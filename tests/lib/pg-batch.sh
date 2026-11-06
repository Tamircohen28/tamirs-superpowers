#!/usr/bin/env bash
# pg-batch.sh — the permission suites' batch runner and agreement check for hooks/permission-guard.sh (PG).
#
# Sourced by tests/test-permission-fuzz.sh and tests/test-permission-guard.sh, never executed. Both suites
# judge their bulk through PG's batch entries (--judge-batch, --classify-batch: NDJSON in, one answer line
# per input line, in order, the engine started once per process) and keep a seeded sample of the same calls
# on the real single-call path, which must agree with the batch line for line. One implementation of each
# half, here, so the two suites cannot drift from each other.
#
# pg_batch_jobs
#     how many batch processes to run side by side: FUZZ_JOBS, or min(cpus, 8). Per-line cost in batch is
#     the bash tokeniser and the resolver, so the saving comes from sharding, not from one process.
#
# pg_batch_run <hook> <judge|classify> <in.ndjson> <out.ndjson> [jobs]
#     shards in.ndjson into `jobs` contiguous chunks, runs `bash <hook> --<mode>-batch` on each at once and
#     writes out.ndjson: exactly one line per input line, in input order. Returns 1 when any shard exited
#     non-zero or printed a line count other than it read (the runner never pads: a short shard is a
#     failure, so a verdict can never be read from the wrong line), 2 on a usage or temp-dir error.
#
# pg_batch_agree <hook> <judge|classify> <in.ndjson> <out.ndjson> <all|N> <seed> <report> [jobs]
#     the divergence detector. Picks N distinct input lines (all of them for `all`) with Python's
#     random.Random(seed) — the same N, seed and line count pick the same lines, so a suite can sample the
#     same calls across several batch files — and runs each through the real single-call path: a
#     {"cmd","cwd","host"} line becomes the host's own shell payload on the hook's stdin (judge) or
#     `--classify <cmd> <cwd>` under PG_HOST=<host> (classify); a full payload line goes to the hook's stdin
#     as it is (judge) or is classified by its tool_input.command (classify). Each answer, and the batch line
#     for it, is read as JSON and compared in a canonical form; a non-JSON answer is compared as text; a
#     single call that exits non-zero differs by construction. A first mismatch is asked once more on the
#     single-call side (the tokeniser's deadline under parallel load is a deny the suites have seen once; a
#     real divergence repeats) and counted only when it repeats. Writes <report>: one
#     "DIFF\t<line>\t<single>\t<batch>" per divergence (both in the canonical form), then
#     "AGREE\t<checked>\t<diffs>"; prints the same summary line; returns 1 when any line diverged, 2 when the
#     batch file has a different line count from the input.
#
#     The canonical form: a judge answer is compared as its decision (permissionDecision; Cursor's
#     permission; {} is a pass), its shape (the key sets, hookEventName) and its whole reason text; a classify
#     answer as the whole object with every list sorted (set-valued fields such as `ids`). Reasons are
#     compared in full because the engine now orders tied ids deterministically (objective/ci-speed e4cfb3e:
#     JOBS are sorted before every max(); measured 2026-11-05, the same command named "workflow.edit" or
#     "file.write.remote" in 3 of 6 single calls before that fix). A batch that passes where the hook asks or
#     denies, asks where it denies, prints another host's shape, answers every line with a fail-closed deny,
#     names another action or another command, or returns the lines out of order is caught
#     (tests/test-permission-fuzz.sh plants each).
#
# The real-hook path of a single call is the suites' own: the hook's stdin, no arguments, the environment of
# the calling suite (TAMIRS_PERMISSION_TEST_ROOT applies to every process here, batch or single, because all
# of them descend from the suite: scripts/lib/permission-common.sh rule 4).
#
# Bash 3.2 compatible; needs python3 (stdlib) and split.
# shellcheck shell=bash

pg_batch_jobs() {
  if [ -n "${FUZZ_JOBS:-}" ]; then printf '%s\n' "$FUZZ_JOBS"; return 0; fi
  python3 -c 'import os; print(min(os.cpu_count() or 2, 8))' 2>/dev/null || echo 2
}

