#!/usr/bin/env bash
# run-pre-pr-gates.sh — mandatory agent-kit / multi-platform pre-PR validation.
#
# Wired into start-dev (before push/PR), pr-dev (before every push + readiness gate),
# and detect-stack.sh (emitted after make validate when applicable).
#
# Usage:
#   bash skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh [repo-root]
#
# WHY THIS NEVER EXITS 0 ON "I FOUND NOTHING"
#   The previous version ran `make repo-standards-gate` / `agent-polish-gate` /
#   `agent:check` and, when the repo had no Makefile or none of those targets,
#   printed "skipping" and exited 0. Every caller treats exit 0 as "the gate
#   passed", so in essentially every third-party repo a gate documented as
#   MANDATORY was a silent no-op that deliver-dev and pr-dev then reported as
#   having run. Claiming a gate ran that did not is worse than having no gate.
#
#   So: the runner is DERIVED from what the repo actually has (Makefile target,
#   package.json script, justfile recipe, Taskfile task, tox/nox, Cargo, Go
#   module), and when no runner can be found this exits 1 with the named cause
#   and the list of everything that was probed. A repo that genuinely has no
#   gate says so once, explicitly, via SUPERPOWERS_PRE_PR_GATES=none.
#
# Exit 0 when the detected gate passes, or when gates are explicitly declared
#        absent (SUPERPOWERS_PRE_PR_GATES=none).
# Exit 1 when the detected gate fails, OR when no gate could be detected.
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
MAKEFILE="$ROOT/Makefile"
PKG="$ROOT/package.json"

say() { echo "pre-pr-gates: $*"; }

# --- explicit opt-out --------------------------------------------------------
# One deliberate declaration, not a silent fallthrough. Anything else set here
# is a typo and must not be read as consent.
case "${SUPERPOWERS_PRE_PR_GATES:-}" in
  none)
    say "gates explicitly declared absent for this repo (SUPERPOWERS_PRE_PR_GATES=none)."
    say "NO GATE RAN — do not report pre-PR validation as having passed."
    exit 0
    ;;
  "") : ;;
  *)
    say "ERROR: SUPERPOWERS_PRE_PR_GATES='${SUPERPOWERS_PRE_PR_GATES}' is not a recognised value (only 'none')."
    exit 1
    ;;
esac

PROBED=()
probed() { PROBED+=("$1"); }

# make_target <name> — true when the Makefile defines that target. Handles the
# escaped-colon spelling GNU make requires for a target like `agent:check`.
make_target() {
  local t="$1" esc
  [[ -f "$MAKEFILE" ]] || return 1
  esc="${t//:/\\\\?:}"          # `agent:check` -> `agent\\?:check`
  grep -qE "^${esc}:" "$MAKEFILE" 2>/dev/null
}

# pkg_script <name> — true when package.json declares that npm script.
pkg_script() {
  local s="$1"
  [[ -f "$PKG" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    [[ "$(jq -r --arg s "$s" '.scripts[$s] // empty' "$PKG" 2>/dev/null)" != "" ]]
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$PKG" "$s" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if (d.get("scripts") or {}).get(sys.argv[2]) else 1)
PY
  else
    grep -qE "\"$s\"[[:space:]]*:" "$PKG" 2>/dev/null
  fi
}

# file_recipe <file> <name> — a justfile recipe or Taskfile task by name.
file_recipe() {
  local f="$1" n="$2"
  [[ -f "$f" ]] || return 1
  grep -qE "^[[:space:]]*${n}:" "$f" 2>/dev/null
}

# node_pm — the package manager this repo actually uses, not "npm by default".
node_pm() {
  local pm=""
  if [[ -f "$PKG" ]] && command -v jq >/dev/null 2>&1; then
    pm="$(jq -r '.packageManager // empty' "$PKG" 2>/dev/null | cut -d@ -f1)"
  fi
  if [[ -z "$pm" ]]; then
    if   [[ -f "$ROOT/pnpm-lock.yaml" ]];                      then pm=pnpm
    elif [[ -f "$ROOT/yarn.lock" ]];                           then pm=yarn
    elif [[ -f "$ROOT/bun.lockb" || -f "$ROOT/bun.lock" ]];    then pm=bun
    else pm=npm
    fi
  fi
  printf '%s' "$pm"
}

RUNNER=""      # human-readable name of what was detected
CMD=()         # the command to execute

# --- detection: first hit wins, most specific first --------------------------
probed "Makefile targets: repo-standards-gate, agent-polish-gate, agent:check, validate, check, test"
for t in repo-standards-gate agent-polish-gate agent:check validate check test; do
  if make_target "$t"; then
    RUNNER="Makefile target '$t'"
    CMD=(make -C "$ROOT" "$t")
    break
  fi
done

if [[ -z "$RUNNER" ]]; then
  probed "package.json scripts: agent:check, validate, check, test"
  for s in agent:check validate check test; do
    if pkg_script "$s"; then
      pm="$(node_pm)"
      RUNNER="package.json script '$s' (via $pm)"
      case "$s" in
        test) CMD=("$pm" test) ;;
        *)    CMD=("$pm" run "$s") ;;
      esac
      break
    fi
  done
