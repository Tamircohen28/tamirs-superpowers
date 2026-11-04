#!/usr/bin/env bash
# test-doctor-permissions.sh — scripts/doctor.sh reports each host CLI's version against its
# permission-levels floor (ADR 004 D9): platform-targets.json permissions_min, and Cursor's
# permissions_min_cli for cursor-agent.
#
# WHAT IT HOLDS
#   1. a host at or above its floor is ok; one below it is a warning that names the feature
#      the floor stands for (Claude Code also its lower floors: onFailure "block" at 2.1.295,
#      the permission_level options picker at 2.1.271), a remedy, and a Summary line, and
#      doctor still exits 0 (an optional feature, not a broken install);
#   2. Cursor's two floors: cursor-agent against permissions_min_cli, the desktop app against
#      permissions_min, its version read from the bundle's package.json: `cursor` (whose
#      launcher shim can block) is never run;
#   3. an unreadable version is a warning only, no host CLI at all is "n/a", and a CLI that
#      hangs on --version is killed at the probe deadline (DOCTOR_PROBE_SECONDS, at most 3 s)
#      with every process it started, reported "version unknown (probe timed out)";
#   4. the floors come from this plugin's platform-targets.json (a changed floor changes the
#      verdict), and where the engineering docs did not ship, from the registry's
#      permission_levels `since`; a floor neither records is "not recorded";
#   5. every fake host was run with --version and nothing else.
#
# HERMETIC
#   Every run is `env -i` with PATH = the fake hosts + a directory of links to the system
#   tools doctor needs (never ~/.local/bin or any real tool dir), so no real claude, codex,
#   cursor, cursor-agent, gemini, opencode or gh is ever found; HOME is a temp dir and the
#   Cursor app dirs are DOCTOR_CURSOR_APP_DIRS under it. The fakes print a version from a
#   file (or sleep, to prove the deadline) and log their argv. No network, no model call,
#   no host session.
#
# Bash 3.2 compatible.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require jq awk

T="$(harness_tmpdir)"
DOCTOR="$ROOT/scripts/doctor.sh"
PLAIN="$T/plain"
mkdir -p "$PLAIN" "$T/home" "$T/tmp"
printf '# an ordinary repo\n' > "$PLAIN/README.md"

