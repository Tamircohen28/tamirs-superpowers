#!/usr/bin/env bash
# test-evals-suite.sh — static shape checks for the `claude plugin eval` suite in evals/.
#
# WHY STATIC ONLY
#   The suite itself needs a model (cases × runs × 2 arms, plus judge votes), so it runs
#   nightly from .github/workflows/evals.yml with an API key, not on every push. What CAN
#   run on every push, for free, is the set of mistakes that make a nightly run fail for
#   a reason that has nothing to do with the plugin: a case with no grader (the loader
#   rejects it), an `llm` grader with no rubric (the judge has nothing to vote on), a case
#   that writes under .claude/ (denied in the run sandbox and indistinguishable from the
#   plugin failing — it cost the first calibration a full cycle), a negative that is not
#   tagged (so `--tag negative` silently drops it), or a case the README forgot to list.
#   This suite catches those at `make validate` time. It makes no model call and never
#   invokes `claude`.
#
# WHAT IT ASSERTS
#   - every case directory under evals/ has a prompt.md or a case.yaml, and at least one
#     grader (graders/*.md, or a `graders:` list in case.yaml);
#   - every grader has a known `type`, and every `llm` grader has a non-empty rubric;
#   - every `tool_used` grader on `Skill` declares its arm explicitly: `with-only` for a
#     fire case (an indicator, not a score) or `both` with min/max 0 for a negative;
#   - no prompt, grader or mock names a path under .claude/ as somewhere to write;
#   - every case whose name says `neg` carries the `negative` tag, and vice versa;
#   - the README's case table lists every case directory;
#   - a mocks/ directory, if present, has a README, mocks only servers .mcp.json declares,
#     and every mock file has a body.
#
# Usage: bash tests/test-evals-suite.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require python3 jq
cd "$REPO_ROOT" || exit 1

python3 -c "import yaml" >/dev/null 2>&1 \
  || { echo "FATAL: PyYAML is required (pip install -r scripts/requirements-validate.txt)"; exit 1; }

EVAL_DIR="evals"
judge "the eval directory exists" yes "$(exists "$EVAL_DIR")"
judge "the suite README exists" yes "$(exists "$EVAL_DIR/README.md")"

# Extract the whole suite into one JSON document with a single Python pass, then assert
# over it with jq. One parser, one place to fix when the case format moves.
META="$(harness_tmpdir)/evals.json"
python3 - "$EVAL_DIR" > "$META" <<'PY'
import json, os, re, sys
import yaml

root = sys.argv[1]
FM = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n?(.*)\Z", re.S)

def split(path):
    text = open(path, encoding="utf-8").read()
    m = FM.match(text)
    if not m:
        return None, text, "no frontmatter"
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except Exception as e:  # noqa: BLE001
        return None, m.group(2), f"yaml: {e}"
    if not isinstance(fm, dict):
        return None, m.group(2), "frontmatter is not a mapping"
    return fm, m.group(2), None

cases = []
for name in sorted(os.listdir(root)):
    d = os.path.join(root, name)
    if not os.path.isdir(d) or name in ("mocks", "results") or name.startswith("."):
        continue
    prompt = os.path.join(d, "prompt.md")
    cyaml = os.path.join(d, "case.yaml")
    case = {"dir": name, "has_prompt": os.path.isfile(prompt), "has_case_yaml": os.path.isfile(cyaml),
            "tags": [], "errors": [], "graders": [], "text_files": []}
    if case["has_prompt"]:
        fm, body, err = split(prompt)
        if err:
            case["errors"].append(f"prompt.md: {err}")
        else:
            case["tags"] += list(fm.get("tags") or [])
            case["prompt_name"] = fm.get("name")
            case["allowed_tools"] = fm.get("allowed_tools") or []
            case["prompt_body_len"] = len(body.strip())
        case["text_files"].append(prompt)
    if case["has_case_yaml"]:
        try:
            cy = yaml.safe_load(open(cyaml, encoding="utf-8")) or {}
            case["tags"] += list(cy.get("tags") or [])
            for g in cy.get("graders") or []:
                case["graders"].append({"name": f"case.yaml:{g.get('name')}", "type": g.get("type"),
                                        "tool": g.get("tool"), "arm": g.get("arm"),
                                        "min": g.get("min"), "max": g.get("max"),
                                        "rubric_len": len((g.get("criteria") or "").strip())})
        except Exception as e:  # noqa: BLE001
            case["errors"].append(f"case.yaml: {e}")
        case["text_files"].append(cyaml)
    gdir = os.path.join(d, "graders")
    if os.path.isdir(gdir):
        for g in sorted(os.listdir(gdir)):
            if not g.endswith(".md"):
                continue
            gp = os.path.join(gdir, g)
            fm, body, err = split(gp)
            entry = {"name": g, "type": None, "tool": None, "arm": None, "min": None, "max": None,
                     "rubric_len": len(body.strip()), "error": err}
            if fm is not None:
                entry.update({"type": fm.get("type"), "tool": fm.get("tool"), "arm": fm.get("arm"),
                              "min": fm.get("min"), "max": fm.get("max")})
            case["graders"].append(entry)
            case["text_files"].append(gp)
    cases.append(case)

