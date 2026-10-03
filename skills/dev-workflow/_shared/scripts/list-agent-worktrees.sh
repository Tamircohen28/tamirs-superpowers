#!/usr/bin/env bash
# list-agent-worktrees.sh — list platform-scoped worktrees for the current repo.
#
# Usage:
#   list-agent-worktrees.sh [repo_root]
#   list-agent-worktrees.sh -h | --help
#
# Output JSON array: [{ platform, path, branch }]
set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import json
import subprocess
import sys

repo = sys.argv[1]
try:
    out = subprocess.check_output(
        ["git", "-C", repo, "worktree", "list", "--porcelain"],
        text=True,
    )
except subprocess.CalledProcessError:
    print("[]")
    sys.exit(0)

entries = []
path = ""
branch = ""
for line in out.splitlines():
    if line.startswith("worktree "):
        path = line[len("worktree "):]
    elif line.startswith("branch "):
        branch = line[len("branch refs/heads/"):]
    elif line == "" and path:
        for platform in ("claude", "cursor", "codex"):
            needle = f"/.{platform}/.worktrees/"
            if needle in path:
                entries.append({"platform": platform, "path": path, "branch": branch})
                break
        path = ""
        branch = ""

print(json.dumps(entries))
PY
