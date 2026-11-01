---
name: feedback-grep-is-ugrep-wrapper
description: "In this session's shell `grep` is a ugrep wrapper honoring .gitignore; make/CI use real grep, so shell tests of shell code can disagree with production"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a35855d6-d668-42fb-af0b-d574c2b896ae
  modified: 2026-10-06T16:01:09.409Z
---

`grep` in the Bash-tool shell is **not** `/usr/bin/grep`. It is a shell function that
re-execs `claude` as `ugrep` with `--ignore-files --hidden -I --exclude-dir=.git …`.
`make` runs recipes under `/bin/sh`, which has no such function, and CI likewise uses the
real binary.

**Why:** testing a Makefile/shell snippet by pasting it into the Bash tool runs it under a
*different grep* than the one that will run in production. A multi-file `grep -q` that works
under real grep returned rc=2 under the wrapper, which made a correct patch look broken —
and could equally make a broken patch look correct. `--ignore-files` means it also silently
skips gitignored files the real grep would read.

**More shell traps in this environment (2026-10-04):**
- zsh reads `$V:skills/...` as a history modifier (`:s`) → "bad substitution" and empty output. Write
  `"${V}:path"`.
- `git grep -E` on macOS uses BSD regex: `\s` and `\b` silently match nothing. Use Python `re` for sweeps.
- `claude plugin test .` run directly in the Bash tool prints "not run from this spelling"; run it as
  `bash -c 'cd <dir> && claude plugin test .'` (the way `make` does).

**How to apply:** when verifying shell logic destined for a Makefile, a hook, or CI, run it
through `/bin/sh -c '…'` (or `command grep`), never by pasting it into the interactive shell.
The ground truth is `make <target>`. This is the same failure shape as
[[feedback-verify-mechanism-claims]] and the `stat -f` bug: a tool that *succeeds at a
different job* rather than erroring. Related: [[feedback-background-task-exit-codes]] for
reading the gate's result correctly once it runs.