mocks = {"present": os.path.isdir(os.path.join(root, "mocks")), "readme": False, "servers": [], "files": []}
if mocks["present"]:
    mroot = os.path.join(root, "mocks")
    mocks["readme"] = os.path.isfile(os.path.join(mroot, "README.md"))
    for s in sorted(os.listdir(mroot)):
        sp = os.path.join(mroot, s)
        if not os.path.isdir(sp) or s.startswith("."):
            continue
        mocks["servers"].append(s)
        for t in sorted(os.listdir(sp)):
            if not t.endswith(".md"):
                continue
            tp = os.path.join(sp, t)
            fm, body, err = split(tp)
            mocks["files"].append({"path": tp, "server": s, "error": err, "body_len": len(body.strip()),
                                   "type": (fm or {}).get("type", "fixed")})

print(json.dumps({"cases": cases, "mocks": mocks}))
PY
judge "the suite parsed into JSON" 0 "$(jq empty "$META" >/dev/null 2>&1; echo $?)"

ncases="$(jq '.cases | length' "$META")"
judge "at least one case exists" yes "$(if [ "$ncases" -gt 0 ]; then echo yes; else echo no; fi)"

# ---------------------------------------------------------------------------
section "every case has a prompt and at least one grader"

judge "every case directory has prompt.md or case.yaml" "" \
  "$(jq -r '.cases[] | select((.has_prompt or .has_case_yaml) | not) | .dir' "$META")"
judge "every case file parsed (frontmatter + YAML)" "" \
  "$(jq -r '.cases[] | select(.errors | length > 0) | "\(.dir): \(.errors | join("; "))"' "$META")"
judge "every prompt.md has a non-empty prompt body" "" \
  "$(jq -r '.cases[] | select(.has_prompt and ((.prompt_body_len // 0) == 0)) | .dir' "$META")"
judge "every case has at least one grader" "" \
  "$(jq -r '.cases[] | select(.graders | length == 0) | .dir' "$META")"
judge "every grader file parsed" "" \
  "$(jq -r '.cases[] | .dir as $d | .graders[] | select(.error != null) | "\($d)/\(.name): \(.error)"' "$META")"

# ---------------------------------------------------------------------------
section "grader types and rubrics"

KNOWN='["regex","tool_used","tool_order","file_exists","llm","baseline"]'
judge "every grader has a known type" "" \
  "$(jq -r --argjson k "$KNOWN" '.cases[] | .dir as $d | .graders[] | select((.type // "") as $t | ($k | index($t)) == null) | "\($d)/\(.name): \(.type)"' "$META")"
judge "every llm grader has a rubric" "" \
  "$(jq -r '.cases[] | .dir as $d | .graders[] | select(.type == "llm" and .rubric_len == 0) | "\($d)/\(.name)"' "$META")"
judge "every tool_used grader names a tool" "" \
  "$(jq -r '.cases[] | .dir as $d | .graders[] | select(.type == "tool_used" and ((.tool // "") == "")) | "\($d)/\(.name)"' "$META")"

# A `tool_used` grader on Skill can never pass without the plugin. The harness already
# excludes it from a two-arm score, but the file must say which way it is meant: an
# indicator (with-only) on a fire case, or a scored must-not (both, 0..0) on a negative.
judge "every tool_used: Skill grader declares arm: with-only or arm: both" "" \
  "$(jq -r '.cases[] | .dir as $d | .graders[] | select(.type == "tool_used" and .tool == "Skill" and ((.arm // "") | IN("with-only","both") | not)) | "\($d)/\(.name): arm=\(.arm)"' "$META")"
judge "every arm: both Skill grader is a must-not (min 0, max 0)" "" \
  "$(jq -r '.cases[] | .dir as $d | .graders[] | select(.type == "tool_used" and .tool == "Skill" and .arm == "both" and ((.min != 0) or (.max != 0))) | "\($d)/\(.name)"' "$META")"

