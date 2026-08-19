# Which invocation, and what stops it

## From what the user said, to the command

| The user says | Verb + scope |
|---|---|
| "is this repo protected", "check my branch protection" | `audit` (no scope — this checkout's origin) |
| "audit OWNER/NAME" | `audit --repo OWNER/NAME` |
| "what would it take to fix this repo" | `plan --repo OWNER/NAME` |
| "fix it", "set up branch protection here" | `plan --repo` → show → `apply --repo` |
| "did that work", "check it took" | `verify --repo OWNER/NAME` |
| "check all my repos", "which of my repos are unprotected" | `plan --all` |
| "bring them all into line" | `plan --all`, then `apply --repo` per repository the user picks |
| "do the same for my org" | `plan --org ORGNAME` — read the `Targeting:` line before anything else |
| "apply it to the whole org" | `apply --org ORGNAME --org-level` if targeting says org; otherwise per repository |
| "why does every PR want me to rebase" | `audit --repo` and read the `Legacy` block for the `!!` line |
| "should I require an approval" | do not run anything — derive it (SKILL.md, Mode 6) |
| "give me machine-readable output" | add `--json` (report goes to stderr, document to stdout) |

`audit` and `verify` take only `--repo`. `plan` and `apply` take exactly one of
`--repo` / `--all` / `--org`.

## Three things stop a write, and each means something different

**1. CONFLICT — never weaken.** The canonical policy is a floor, not a ceiling.
If applying it would remove a required check, drop a rule already in force, turn
off strict "branch must be up to date", lower approvals, or stop targeting the
default branch, the write is refused and the repository is reported `CONFLICT`.

The right response is almost never `--allow-weakening`. The common case is a
repository with a required check that the policy has no `required_checks.contexts`
entry for — the fix is to add the contexts to the policy file. Only after the
user has looked at the specific conflict and said the policy is right does
`--allow-weakening` come out, and even then each change is still shown and
confirmed one repository at a time.

**2. CONFLICT — never bypass an organization.** An org ruleset stricter than
canonical means the repository is left alone. There is no flag. Report it; do
not look for a way around it.

**3. The LIVE-TARGET GATE.** Without a terminal, `--yes` alone does not
authorise a write — the tool prints the plan and exits 0. That exit 0 means "it
did exactly what it promised", not "it applied". `GITHUB_POLICY_ALLOW_LIVE=1` is
the declaration an unattended caller must make, and **you never set it**: the
gate exists because a non-interactive `--yes` run once reverted a deliberate
setting on the author's own repository.

## Exit codes

| Code | Meaning | How to report it |
|---|---|---|
| `0` | compliant, or a plan was printed, or apply finished, or there was no terminal so the plan was printed instead | check which verb ran before saying "protected" |
| `3` | drift: something is absent, drifted, or blocked | a **finding**, not a crash |
| `1` | failure: bad flag, missing `gh`/`jq`, unreadable policy, API failure | a genuine error; say what the tool said |

## Fallbacks

**`gh` missing or unauthenticated** — a hard stop. This feature has no local
substitute; the GitHub action *is* the request. Say `brew install gh` /
`gh auth login` and stop. Do not attempt the audit from local files, do not
guess from `.github/`, and do not use the GitHub MCP server instead — the
transport is `gh api` by design so that classification is uniform.

**No admin permission on a repository** — reads still work, so the audit is
still worth running and its answer is still true. That repository lands in
`FAILED` on a write with the permission named. Report which repositories could
be read but not written, rather than abandoning the sweep.

**Organization rulesets unavailable** — never a failure. Report the tool's own
reason (plan, scope, org policy, permission, or a repository filter) and carry
on with the per-repository sweep, which is what the tool already did.
