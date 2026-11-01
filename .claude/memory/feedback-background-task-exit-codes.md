---
name: feedback-background-task-exit-codes
description: "make validate here runs >2min so it must be backgrounded — and its result is the log's own EXIT= line, never the background task notification's exit code"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ecd4a1e-ed87-4ea9-a55d-5727b73b1a29
  modified: 2026-09-01T22:00:40.793Z
---

`make validate` in this repo takes **4-5 minutes** (the hook suites alone run 500+ assertions).
That exceeds the default 2-minute Bash timeout, so a foreground run is killed mid-flight and the
cycle is wasted — this happened on the first attempt of the 2026-09-01 session.

Run it backgrounded, recording its own exit status into the log:

```bash
cd <worktree> && make validate > "$SCRATCH/validate.log" 2>&1; echo "EXIT=$?" >> "$SCRATCH/validate.log"
```

**The trap that follows.** A background task's completion notification reports the exit code of
**the tool invocation**, not of the command whose output was redirected to a file. Waiting on it
with a second background poller makes this worse: that poller's notification says
`completed (exit code 0)` because *the poll loop* succeeded.

On 2026-09-01 I read exactly that and announced "Gate green", then committed and pushed — while
the log's last line read `EXIT=2` and `tests/test-github-policy.sh` had 17 failing assertions.
No PR was open so nothing merged red, but the claim was false when made.

**How to apply:** the result of a backgrounded gate is whatever the log says, never what the
notification says. Read it explicitly, every time:

```bash
grep '^EXIT=' "$SCRATCH/validate.log"
grep -nE 'FAILED|failed: [1-9]|make: \*\*\*' "$SCRATCH/validate.log" | head
```

`EXIT=0` **and** no failure lines before claiming a gate passed. Beware that a plain
`grep -c fail` can hit `ok` lines whose text contains the word — match on the count patterns
above, not on bare "fail".

**Recurrence, 2026-09-23.** This fired three more times in a single session, same shape every
time: notifications reading `completed (exit code 0)` while the log said `EXIT=2`. Once the
failure was a forked contract template (`sync-contract-scripts.sh` regenerates 36 copies; any
edit to `core/capabilities/platforms.json` is really a 4-file edit), once a stale root
`.codex-version` pin, once a shellcheck SC2155. All three would have been committed as "gate
green" on the notification alone. The rule is not aging out — read the `EXIT=` line every time.

Related: [[feedback-verify-mechanism-claims]] — this is the mechanical instance of that pattern.
See also [[feedback-probe-narrow-before-full-gate]] for not paying the 2-minute cost repeatedly
while iterating on a localized fix.
