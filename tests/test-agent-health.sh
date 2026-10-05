#!/usr/bin/env bash
# Tests for scripts/agent-health.sh — verdicts per worktree, text and --json, flags.
#
# Builds one temp repo with a worktree per verdict. "Old" is made portable with a
# fixed `touch -t 202001010000` (no GNU/BSD date arithmetic).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/agent-health.sh"
PASS=0
FAIL=0

[ -f "$SCRIPT" ] || { echo "FATAL: $SCRIPT not found"; exit 1; }
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

G() { git -C "$1" -c user.email=t@e -c user.name=t "${@:2}"; }

REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
echo base >"$REPO/base.txt"
G "$REPO" add -A
G "$REPO" commit -q -m init

# okwt: one commit ahead, clean, fresh writes.
G "$REPO" worktree add -q -b ok-branch "$TMPROOT/okwt"
echo a >"$TMPROOT/okwt/a.txt"; G "$TMPROOT/okwt" add -A; G "$TMPROOT/okwt" commit -q -m a

# pilewt: 30 untracked files.
G "$REPO" worktree add -q -b pile-branch "$TMPROOT/pilewt"
i=0; while [ "$i" -lt 30 ]; do echo "$i" >"$TMPROOT/pilewt/f$i.txt"; i=$((i + 1)); done

# idlewt: one commit ahead, every file written long ago.
G "$REPO" worktree add -q -b idle-branch "$TMPROOT/idlewt"
echo b >"$TMPROOT/idlewt/b.txt"; G "$TMPROOT/idlewt" add -A
GIT_COMMITTER_DATE="2020-01-01T00:00:00" GIT_AUTHOR_DATE="2020-01-01T00:00:00" \
  G "$TMPROOT/idlewt" commit -q -m b
find "$TMPROOT/idlewt" -path "$TMPROOT/idlewt/.git" -prune -o -type f -exec touch -t 202001010000 {} +

# nocwt: fresh branch, nothing ahead, nothing changed.
G "$REPO" worktree add -q -b noc-branch "$TMPROOT/nocwt"

# detachedwt: detached HEAD at main.
G "$REPO" worktree add -q --detach "$TMPROOT/detwt" main

# gonewt: worktree dir deleted behind git's back.
G "$REPO" worktree add -q -b gone-branch "$TMPROOT/gonewt"
rm -rf "$TMPROOT/gonewt"

# A fresh file under node_modules must not hide idleness.
mkdir -p "$TMPROOT/idlewt/node_modules"; echo x >"$TMPROOT/idlewt/node_modules/x.js"

verdict_text() { # branch [flags...]
  local b="$1"; shift
  bash "$SCRIPT" --repo "$REPO" "$@" | awk -v b="$b" '$2 == b { print $1; exit }'
}
verdict_json() {
  local b="$1"; shift
  bash "$SCRIPT" --repo "$REPO" --json "$@" | jq -r --arg b "$b" '.worktrees[] | select(.branch == $b) | .verdict'
}

echo "== verdicts (text)"
check "main worktree clean on default branch" ok "$(verdict_text main)"
check "fresh committed work is ok"            ok "$(verdict_text ok-branch)"
check "30 uncommitted files is a pile"        uncommitted-pile "$(verdict_text pile-branch)"
check "old files with commits is idle"        idle "$(verdict_text idle-branch)"
check "empty fresh branch is no-commits"      no-commits "$(verdict_text noc-branch)"
check "detached HEAD with no commits"         no-commits "$(verdict_text '(detached)')"

echo "== verdicts (--json)"
check "json ok"       ok "$(verdict_json ok-branch)"
check "json pile"     uncommitted-pile "$(verdict_json pile-branch)"
check "json idle"     idle "$(verdict_json idle-branch)"
check "json no-commits" no-commits "$(verdict_json noc-branch)"

echo "== json shape"
J="$(bash "$SCRIPT" --repo "$REPO" --json)"
printf '%s' "$J" | jq empty >/dev/null 2>&1 && ok "valid JSON" || bad "valid JSON"
check "json lists every worktree" 7 "$(printf '%s' "$J" | jq '.worktrees | length')"
check "json uncommitted count" 30 "$(printf '%s' "$J" | jq '[.worktrees[] | select(.branch=="pile-branch")][0].uncommitted')"
check "json ahead count" 1 "$(printf '%s' "$J" | jq '[.worktrees[] | select(.branch=="ok-branch")][0].ahead')"
check "json default branch" main "$(printf '%s' "$J" | jq -r '.default_branch')"
check "json missing worktree noted" missing "$(printf '%s' "$J" | jq -r '[.worktrees[] | select(.branch=="gone-branch")][0].note')"
check "json idle last_write is old" true "$(printf '%s' "$J" | jq '[.worktrees[] | select(.branch=="idle-branch")][0].last_write_min > 1000')"

