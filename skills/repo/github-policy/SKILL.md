---
name: github-policy
description: 'Use when a repository''s branch protection, rulesets, required checks, or PR-run cancellation may not match the canonical policy — a new repo that was never set up, a repo somebody configured by hand, an org whose repos were never brought into line, or a merge that was blocked or allowed in a way nobody expected. Also for: is this repo actually protected, why did that PR merge without CI, why is every PR asking me to update the branch, bring these repos into compliance, set up branch protection, audit my rulesets, apply the policy to all my repos, organization ruleset, convert classic branch protection to a ruleset, required approvals, cancel superseded PR runs.'
when_to_use: 'User asks whether their GitHub repositories are protected the way they think, or wants them brought into line: "is this repo protected", "set up branch protection", "audit my rulesets", "apply the policy to all my repos", "do the same for my org", "why did that merge without CI", "why does every PR want me to rebase", "convert classic branch protection to rulesets", "should I require an approval on this repo".'
argument-hint: '[audit|remediate|fleet|org] [owner/repo or org name — default: this checkout''s origin]'
arguments:
- mode
- target
user-invocable: true
disable-model-invocation: false
allowed-tools:
- Bash
- Read
- Grep
- Glob
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  updated-date: '2026-08-19'
  tamirs:
    visibility: public
    category: repo
    capabilities:
      required: [shell, github_cli]
      optional: [git]
    role: reviewer
    updated-date: "2026-08-19"
    validation-tier: 2
---

## Live context
!`git rev-parse --show-toplevel >/dev/null 2>&1 && git remote get-url origin 2>/dev/null || echo "no github origin in cwd"`
!`gh auth status 2>&1 | head -2 || echo "gh: not available"`

# github-policy

Hold GitHub repositories to one canonical policy — rulesets, branch settings,
required checks, and Actions concurrency — and report honestly when they are not.

**You are the interface and the judgement. `scripts/github-policy.sh` is the
implementation.** Do not re-derive rules, re-implement API calls, or restate a
required-check list here: the policy lives in
`config/github/repository-policy.json` and nothing else may repeat it. Your job
is to pick the right invocation, read the output, and tell the user what it
means and what it will cost.

**User guide:** [docs/user/github-policy.md](../../../docs/user/github-policy.md)

---

## The one rule that outranks everything below

**Reading is free. Writing is not.** `audit`, `plan` and `verify` never write and
never need permission. `apply` mutates live branch governance across
repositories the user cannot easily un-break, so:

- Never run `apply` before showing the user a `plan` and getting an answer.
- Never pass `--yes` unless the user said so in this conversation.
- Never pass `--allow-weakening` unless the user has seen the specific conflict
  and said the policy is right.
- Never set `GITHUB_POLICY_ALLOW_LIVE=1`. It exists so an unattended caller has
  to declare itself; an agent setting it is an agent defeating the gate that was
  added after a live setting was reverted by accident.
- If the tool declines and prints a plan instead, that is the tool working.
  Report it; do not route around it.

---

## Preflight

```bash
gh auth status        # `gh` missing or unauthenticated is a hard stop here
```

`gh` is not optional for this skill — the GitHub action *is* the request, so
there is no local substitute. If it is missing, say so and stop:
`brew install gh && gh auth login`. If a scope is missing, the tool names it.

---

## Mode 1 — audit one repository

The default. Answers "is this repository compliant, and if not, what exactly?"

```bash
bash scripts/github-policy.sh audit                      # this checkout's origin
bash scripts/github-policy.sh audit --repo OWNER/NAME
```

Read four blocks out of the report and summarise them for the user:

| Block | What a bad line means |
|---|---|
| `Rulesets` | a ruleset is absent or drifts from canonical |
| `Bypass actors` | somebody can merge around every rule below — preserved deliberately, never asserted; surface it, don't "fix" it |
| `Legacy` | classic branch protection is also in force (see Mode 5) |
| `Actions` | a superseded PR run is not cancelled, or a stateful workflow has cancellation ON |

Exit `0` compliant · `3` drift or conflict · `1` failure. Exit 3 is a finding,
not an error — do not report it as a crash.

## Mode 2 — remediate one repository

```bash
bash scripts/github-policy.sh plan  --repo OWNER/NAME     # show the diff, write nothing
# show the user the diff, get an answer, and only then:
bash scripts/github-policy.sh apply --repo OWNER/NAME
bash scripts/github-policy.sh verify --repo OWNER/NAME
```

`apply` shows each change and confirms it at the terminal. Running it twice is a
no-op proven by content, not asserted — say so if the user worries about
re-running it.

Workflow findings are **not** applied by the tool: `.github/workflows/*.yml` is
edited by hand. When the Actions block reports a missing concurrency group, add
the block from `config/github/repository-policy.json` → `actions.concurrency`
(or `actions.serialize_concurrency` for a deploy) yourself, in a PR.

## Mode 3 — dry-run every personal repository, then sync selected ones

```bash
bash scripts/github-policy.sh plan --all                             # every repo you own
bash scripts/github-policy.sh plan --all --exclude 'sandbox|archive' # narrow it
```

