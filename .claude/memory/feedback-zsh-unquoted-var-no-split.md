---
name: feedback-zsh-unquoted-var-no-split
description: the Bash tool runs zsh, so `for x in $LIST` and `bash $cmd` with a space-separated variable do NOT word-split
metadata:
  type: feedback
---

In this repo's shell, `for b in $DEL` treats the whole string as one word and `bash $c` with `c="scripts/x.sh ."` runs a path containing a space (exit 127). Both failed silently-looking today (a branch-delete loop deleted nothing; a check loop reported "No such file").

**Why:** zsh does not split unquoted parameter expansions like bash does.

**How to apply:** put such loops inside `bash -c '...'`, or use real arrays / a literal word list in the `for`. If a result says exit=127 or "could not delete <the whole list>", suspect splitting before suspecting the command. See also [[feedback-grep-is-ugrep-wrapper]] for the other shell surprise here.