# ---------------------------------------------------------------------------
section "no case writes under .claude/"

# Protected in the run sandbox: every write there is denied, and the result looks exactly
# like the plugin failing. A prompt that says "put it in .claude/skills/x" or a grader that
# reads ".claude/..." back is the mistake this check exists for.
dotclaude=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -nE '(^|[^A-Za-z0-9_./-])\.claude/' "$f" >/dev/null 2>&1; then
    dotclaude="$dotclaude $f"
  fi
done < <(jq -r '.cases[].text_files[]' "$META")
judge "no prompt or grader names a path under .claude/" "" "$dotclaude"

# ---------------------------------------------------------------------------
section "negatives are tagged"

judge "every case whose name says neg carries the negative tag" "" \
  "$(jq -r '.cases[] | select((.dir | test("(^|-)neg(-|$)")) and ((.tags | index("negative")) == null)) | .dir' "$META")"
judge "every negative-tagged case says neg in its name" "" \
  "$(jq -r '.cases[] | select(((.tags | index("negative")) != null) and ((.dir | test("(^|-)neg(-|$)")) | not)) | .dir' "$META")"
judge "every negative has a must-not Skill grader scored in both arms" "" \
  "$(jq -r '.cases[] | select((.tags | index("negative")) != null) | select([.graders[] | select(.type == "tool_used" and .tool == "Skill" and .arm == "both" and .max == 0)] | length == 0) | .dir' "$META")"
judge "every case carries at least one tag" "" \
  "$(jq -r '.cases[] | select(.tags | length == 0) | .dir' "$META")"

# ---------------------------------------------------------------------------
section "the README lists every case"

unlisted=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  grep -qF "\`$d\`" "$EVAL_DIR/README.md" || unlisted="$unlisted $d"
done < <(jq -r '.cases[].dir' "$META")
judge "every case directory appears in the README table" "" "$unlisted"

ghost=""
# shellcheck disable=SC2016  # the backticks in the grep are literal table-cell markup, not a command
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -d "$EVAL_DIR/$d" ] || ghost="$ghost $d"
done < <(grep -oE '^\| `[0-9]{2}-[a-z0-9-]+`' "$EVAL_DIR/README.md" | tr -d '|` ' )
judge "every case the README table names exists on disk" "" "$ghost"

# ---------------------------------------------------------------------------
section "mocks"

if [ "$(jq -r '.mocks.present' "$META")" = "true" ]; then
  judge "evals/mocks/ has a README" true "$(jq -r '.mocks.readme' "$META")"
  declared="$(jq -r '.mcpServers | keys[]' .mcp.json 2>/dev/null | sort | tr '\n' ' ')"
  judge "every mocked server is declared in .mcp.json" "" \
    "$(jq -r --arg d " $declared" '.mocks.servers[] | . as $s | select(($d | index(" " + $s + " ")) == null)' "$META")"
  judge "every mock file parsed" "" \
    "$(jq -r '.mocks.files[] | select(.error != null) | "\(.path): \(.error)"' "$META")"
  judge "every mock file has a body" "" \
    "$(jq -r '.mocks.files[] | select(.body_len == 0) | .path' "$META")"
  judge "every mock type is fixed or agent" "" \
    "$(jq -r '.mocks.files[] | select(.type | IN("fixed","agent") | not) | "\(.path): \(.type)"' "$META")"
  # A `type: agent` mock answers with a judge call per run unless a .replay recording is
  # adopted; CI must not pay for that silently. The mocks README documents how to record.
  agent_mocks="$(jq -r '[.mocks.files[] | select(.type == "agent")] | length' "$META")"
  if [ "$agent_mocks" -gt 0 ] && [ ! -d "$EVAL_DIR/mocks/.replay" ]; then
    warn "$agent_mocks agent mock(s) with no mocks/.replay/ — every CI run pays a judge call per answer; see evals/mocks/README.md"
  fi
else
  skip "mocks checks" "no evals/mocks/ directory"
fi

# ---------------------------------------------------------------------------
section "results are not committed"

judge ".gitignore excludes evals/results/" yes "$(if grep -qE '^evals/results/?$' .gitignore; then echo yes; else echo no; fi)"
judge "no evals/results/ is tracked" "" "$(git ls-files "$EVAL_DIR/results" 2>/dev/null | head -3)"

harness_summary