echo "== json escaping"
ODD="$TMPROOT/odd \"q\" back\\slash"
mkdir -p "$ODD"; git -C "$ODD" init -q -b main
G "$ODD" commit -q --allow-empty -m i
bash "$SCRIPT" --repo "$ODD" --json | jq empty >/dev/null 2>&1 && ok "odd path yields valid JSON" || bad "odd path yields valid JSON"

echo "== thresholds"
check "--pile 100 clears the pile"   no-commits "$(verdict_text pile-branch --pile 100)"
check "--pile 1 flags one change"    uncommitted-pile "$(verdict_text pile-branch --pile 1)"
check "--idle-min huge clears idle"  ok "$(verdict_text idle-branch --idle-min 100000000)"
check "--idle-min 0 flags old work"  idle "$(verdict_text idle-branch --idle-min 0)"
check "--pile reflected in json" 7 "$(bash "$SCRIPT" --repo "$REPO" --json --pile 7 | jq '.pile')"

echo "== usage errors"
bash "$SCRIPT" --nope >/dev/null 2>&1; check "unknown flag exits 2" 2 "$?"
bash "$SCRIPT" --pile abc >/dev/null 2>&1; check "non-numeric --pile exits 2" 2 "$?"
bash "$SCRIPT" --idle-min >/dev/null 2>&1; check "missing --idle-min value exits 2" 2 "$?"
bash "$SCRIPT" --repo "$TMPROOT/does-not-exist" >/dev/null 2>&1; check "bad --repo exits 2" 2 "$?"
mkdir -p "$TMPROOT/plain"
bash "$SCRIPT" --repo "$TMPROOT/plain" >/dev/null 2>&1; check "non-git dir exits 2" 2 "$?"
bash "$SCRIPT" -h >/dev/null 2>&1; check "-h exits 0" 0 "$?"
bash "$SCRIPT" --repo "$REPO" >/dev/null 2>&1; check "report exits 0 despite bad verdicts" 0 "$?"

echo "== default branch is the remote-tracking ref"
UP="$TMPROOT/up.git"; git init -q --bare -b main "$UP"
R2="$TMPROOT/r2"; git clone -q "$UP" "$R2" 2>/dev/null
G "$R2" checkout -q -b main 2>/dev/null || true
echo a >"$R2/a.txt"; G "$R2" add -A; G "$R2" commit -q -m c1; G "$R2" push -q origin main
G "$R2" worktree add -q -b w-branch "$TMPROOT/w2"
# Upstream advances; local main stays stale, the worker rebases onto origin/main.
echo b >"$R2/b.txt"; G "$R2" add -A; G "$R2" commit -q -m c2; G "$R2" push -q origin main
G "$R2" reset -q --hard HEAD~1
git -C "$R2" remote set-head origin main >/dev/null 2>&1
G "$R2" fetch -q origin
G "$TMPROOT/w2" merge -q --ff-only origin/main
echo w >"$TMPROOT/w2/w.txt"; G "$TMPROOT/w2" add -A; G "$TMPROOT/w2" commit -q -m own
check "ahead counts only own commits, not upstream" 1 "$(bash "$SCRIPT" --repo "$R2" --json | jq '[.worktrees[] | select(.branch=="w-branch")][0].ahead')"

echo "== nested worktrees do not drive a checkout's age"
G "$REPO" worktree add -q -b outer-branch "$TMPROOT/outerwt"
echo x >"$TMPROOT/outerwt/f.txt"; G "$TMPROOT/outerwt" add -A; G "$TMPROOT/outerwt" commit -q -m o
find "$TMPROOT/outerwt" -type f -not -path '*/.git*' -exec touch -t 202001010000 {} +
touch -t 202001010000 "$TMPROOT/outerwt/.git"
mkdir -p "$TMPROOT/outerwt/.agent-worktrees/inner" "$TMPROOT/outerwt/vendor/sub"
echo fresh >"$TMPROOT/outerwt/.agent-worktrees/inner/new.txt"
echo gitdir: x >"$TMPROOT/outerwt/vendor/sub/.git"; echo fresh >"$TMPROOT/outerwt/vendor/sub/new.txt"
check "fresh writes in nested worktrees leave the outer idle" idle "$(verdict_text outer-branch)"

echo
echo "agent-health: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