pg_batch_run() {
  local hook="$1" mode="$2" in="$3" out="$4" jobs="${5:-}" d n per c rc want got fail=0
  local chunks=()
  case "$mode" in judge|classify) ;; *) echo "pg_batch_run: mode must be judge or classify, not '$mode'" >&2; return 2 ;; esac
  [ -f "$in" ] || { echo "pg_batch_run: no input file $in" >&2; return 2; }
  [ -n "$jobs" ] || jobs="$(pg_batch_jobs)"
  case "$jobs" in ''|*[!0-9]*|0) jobs=1 ;; esac
  d="$(mktemp -d "${TMPDIR:-/tmp}/pg-batch-run.XXXXXX")" || return 2
  # The batch counts a final unterminated line as one; split does too, but a terminated file is one fewer
  # thing to reason about.
  if [ -s "$in" ] && [ -n "$(tail -c 1 "$in")" ]; then { cat "$in"; echo; } > "$d/in"; else cp "$in" "$d/in"; fi
  n="$(wc -l < "$d/in" | tr -d ' ')"
  : > "$out"
  if [ "$n" -eq 0 ]; then rm -rf "$d"; return 0; fi
  per=$(( (n + jobs - 1) / jobs ))
  ( cd "$d" && split -l "$per" -a 4 in chunk. ) || { rm -rf "$d"; return 2; }
  chunks=("$d"/chunk.*)
  for c in "${chunks[@]}"; do
    ( bash "$hook" "--$mode-batch" < "$c" > "$c.out" 2> "$c.err"; echo $? > "$c.rc" ) &
  done
  wait
  for c in "${chunks[@]}"; do
    want="$(wc -l < "$c" | tr -d ' ')"
    got="$(wc -l < "$c.out" | tr -d ' ')"
    rc="$(cat "$c.rc" 2>/dev/null || echo 1)"
    if [ "$rc" != 0 ] || [ "$want" != "$got" ]; then
      echo "pg_batch_run: $(basename "$c") ($mode): exit $rc, printed $got lines for $want read; stderr tail: $(tail -n 2 "$c.err" 2>/dev/null | tr '\n' ' ' | head -c 300)" >&2
      fail=1
    fi
    cat "$c.out" >> "$out"
  done
  rm -rf "$d"
  return "$fail"
}

pg_batch_agree() {
  local hook="$1" mode="$2" in="$3" out="$4" sample="$5" seed="$6" report="$7" jobs="${8:-}"
  case "$mode" in judge|classify) ;; *) echo "pg_batch_agree: mode must be judge or classify, not '$mode'" >&2; return 2 ;; esac
  [ -n "$jobs" ] || jobs="$(pg_batch_jobs)"
  python3 - "$hook" "$mode" "$in" "$out" "$sample" "$seed" "$report" "$jobs" <<'PY'
import json, os, random, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

hook, mode, inp, outp, sample, seed, report, jobs = sys.argv[1:9]


def lines_of(path):
    text = open(path, encoding="utf-8", errors="surrogateescape").read()
    if text.endswith("\n"):
        text = text[:-1]
    return text.split("\n") if text else []


lines_in, lines_out = lines_of(inp), lines_of(outp)
if len(lines_in) != len(lines_out):
    with open(report, "w", encoding="utf-8") as f:
        f.write("COUNT\t%d\t%d\n" % (len(lines_in), len(lines_out)))
    print("pg_batch_agree: %d input lines but %d batch lines" % (len(lines_in), len(lines_out)))
    sys.exit(2)
n = len(lines_in)
if sample == "all":
    picked = list(range(n))
else:
    k = min(int(sample), n)
    picked = sorted(random.Random(int(seed)).sample(range(n), k))


def short_payload(o, host, cwd):
    """The host's shell payload a {"cmd","cwd","host"} line becomes (the batch's pg_short)."""
    claude = {"cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": o["cmd"]}}
    if host == "claude":
        return claude
    if host == "codex":
        return dict(claude, turn_id="batch")
    if host == "opencode":
        return dict(claude, host="opencode")
    if host == "cursor":
        p = {"conversation_id": "batch", "hook_event_name": "beforeShellExecution", "workspace_roots": [cwd],
             "cwd": cwd, "command": o["cmd"]}
        if isinstance(o.get("cursor_version"), str):
            p["cursor_version"] = o["cursor_version"]
        return p
    return None


