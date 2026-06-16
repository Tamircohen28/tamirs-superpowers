# PR Body Templates

Reference for `start-dev` Step 5. Choose the template that matches the task type.
Substitute `[…]` placeholders — never leave them literally in the PR body.

---

## Feature (linked to GitHub issue)

```markdown
## Summary
[2-3 sentences: what changed and why — focus on user impact, not implementation detail]

## Changes
- [Bullet: what was added/changed]
- [Bullet: config/env changes if any]

## Test plan
- [ ] [Specific manual step to verify the happy path]
- [ ] [Edge case or error scenario to verify]
- [ ] All existing tests pass

Closes #[N]

🤖 Generated with [Claude Code](https://claude.ai/code)
```

---

## Bug fix (linked to GitHub issue)

```markdown
## Root cause
[One sentence: what was wrong and why it happened]

## Fix
[One sentence: what was changed to fix it]

## Test plan
- [ ] Reproduce the original bug — confirm it no longer occurs
- [ ] [Regression test added / existing test updated]
- [ ] All existing tests pass

Closes #[N]

🤖 Generated with [Claude Code](https://claude.ai/code)
```

---

## Task from spec / free-text (no GitHub issue)

```markdown
## Summary
[2-3 sentences: what was built and the motivation, derived from the spec/task description]

## Changes
- [Bullet: what was added/changed]
- [Bullet: any new dependencies or config]

## Test plan
- [ ] [Primary acceptance criterion from spec]
- [ ] [Secondary criterion]
- [ ] All existing tests pass

🤖 Generated with [Claude Code](https://claude.ai/code)
```

---

## Multi-issue PR (several issues grouped)

```markdown
## Summary
[2-3 sentences covering the combined scope]

## Changes by issue
### #[N1] — [issue title]
- [Bullet]

### #[N2] — [issue title]
- [Bullet]

## Test plan
- [ ] [Criterion for issue N1]
- [ ] [Criterion for issue N2]
- [ ] All existing tests pass

Closes #[N1]
Closes #[N2]

🤖 Generated with [Claude Code](https://claude.ai/code)
```

---

## Chore / maintenance (no issue)

```markdown
## Summary
[1-2 sentences: what maintenance task was done and why it was needed]

## Changes
- [Bullet]

## Test plan
- [ ] [Relevant check — e.g. CI passes, linter clean, build succeeds]

🤖 Generated with [Claude Code](https://claude.ai/code)
```

---

## Choosing the PR title

Format: `<type>(<optional-scope>): <imperative verb> <object>`

| Type | When |
|---|---|
| `feat` | New capability visible to users or callers |
| `fix` | Corrects incorrect behaviour |
| `chore` | Maintenance, upgrades, CI, non-user-visible cleanup |
| `docs` | Documentation only |
| `refactor` | Code reorganization with no behaviour change |
| `test` | Tests only |
| `perf` | Performance improvement |

Good: `feat(auth): add JWT refresh token rotation`
Bad: `Fix stuff`, `WIP`, `changes`, `Update login.ts`
