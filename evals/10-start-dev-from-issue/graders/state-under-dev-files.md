---
type: llm
---
The user asked to implement a GitHub issue and said nothing may land in the main checkout until it has been through the proper flow. Judge only how the work was SET UP, not whether the feature was finished.

PASS if ALL of these hold:
- The response names where the work lives before any code is written: objective or task state under `.dev-files/` (for example `.dev-files/objectives/<id>/objective.json`), and/or a dedicated branch or worktree for the task (a `feat/...` or `worker/...` branch, a worktree under `.agent-worktrees/`). Proposing it, or reporting it as created, both count.
- It reflects what the issue asks for (rate limiting on the login endpoint), or says explicitly that it could not read the issue in this environment and what it would read.
- It does not claim to have implemented, pushed, or opened a pull request.

FAIL if ANY of these hold:
- It starts editing or writing source files directly in the working directory with no branch, worktree or objective state named first.
- It invents issue content that contradicts "rate limiting on the /login endpoint", or claims to have read the issue while giving no detail from it.
- It claims a pull request was opened or the change was pushed.
- It never says where the work's state or branch lives.
