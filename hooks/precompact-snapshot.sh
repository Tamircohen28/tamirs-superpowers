#!/usr/bin/env bash
# precompact-snapshot.sh — PreCompact hook (ADVISORY, never blocks).
#
# WHY A FILE AND NOT injected CONTEXT
#   The obvious design is to return `hookSpecificOutput.additionalContext` and
#   have the post-compaction turn read it. That channel is NOT documented for
#   `PreCompact` — the decision-control model covers the tool events and the
#   Stop family, and `PreCompact`/`PostCompact` appear only in the lifecycle and
#   matcher tables. `systemMessage` is universal but the docs say plainly that
#   "some events discard it."
#
#   So this hook does not depend on either. It writes a file. A file survives
#   compaction unconditionally, costs nothing to produce, and the model can read
#   it back on demand — which is the whole point, since what compaction destroys
#   is precisely the cheap-to-write, expensive-to-re-derive working state.
#   `systemMessage` is emitted too, best-effort: if the host shows it, the user
#   learns the file exists; if it discards it, nothing is lost.
#
# WHAT IT CAPTURES
#   Only facts that are expensive to re-derive after context loss and cheap to
#   read from disk: the branch, what is uncommitted, the open objective, recent
#   commit subjects. Not a transcript — the transcript already exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
trigger="$(printf '%s' "$input" | jq -r '.trigger // .matcher // empty' 2>/dev/null || true)"
[ -n "$trigger" ] || trigger="unknown"

# Outside a git repo there is no working state worth snapshotting.
if ! git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  echo '{"suppressOutput": true}'
  exit 0
fi

repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
dirty="$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c . || true)"

objective=""
if [ -d "${repo_root}/.dev-files/objectives" ]; then
  objective="$(
    find "${repo_root}/.dev-files/objectives" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
      | head -1 | xargs -I{} basename {} 2>/dev/null || true
  )"
fi

# Nothing in flight — a compaction mid-browse needs no snapshot.
if [ "$dirty" -eq 0 ] && [ -z "$objective" ]; then
  echo '{"suppressOutput": true}'
  exit 0
fi

out_dir="${repo_root}/.dev-files/compaction"
mkdir -p "$out_dir" 2>/dev/null || { echo '{"suppressOutput": true}'; exit 0; }
out="${out_dir}/latest.md"

{
  printf '# Pre-compaction snapshot\n\n'
  printf -- '- when: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf -- '- trigger: %s\n' "$trigger"
  printf -- '- repo: %s\n' "$repo_root"
  printf -- '- branch: %s\n' "$branch"
  [ -n "$objective" ] && printf -- '- open objective: %s\n' "$objective"
  printf '\n## Uncommitted (%s)\n\n' "$dirty"
  if [ "$dirty" -gt 0 ]; then
    git -C "$cwd" status --porcelain 2>/dev/null | sed 's/^/    /' | head -50
  else
    printf '    (clean)\n'
  fi
  printf '\n## Recent commits on this branch\n\n'
  git -C "$cwd" log -8 --pretty='    %h %s' 2>/dev/null || printf '    (none)\n'
} > "$out" 2>/dev/null || { echo '{"suppressOutput": true}'; exit 0; }

rel="${out#"${repo_root}"/}"
detail="${dirty} uncommitted file(s) on ${branch}"
[ -n "$objective" ] && detail="${detail}, objective '${objective}'"

msg="Context compaction (${trigger}) — working state saved to ${rel}: ${detail}. Read that file rather than re-deriving it if the thread is lost."

jq -n --arg msg "$msg" '{systemMessage: $msg}'