def single(line):
    """(rc, stdout) of the real single-call path for one batch line; None when the line has no such form."""
    try:
        o = json.loads(line)
    except ValueError:
        o = None
    is_obj = isinstance(o, dict)
    short = is_obj and isinstance(o.get("cmd"), str) and not any(k in o for k in ("tool_name", "hook_event_name", "command"))
    env = dict(os.environ)
    if mode == "classify":
        if short:
            cmd, host = o["cmd"], o.get("host") or env.get("PG_HOST", "claude")
        elif is_obj and isinstance((o.get("tool_input") or {}).get("command"), str):
            cmd, host = o["tool_input"]["command"], env.get("PG_HOST", "claude")
        else:
            return None
        cwd = o.get("cwd") if isinstance(o.get("cwd"), str) and o.get("cwd") else os.getcwd()
        env["PG_HOST"] = host
        r = subprocess.run(["bash", hook, "--classify", cmd, cwd], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           env=env, timeout=60)
        return r.returncode, r.stdout
    if short:
        cwd = o.get("cwd") if isinstance(o.get("cwd"), str) and o.get("cwd") else os.getcwd()
        p = short_payload(o, o.get("host") or "claude", cwd)
        if p is None:
            return None
        payload = json.dumps(p).encode("utf-8")
    else:
        payload = line.encode("utf-8", "surrogateescape")
    r = subprocess.run(["bash", hook], input=payload, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    return r.returncode, r.stdout


def sort_lists(o):
    if isinstance(o, dict):
        return dict((k, sort_lists(v)) for k, v in o.items())
    if isinstance(o, list):
        return sorted((sort_lists(x) for x in o), key=lambda x: json.dumps(x, sort_keys=True))
    return o


def reason_parts(reason):
    """The whole reason (the header): tied ids are ordered deterministically by the engine."""
    return {"reason": reason if isinstance(reason, str) else None}


def canon(rc, data):
    """The canonical form of an answer (the header's 'canonical form')."""
    t = data.decode("utf-8", "replace").strip()
    try:
        d = json.loads(t)
    except ValueError:
        d = None
        c = t
    if d is not None and mode == "classify":
        c = json.dumps(sort_lists(d), sort_keys=True, separators=(",", ":"))
    elif isinstance(d, dict):
        h = d.get("hookSpecificOutput")
        if isinstance(h, dict):   # Claude Code / Codex / Gemini / OpenCode: an ask or a deny
            c = {"keys": sorted(d), "hook_keys": sorted(h), "event": h.get("hookEventName"),
                 "decision": h.get("permissionDecision", "allow")}
            c.update(reason_parts(h.get("permissionDecisionReason")))
        elif "permission" in d:   # Cursor's shape
            c = {"keys": sorted(d), "decision": d.get("permission")}
            c.update(reason_parts(d.get("user_message")))
        else:                     # {} is the allow of every other host
            c = {"keys": sorted(d), "decision": "allow"}
        c = json.dumps(c, sort_keys=True, separators=(",", ":"))
    elif d is not None:
        c = json.dumps(d, sort_keys=True, separators=(",", ":"))
    return c if rc == 0 else "exit %d: %s" % (rc, c)


def check(i):
    b = canon(0, lines_out[i].encode("utf-8", "surrogateescape"))
    for attempt in (1, 2):
        s = single(lines_in[i])
        if s is None:
            return i, "no single-call form for this line", b
        s = canon(*s)
        if s == b:
            return i, None, None
    return i, s, b


with ThreadPoolExecutor(max_workers=max(1, int(jobs))) as ex:
    results = list(ex.map(check, picked))
diffs = [(i, s, b) for i, s, b in results if s is not None]
with open(report, "w", encoding="utf-8") as f:
    for i, s, b in diffs:
        f.write("DIFF\t%d\t%s\t%s\n" % (i + 1, s.replace("\t", " ").replace("\n", " "), b.replace("\t", " ").replace("\n", " ")))
    f.write("AGREE\t%d\t%d\n" % (len(picked), len(diffs)))
print("AGREE\t%d\t%d" % (len(picked), len(diffs)))
sys.exit(1 if diffs else 0)
PY
}
