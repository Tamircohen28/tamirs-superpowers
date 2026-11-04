# Stage 4 — merge settings and branch governance

Detail for repo-scaffold Stage 4, after the initial push. `SKILL.md` carries the two commands and the
degraded-success rule; this file is the full statement.

Enable PR auto-merge (required for `start-dev` / `pr-dev`). Without `--apply` the script only prints the PATCH; with it, it asks the resolver about `repo.settings.merge` (R3, never automatic) and sends the PATCH only on allow, or on a `y` typed at a terminal of its own:

```bash
bash "$CONTRACT_ROOT/scripts/enable-repo-merge-settings.sh" "TamirCohen28/$REPO_NAME" --apply --skill repo-scaffold
```

Exit `3` means it was not applied (denied, or there was no terminal to confirm at — the usual case in an agent shell). That is a **degraded success**, like the policy step below: continue, and put the script's printed `blocked:` line and its "run this yourself" command in the Stage 6 summary. Never retry it with a different flag or call `gh api` directly to get around it.

Apply the canonical repository policy (branch rulesets on the default branch):

```bash
PLUGIN_ROOT="$(cd "$CONTRACT_ROOT/../../.." && pwd)"
bash "$PLUGIN_ROOT/scripts/github-policy.sh" apply --repo "TamirCohen28/$REPO_NAME"
```

This replaced `ensure-branch-protection.sh`, which wrote classic `branches/*/protection` with one literal `CI` context and a hardcoded default-branch name. The old script remains only as a deprecating shim onto this command.

**If it cannot run, the scaffold still succeeded.** Repository creation must never fail because branch governance could not be applied — the local tree, the docs, the CI and the contract gate are all real work that is already done and pushed. `github-policy.sh apply` exits non-zero when `gh` is missing, unauthenticated, or lacks repository-administration permission, or when the permission resolver denies `ruleset.apply` (exit 3); when the resolver asks (R4, always) and there is no TTY to confirm at, it prints the plan and writes nothing. Treat every one of those as a **degraded success**: continue to Stage 5, and report verbatim in the Stage 6 summary —

> Local repository configured. GitHub repository policy was not applied because GitHub administration access is unavailable.

— followed by the exact command the user can run themselves once access exists:

```bash
bash scripts/github-policy.sh apply --repo TamirCohen28/$REPO_NAME
```

Do not retry, do not fall back to classic branch protection, and do not silently mark the repo as protected.