# The system tools doctor runs, linked by absolute path; the host CLIs are never among them.
SYS="$T/sys"
mkdir -p "$SYS"
for tool in bash sh env jq awk sed grep head tail find sort tr cat dirname basename git date mkdir rm \
  wc cut uname id ls mktemp readlink python3 tput sleep; do
  p="$(command -v "$tool" 2>/dev/null || true)"
  case "$p" in /*) ln -sf "$p" "$SYS/$tool" ;; esac
done
for host in claude codex cursor-agent cursor gemini opencode gh; do
  [ -e "$SYS/$host" ] && { echo "FATAL: $host leaked into the system-tool dir" >&2; exit 2; }
done
SYS_NOJQ="$T/sys-nojq"
mkdir -p "$SYS_NOJQ"
for f in "$SYS"/*; do [ "$(basename "$f")" = jq ] || ln -sf "$(readlink "$f")" "$SYS_NOJQ/$(basename "$f")"; done

# fakes <name=version>... — a fresh bin dir holding only the named host CLIs, plus a gh that
# fails at once (doctor's `gh auth status` must not reach the network). An empty version means
# the CLI prints nothing; @hang means it never answers (it sleeps, in a child process).
# app=<version> is the Cursor desktop app: a bundle package.json under the temp HOME.
BIN="$T/bin"
APPDIRS="$T/home/no-app"
fakes() {
  local kv name ver
  rm -rf "$BIN" "$T/home/app"; mkdir -p "$BIN" "$T/ver"
  : > "$T/calls.log"
  APPDIRS="$T/home/no-app"
  printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"
  for kv in "$@"; do
    name="${kv%%=*}"; ver="${kv#*=}"
    if [ "$name" = app ]; then
      mkdir -p "$T/home/app"
      printf '{"name": "cursor", "version": "%s"}\n' "$ver" > "$T/home/app/package.json"
      APPDIRS="$T/home/no-app:$T/home/app"
      continue
    fi
    printf '%s\n' "$ver" > "$T/ver/$name"
    if [ "$ver" = @hang ]; then
      printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\nsleep 6011\n' "$name" "$T/calls.log" > "$BIN/$name"
    else
      cat > "$BIN/$name" <<SH
#!/bin/sh
printf '%s %s\n' "$name" "\$*" >> "$T/calls.log"
cat "$T/ver/$name"
SH
    fi
    chmod +x "$BIN/$name"
  done
}

OUT="" RC=0 PROBE=""
# doctor [sys-dir] [doctor-path] — the permission section of one hermetic run, in OUT; full log in
# $T/doctor.out. PROBE, when set, is DOCTOR_PROBE_SECONDS.
doctor() {
  env -i PATH="$BIN:${1:-$SYS}" HOME="$T/home" TMPDIR="$T/tmp" LANG=C DOCTOR_CURSOR_APP_DIRS="$APPDIRS" \
    ${PROBE:+DOCTOR_PROBE_SECONDS="$PROBE"} bash "${2:-$DOCTOR}" "$PLAIN" </dev/null > "$T/doctor.out" 2>&1
  RC=$?
  OUT="$(sed -n '/== Permission levels/,/== Summary/p' "$T/doctor.out")"
}

section "hermetic: the test PATH reaches no real host CLI"
judge "no host CLI resolves through the system-tool links" "" \
  "$(env -i PATH="$SYS" /bin/sh -c 'for h in claude codex cursor cursor-agent gemini opencode gh agy; do command -v "$h"; done' 2>/dev/null || true)"
judge "the test PATH holds no ~/.local/bin and no real tool dir" "$T/bin:$T/sys" "$BIN:$SYS"
line() { printf '%s\n' "$OUT" | grep -F "$1" | head -1; }

floor() { jq -r --arg t "$1" --arg f "${2:-permissions_min}" '.targets[$t][$f]' "$ROOT/docs/engineering/build-and-release/platform-targets.json"; }
CC="$(floor claude_code)"; CX="$(floor codex)"; CU="$(floor cursor)"; CUC="$(floor cursor permissions_min_cli)"
GM="$(floor gemini_cli)"; OC="$(floor opencode)"
section "the suite reads the floors it tests against"
for v in "$CC" "$CX" "$CU" "$CUC" "$GM" "$OC"; do
  case "$v" in [0-9]*.[0-9]*) ;; *) echo "FATAL: a floor in platform-targets.json is unreadable ($v)" >&2; exit 2 ;; esac
done
ok "floors: claude_code $CC, codex $CX, cursor $CU / cli $CUC, gemini_cli $GM, opencode $OC"

# --- 1. at, above and below the floor ------------------------------------------------------
section "every host at its floor is ok"
fakes "claude=$CC (Claude Code)" "codex=codex-cli $CX" "cursor-agent=$CUC-6d2e1c3" "app=$CU" "gemini=$GM" "opencode=$OC"
doctor
judge "doctor exits 0" 0 "$RC"
for l in "Claude Code $CC meets the floor $CC" "Codex CLI $CX meets the floor $CX" "Cursor CLI $CUC meets the floor $CUC" \
  "Cursor desktop $CU meets the floor $CU" "Gemini CLI $GM meets the floor $GM" "OpenCode $OC meets the floor $OC"; do
  judge "ok: $l" yes "$(has "$(line "$l")" "ok")"
done
judge "no warning at the floors" no "$(has "$OUT" "below the floor")"

section "below the floor: a warning naming the feature, a remedy, a Summary line, exit 0"
fakes "claude=2.1.300 (Claude Code)"
doctor
judge "doctor still exits 0 (optional feature)" 0 "$RC"
w="$(line "Claude Code 2.1.300 is below the floor $CC")"
judge "warns: Claude Code 2.1.300 below $CC" yes "$(has "$w" "warn")"
judge "  ... names the ask dialog under bypassPermissions" yes "$(has "$w" "bypassPermissions")"
judge "  ... names where the floor came from" yes "$(has "$w" "platform-targets.json, ADR 004 D9")"
judge "  ... not the onFailure floor (2.1.300 >= 2.1.295)" no "$(has "$OUT" "onFailure")"
judge "  ... a remedy that names supervised" yes "$(has "$OUT" "remedy: upgrade Claude Code to $CC or later; until then keep the level at supervised")"
judge "  ... and a Summary line" yes "$(has "$(sed -n '/== Summary/,$p' "$T/doctor.out")" "permission levels on Claude Code 2.1.300")"
fakes "claude=2.1.290 (Claude Code)"
doctor
judge "Claude Code 2.1.290: also below onFailure \"block\" (2.1.295)" yes "$(has "$OUT" "fails OPEN if it cannot start")"
judge "  ... not the options picker (2.1.290 >= 2.1.271)" no "$(has "$OUT" "options picker")"
fakes "claude=2.1.250 (Claude Code)"
doctor
judge "Claude Code 2.1.250: also the permission_level options picker (C2)" yes "$(has "$OUT" "permission_level options picker does not load")"
fakes "claude=2.2.0 (Claude Code)"
doctor
judge "Claude Code 2.2.0: above the floor is ok" yes "$(has "$(line "Claude Code 2.2.0 meets")" "ok")"
fakes "claude=$CC.1 (Claude Code)"
doctor
judge "a longer version at the floor's prefix is not below it" yes "$(has "$(line "meets the floor $CC")" "ok")"
fakes "codex=codex-cli 0.150.0"
doctor
judge "Codex 0.150.0: below $CX, names the deny-only contract" yes "$(has "$(line "Codex CLI 0.150.0 is below the floor $CX")" "deny-only hook contract")"
fakes "gemini=0.60.0" "opencode=2.2.4"
doctor
judge "Gemini 0.60.0: below $GM, names ask_user" yes "$(has "$(line "Gemini CLI 0.60.0 is below the floor $GM")" "ask_user")"
judge "OpenCode 2.2.4: below $OC, names --auto" yes "$(has "$(line "OpenCode 2.2.4 is below the floor $OC")" "--auto")"

# --- 2. Cursor's two floors -----------------------------------------------------------------
section "Cursor: cursor-agent against permissions_min_cli, the desktop app against permissions_min"
fakes "cursor-agent=2026.09.30-abc1234" "app=3.26.1"
doctor
judge "cursor-agent 2026.09.30: below the CLI floor $CUC" yes "$(has "$(line "Cursor CLI 2026.09.30 is below the floor $CUC")" "U1")"
judge "cursor 3.26.1: below the desktop floor $CU" yes "$(has "$(line "Cursor desktop 3.26.1 is below the floor $CU")" "S2")"
fakes "cursor-agent=$CUC-abc1234" "app=$CU"
doctor
judge "the two Cursor floors are not crossed (each ok at its own)" "yes yes" \
  "$(has "$(line "Cursor CLI $CUC meets")" ok) $(has "$(line "Cursor desktop $CU meets")" ok)"

# --- 3. unreadable, none, no jq ---------------------------------------------------------------
section "an unreadable version warns only; no host is n/a"
fakes "claude=dev build"
doctor
judge "unreadable: a warning, not a verdict" yes "$(has "$(line "Claude Code version unreadable")" "a warning only")"
judge "  ... exit 0" 0 "$RC"
fakes "opencode="
doctor
judge "a CLI that prints nothing reads as unreadable" yes "$(has "$OUT" "OpenCode version unreadable")"
fakes
doctor
judge "no host CLI: n/a" yes "$(has "$OUT" "no host CLI on PATH to compare")"
fakes "claude=2.1.300 (Claude Code)"
doctor "$SYS_NOJQ"
judge "no jq: the floors are not read, and doctor says so" yes "$(has "$OUT" "needs jq to read them")"

# --- 4. where the floors come from ------------------------------------------------------------
section "the floors are read, not hard-coded: platform-targets.json, else the registry"
mk_plugin() { # mk_plugin <dir> [with-targets] — doctor.sh with this plugin's registry (and targets)
  mkdir -p "$1/scripts" "$1/core/capabilities"
  cp "$DOCTOR" "$1/scripts/doctor.sh"
  cp "$ROOT/core/capabilities/platforms.json" "$1/core/capabilities/"
  if [ -n "${2:-}" ]; then
    mkdir -p "$1/docs/engineering/build-and-release"
    jq '.targets.claude_code.permissions_min = "9.9.9"' "$ROOT/docs/engineering/build-and-release/platform-targets.json" \
      > "$1/docs/engineering/build-and-release/platform-targets.json"
  fi
}
mk_plugin "$T/p-targets" yes
fakes "claude=$CC (Claude Code)"
doctor "$SYS" "$T/p-targets/scripts/doctor.sh"
judge "a raised permissions_min in platform-targets.json moves the verdict" yes "$(has "$(line "Claude Code $CC is below the floor 9.9.9")" "warn")"
mk_plugin "$T/p-dist"
fakes "claude=2.1.300 (Claude Code)" "cursor-agent=$CUC-abc1234" "codex=codex-cli $CX"
doctor "$SYS" "$T/p-dist/scripts/doctor.sh"
judge "no engineering docs (a distribution): the registry's permission_levels since is the floor" yes \
  "$(has "$(line "Claude Code 2.1.300 is below the floor $CC")" "core/capabilities/platforms.json")"
judge "  ... and it agrees for Codex" yes "$(has "$(line "Codex CLI $CX meets the floor $CX")" "ok")"
judge "  ... the CLI floor only platform-targets.json records is 'not recorded'" yes "$(has "$OUT" "Cursor CLI floor (permissions_min_cli) is not recorded in this install")"
mkdir -p "$T/p-bare/scripts"; cp "$DOCTOR" "$T/p-bare/scripts/doctor.sh"
doctor "$SYS" "$T/p-bare/scripts/doctor.sh"
judge "neither file: said, not guessed" yes "$(has "$OUT" "neither platform-targets.json nor core/capabilities/platforms.json")"
mkdir -p "$PLAIN/docs/engineering/build-and-release"
printf '{"targets": {"claude_code": {"permissions_min": "9.9.9"}}}\n' > "$PLAIN/docs/engineering/build-and-release/platform-targets.json"
fakes "claude=$CC (Claude Code)"
doctor
judge "the floors are this plugin's, never the inspected repo's" yes "$(has "$(line "Claude Code $CC meets the floor $CC")" "ok")"
rm -rf "$PLAIN/docs"

section "a CLI that hangs on --version: killed at the probe deadline, reported, never waited on"
fakes "claude=@hang" "codex=codex-cli $CX"
t0="$(date +%s)"; PROBE=1 doctor; t1="$(date +%s)"; PROBE=""
judge "doctor still finishes, exit 0" 0 "$RC"
judge "  ... in seconds, not minutes (took $((t1 - t0)) s)" yes "$([ $((t1 - t0)) -lt 15 ] && echo yes || echo no)"
judge "  ... the hung host: version unknown (probe timed out)" yes "$(has "$OUT" "Claude Code version unknown (probe timed out) after 1s")"
judge "  ... a warning only, its floor not checked" yes "$(has "$(line "Claude Code version unknown")" "a warning only")"
judge "  ... the detected-platform line says so too" yes "$(has "$(cat "$T/doctor.out")" "claude_code (CLI: version unknown (probe timed out))")"
judge "  ... the other hosts are still checked" yes "$(has "$(line "Codex CLI $CX meets")" ok)"
sleep 1
judge "  ... and the probe died with the process it started" "" "$(pgrep -f 'sleep 6011' 2>/dev/null || true)"
fakes "claude=@hang"
t0="$(date +%s)"; doctor; t1="$(date +%s)"
judge "the default deadline is 3 s (took $((t1 - t0)) s, under 10)" yes "$([ $((t1 - t0)) -lt 10 ] && echo yes || echo no)"
judge "  ... and says so" yes "$(has "$OUT" "probe timed out) after 3s")"
fakes "claude=@hang"
PROBE=30 doctor; PROBE=""
judge "DOCTOR_PROBE_SECONDS above 3 is held to 3" yes "$(has "$OUT" "probe timed out) after 3s")"
pkill -f 'sleep 6011' 2>/dev/null || true

# --- 5. the hosts were only asked their version ----------------------------------------------
section "the fake hosts saw --version and nothing else; the Cursor app is never run"
fakes "claude=$CC (Claude Code)" "codex=codex-cli $CX" "cursor-agent=$CUC-6d2e1c3" "cursor=@hang" "app=$CU" "gemini=$GM" "opencode=$OC"
doctor
judge "every call was <host> --version" "" "$(grep -v -- ' --version$' "$T/calls.log" || true)"
judge "a \`cursor\` on PATH (one that would hang) is never run: the app version came from its bundle" "no yes" \
  "$(grep -q '^cursor ' "$T/calls.log" && echo yes || echo no) $(has "$(line "Cursor desktop $CU meets")" ok)"
judge "each host was asked once" "claude codex cursor-agent gemini opencode" \
  "$(cut -d' ' -f1 "$T/calls.log" | sort | uniq -c | awk '$1 == 1 { print $2 }' | tr '\n' ' ' | sed 's/ $//')"

harness_summary