Read the buckets — `WOULD UPDATE`, `ALREADY COMPLIANT`, `CONFLICT`, `SKIPPED`
(forks and archived), `FAILED` — and give the user a short list of what would
change and where the conflicts are. Then apply the ones they pick, **by name**:

```bash
bash scripts/github-policy.sh apply --repo OWNER/NAME
```

Prefer repeating `apply --repo` over `apply --all` unless the user explicitly
asks for the whole fleet. A per-repo run is reviewable; a fleet run is a
nineteen-repository decision made once.

## Mode 4 — organization mode

**This is where the answer is different, and the difference is the point.** An
organization ruleset carries `conditions.repository_name` targeting, so ONE
ruleset governs every repository in the org — including repositories created
tomorrow. Copying the same ruleset onto each repository is not a smaller version
of that; it is N copies that drift the moment anyone edits one.

```bash
bash scripts/github-policy.sh plan --org ORGNAME
```

The report opens with an `Organization-level rulesets` block. Read the
`Targeting:` line:

- **`organization-level is available and preferred`** → recommend the single
  write, and say what it buys: one place to change the policy, and every future
  repository governed on creation.
  ```bash
  bash scripts/github-policy.sh apply --org ORGNAME --org-level
  ```
  `--org-level` is required on purpose — an org ruleset also governs
  repositories that do not exist yet, and that blast radius has to be typed.
- **`per-repository`** → the block states the reason. Repeat it to the user
  verbatim rather than paraphrasing; the reasons are not interchangeable:
  - *the organization's plan* — org rulesets need GitHub Team or Enterprise.
    Nothing the user can do in the CLI fixes this. Say so plainly and fall back.
  - *a missing scope* — fixable: `gh auth refresh -h github.com -s admin:org`.
  - *not an organization owner* — needs somebody else.
  - *a repository filter is in effect* — `--include`/`--exclude` are EREs and
    GitHub's targeting takes globs; drop the filter to use org-level, or keep it
    and accept the sweep.

**Two things never route around an organization:** an existing org ruleset that
is stricter than canonical is reported as `CONFLICT` and left alone, at any
verbosity and with any flag; and required status-check contexts stay
per-repository, because a context is a CI job name and a name no workflow
produces blocks every PR in that repository forever. Tell the user the org
ruleset covers everything *except* contexts, and that the per-repository sweep
still supplies those.

## Mode 5 — classic branch protection sitting under a ruleset

Classic branch protection and rulesets **apply at the same time**, and GitHub
takes the stricter of the two. A repository can therefore pass a ruleset audit
perfectly while a classic rule nobody has opened in a year is what actually
gates merges. GitHub's "Convert to ruleset" button copies classic protection
into a ruleset and **leaves classic enabled** — which is how repositories end up
in this state.

The `Legacy` block reports it. One line is marked `!!` and outranks everything
else in the report: **a classic rule still forcing "branch must be up to date"**
(`required_status_checks.strict: true`). Canonical turns that off deliberately —
with parallel workers and one integration PR it costs O(N²) CI runs — and the
leftover classic rule reinstates it invisibly, because the ruleset everybody
reads still says `false`. If the user has ever asked "why does every PR want me
to rebase", this is the answer.

The report prints the migration path. **Never run its last step for the user.**
Removing branch protection because a ruleset appears to have taken over is
un-protecting a branch on a belief; the tool reads classic protection and never
writes it, and neither do you without the user saying the words.

## Mode 6 — should this repository require an approval?

Do not answer from taste, and do not copy another repository's number. It is
derived:

```
count = 1 if (bypass_actor_present AND collaborators > 1) else 0
```

On a solo repository the owner authors every PR, so a review requirement is not
strict — it is **unsatisfiable**, and the only way anything lands is `--admin`,
which bypasses required status checks, linear history and thread resolution *at
the same time*. Requiring an approval there converts a green-CI gate into a
bypass habit: a net loss of safety wearing the costume of an increase. The count
is only meaningful *because* a bypass actor exists — with one, the pair reads
"anyone else's change needs a review, the owner keeps an escape hatch". The real
gate on a solo repository is `required_review_thread_resolution`, which a bot
review can satisfy and one human can genuinely clear.

---

## Reporting back

Lead with the answer, then the cost:

> `Tamircohen28/job-tracker-web` — **NON-COMPLIANT**. Both rulesets are absent
> and CI is not cancelling superseded PR runs. Remediating is two ruleset
> creates plus one workflow edit; nothing has been written.

Never say a repository is protected because the command exited 0 without reading
which verb ran — `plan` exits 0 having written nothing. Never summarise a
`CONFLICT` as "failed"; it is a decision waiting for the user.

## References

- [references/api-surface.md](references/api-surface.md) — the endpoints, the
  status codes each degrade path produces, and what the tool does with them
- [references/decision-tree.md](references/decision-tree.md) — which verb and
  scope for which request, and the three things that stop a write

## Evals

- [evals/evals.json](evals/evals.json) — behaviour cases, including the
  no-`gh` and no-permission fallbacks
- [evals/trigger-evals.json](evals/trigger-evals.json) — trigger accuracy