fi

if [[ -z "$RUNNER" ]]; then
  for jf in justfile Justfile .justfile; do
    probed "$jf recipes: agent-check, validate, check, test"
    for n in agent-check validate check test; do
      if file_recipe "$ROOT/$jf" "$n"; then
        RUNNER="$jf recipe '$n'"
        CMD=(just --justfile "$ROOT/$jf" --working-directory "$ROOT" "$n")
        break 2
      fi
    done
  done
fi

if [[ -z "$RUNNER" ]]; then
  for tf in Taskfile.yml Taskfile.yaml; do
    probed "$tf tasks: validate, check, test"
    for n in validate check test; do
      if file_recipe "$ROOT/$tf" "  $n"; then
        RUNNER="$tf task '$n'"
        CMD=(task -d "$ROOT" "$n")
        break 2
      fi
    done
  done
fi

if [[ -z "$RUNNER" ]]; then
  probed "tox.ini / noxfile.py"
  if [[ -f "$ROOT/tox.ini" ]]; then
    RUNNER="tox.ini"
    CMD=(tox -c "$ROOT/tox.ini")
  elif [[ -f "$ROOT/noxfile.py" ]]; then
    RUNNER="noxfile.py"
    CMD=(nox -f "$ROOT/noxfile.py")
  fi
fi

if [[ -z "$RUNNER" ]]; then
  probed "Cargo.toml"
  if [[ -f "$ROOT/Cargo.toml" ]]; then
    RUNNER="Cargo.toml"
    CMD=(cargo test --manifest-path "$ROOT/Cargo.toml")
  fi
fi

if [[ -z "$RUNNER" ]]; then
  probed "go.mod"
  if [[ -f "$ROOT/go.mod" ]]; then
    RUNNER="go.mod"
    CMD=(go test ./...)
  fi
fi

# --- no runner: fail loudly with the named cause -----------------------------
if [[ -z "$RUNNER" ]]; then
  {
    echo "pre-pr-gates: FAILED — no pre-PR gate could be detected in $ROOT."
    echo "pre-pr-gates: probed, and found nothing runnable:"
    printf 'pre-pr-gates:   - %s\n' "${PROBED[@]}"
    echo "pre-pr-gates: NO GATE RAN. Do not report pre-PR validation as having passed."
    echo "pre-pr-gates: remedy — add one of the targets/scripts above, or, if this repo"
    echo "pre-pr-gates:          genuinely has no validation gate, declare it once with"
    echo "pre-pr-gates:          SUPERPOWERS_PRE_PR_GATES=none and say so in the PR."
  } >&2
  exit 1
fi

# --- run it ------------------------------------------------------------------
say "detected $RUNNER"
echo "=== pre-pr-gates: ${CMD[*]} ==="
if ! (cd "$ROOT" && "${CMD[@]}"); then
  say "FAILED ($RUNNER)"
  exit 1
fi
say "passed ($RUNNER)"
exit 0
