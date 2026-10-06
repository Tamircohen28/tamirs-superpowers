---
name: feedback-fix-the-class-not-the-example
description: "When a scanner/linter names one example and fixing it just reveals the next, stop — sweep the whole shape, add a guard, label readings as hypotheses"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 03613cd1-02ee-4604-ab0f-03bd4306a67a
  modified: 2026-10-06T16:00:45.745Z
---

When an external checker (directory portal scanner, linter, reviewer bot) names **one example** of a
finding, and fixing that example only makes it name a **different** one, the finding is a class, not
an instance. Stop fixing examples.

**Why:** the Claude plugin-directory credential hold (`MCP_FORWARDS_CREDENTIAL_ENV`) pairs a "reader"
in one skill with a "sender" in another; both sides are open lists and the portal names one example
of each per validation. Six releases (4.11.5 -> 4.11.11, 2026-10-03/04) each fixed the named example:
reader `pass --decision` -> `${SOME_SECRET}` -> `gh auth ...`; sender diagnose-refusal -> targeted-debug
-> switch-dev. Each round cost a full gate + release + portal validation (~1h). Only round 6 swept the
whole reader class (7 lines in 29 skills) and added a guard to `scripts/check-claude-dist.sh`. One
round (4.11.9, "pipes into bash") shipped a wrong reading that the history already contradicted.

**How to apply:**
1. After the second "same rule, different example", model the checker: what shape does it match?
2. Sweep every instance of that shape across the shipped tree in one pass (Python regex, not
   `git grep -E` — see [[feedback-grep-is-ugrep-wrapper]]).
3. Add a local guard that refuses the shape, with a test that plants it.
4. Test any reading against the history before shipping it, and write it as a hypothesis in the PR.
Related: [[project-directory-submission-holds]], [[feedback-verify-mechanism-claims]].
