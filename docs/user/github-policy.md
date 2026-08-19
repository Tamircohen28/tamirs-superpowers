# GitHub repository policy

One canonical definition of how every repository you own is governed, and one
command that reports and enforces it.

```bash
make github-policy-plan                             # what would change here; writes nothing
bash scripts/github-policy.sh audit                 # is this repository compliant?
bash scripts/github-policy.sh plan --all            # dry run across every repo you own
bash scripts/github-policy.sh apply --repo O/R      # diff, confirm, then write
```

It answers one question: **"are my repositories actually protected the way I
think they are, and if not, exactly what would it take?"**

---

## Why this is a separate command

It mutates live branch governance. A wrong rule applied across nineteen
repositories can lock you out of your own default branches, and undoing it means
clicking through nineteen settings pages. So the whole tool is built around
being boring:

- the default verb is `audit`, which only reads;
- `apply` shows the exact current-vs-desired ruleset JSON before every write;
- bulk scope needs the `apply` verb **and** a confirmation;
- with no terminal to confirm on, it prints the plan and exits 0 — it never
  adopts silently and never blocks;
- it refuses to make any repository *less* protected than it already is.

---

## The canonical policy

The single source of truth is [`config/github/repository-policy.json`](../../config/github/repository-policy.json),
validated against [`core/schemas/repository-policy.json`](../../core/schemas/repository-policy.json).
No skill, script, or doc — including this page — restates a rule from it. Read
the file for the rules themselves; what follows is how it behaves.

It defines two branch rulesets, both scoped to GitHub's `~DEFAULT_BRANCH` magic
ref rather than a branch name:

| Ruleset | What it is for |
|---|---|
| `Default Branch - Safety` | the floor — no deletion, no force pushes. Depends on nothing, so it is safe on a repository's first day. |
| `Default Branch - PR & CI` | how change arrives — pull request, linear history, green required checks. Apply it only once a CI workflow exists on the default branch. |

**No literal branch name appears anywhere in the policy.** Fifteen of the
repositories governed here default to `main` and four to `master`; any literal
would be wrong for one of those sets, and would quietly stop matching the day a
default branch is renamed. `scripts/check-github-policy.sh` fails the build if
one ever appears.

Required status-check contexts are **per repository, never global**. A context
is a CI job name; a name that does not exist in a repository's workflows blocks
every pull request in that repository forever. The global default is the empty
list, and each repository opts its own job names in.

---

## Why "branch must be up to date" is off

`strict_required_status_checks_policy` — the GitHub setting labelled *"Require
branches to be up to date before merging"* — is **deliberately disabled**, and
the policy file says so in as many words. This is a decision, not an oversight.

The development model here is: one objective → a task DAG → parallel workers →
integration → **one pull request**. Strict mode says a branch may only merge if
it already contains the tip of the default branch. So every merge invalidates
the green status of every other open pull request and forces all of them to
rebuild:

- N merges cost O(N²) CI runs;
- workers block on each other for reasons unrelated to their work;
- the integration branch can never stay green long enough to land, because
  landing anything else invalidates it.

Correctness is protected by two other things instead: `required_linear_history`,
which stops a merge commit from smuggling in a combination nothing ever tested,
and a full CI run on the integration branch immediately before it merges.

**One objective, one PR is what makes this safe.** Because a change reaches the
default branch as a single reviewed, fully-tested pull request rather than as a
stream of partial merges, the window in which "my branch is slightly behind"
could matter is a single merge wide. If you move to many small concurrent PRs
against a busy default branch, that trade changes — and the right response is to
change the architecture first, not to flip this switch.

If a repository already enforces strict mode, this tool will **not** turn it
off. It reports a `CONFLICT` and leaves the repository alone — see
[When the policy is *weaker* than a repository](#when-the-policy-is-weaker-than-a-repository).

---

## Actions concurrency

The second half of the policy is about GitHub Actions: when a newer commit
supersedes a run, should the older run be cancelled?

- **Yes for verification.** A test, lint, typecheck, or scan run is pure and
  repeatable. Killing it mid-flight leaves nothing behind, and the newer
  commit's run supersedes it anyway. Not cancelling just burns minutes.
- **Never for anything that writes outside the repository.** A cancelled deploy,
  release, publish, or migration leaves external state half-written: a partly
  published package version, a tag with no release, a migration applied to some
  tables and not others. There is no "just re-run it" for those.

Workflows are classified by matching name and file content against patterns that
live **in the policy file**, not in the script. `never_cancel` wins any tie: a
test job wrongly serialized costs minutes, a deploy wrongly cancelled costs a
half-written external state. A workflow matching neither class is reported for a
human decision and left untouched.

So a report has two healthy shapes, and only one of them is a checkmark:

```
Actions:
✓ ci.yml — superseded PR runs cancelled
⚠ release.yml — cancellation intentionally not enabled
```

That `⚠` is **not a finding**. It is the tool confirming that a stateful
workflow correctly has no cancellation, and it never affects the result line.
The tool will never propose adding cancellation to a deployment, release,
publish, or migration workflow.

`github-policy.sh` reports workflow gaps; it never edits workflow files. Fixing
one is a hand edit and a pull request like any other code change.

> Concurrency is analysed for single-repository scope only (`audit`, `verify`,
> and `plan`/`apply --repo`). A bulk sweep is about branch governance, and
> reading every workflow of every repository would be one API call per file.

---

## Required GitHub permissions

`gh` must be installed and authenticated, and this is the one feature where a
missing `gh` is a hard failure rather than a skipped step — the GitHub action
*is* the request, so there is no local substitute to fall back to.

| What you are doing | What the token needs |
|---|---|
| `audit`, `plan`, `verify` | `repo` — read access to the repository's administration |
| `apply` | admin on the repository. Without it, GitHub returns 403 and the repository lands in `FAILED` with "insufficient Administration permission" |
| `--org` | `admin:org` in addition, to read organization-level rulesets |

```bash
gh auth status                                       # what you have now
gh auth refresh -h github.com -s repo -s admin:org   # add what is missing
```

Never paste a token by hand; derive it with `gh auth token` if a tool needs one.

---

## Auditing one repository

```bash
bash scripts/github-policy.sh audit                                  # this checkout's origin
bash scripts/github-policy.sh audit --repo Tamircohen28/job-tracker-web
```

```
GitHub Repository Standards — Tamircohen28/tamirs-superpowers

Default branch: master

Rulesets:
✓ Default Branch - Safety
✗ Default Branch - PR & CI — drifts from policy

Legacy:
✓ no classic branch protection (rulesets are authoritative)

Actions:
✓ ci.yml — superseded PR runs cancelled
⚠ release.yml — cancellation intentionally not enabled

Result: NON-COMPLIANT
```

The default branch is always read from the API, never assumed.

**Rulesets are authoritative; classic branch protection is legacy.** The two are
different GitHub features living at different endpoints, and a repository fully
protected by rulesets returns 404 for classic protection. Reading only the
classic endpoint — which the scripts this replaced did — scores a correctly
protected repository as unprotected. When classic protection *is* present it is
reported as a migration item; this tool reads it and never writes it.

---

## Remediating one repository

```bash
bash scripts/github-policy.sh plan  --repo Tamircohen28/job-tracker-web   # look
bash scripts/github-policy.sh apply --repo Tamircohen28/job-tracker-web   # then decide
```

`apply` prints the unified diff of live versus desired ruleset JSON and asks
`[y/N/a/q]` before each write. The default is **No**. The bytes it sends are the
same bytes it showed you — nothing is re-rendered between the confirmation and
the write, so approving a diff can never write something you did not see.

Prompts are read from `/dev/tty`, never from stdin, so running this inside a
hook or a pipeline cannot accidentally answer its own questions.

---

## Dry-running every repository you own

```bash
bash scripts/github-policy.sh plan --all
```

`plan` never writes, whatever the scope. The report ends in five buckets:

| Bucket | Meaning |
|---|---|
| `UPDATED` | rulesets were written |
| `ALREADY COMPLIANT` | live state already matches; nothing was sent |
| `SKIPPED` | not eligible, with the reason — archived, fork — or you declined at the prompt |
| `CONFLICT` | an organization ruleset is stricter, or applying would weaken a control already in force. Nothing was written. |
| `FAILED` | the API said no, with the reason — most often insufficient Administration permission |

One repository's failure never ends the sweep.

---

## Syncing selected repositories

```bash
bash scripts/github-policy.sh plan  --all --include 'production-master'
bash scripts/github-policy.sh apply --all --include '^Tamircohen28/(DJ|MHFC)$'
bash scripts/github-policy.sh plan  --all --exclude 'sandbox|scratch'
```

`--include` and `--exclude` take POSIX extended regular expressions matched
against `owner/name`, and both are repeatable. **`--exclude` wins**: a pattern
that says "never touch this one" must not be defeated by a broader `--include`.

Bulk `apply` needs two things before it moves: the `apply` verb, which is never
the default, and a confirmation. `--yes` is the only way to skip the per-
repository prompts and it has to be typed:

```bash
bash scripts/github-policy.sh apply --all --yes
```

With no terminal and no `--yes`, a bulk apply prints the plan and exits 0.

---

## When the policy is *weaker* than a repository

The canonical policy is a **floor, never a ceiling**. Before every write, the
live ruleset is compared against the desired one along the dimensions that
actually reduce protection, and if applying the policy would make the repository
less protected than it is today, the write is refused and the repository is
reported as `CONFLICT`:

- a required status check would be removed
- a protection rule already in force would be dropped
- strict "branch must be up to date" would be turned off
- required approving reviews would be lowered
- review-thread resolution, CODEOWNERS review, last-push approval, or
  stale-review dismissal would stop being required
- enforcement would drop from `active`
- the ruleset would stop targeting the default branch

This is the guard that makes `apply --all --yes` safe to type. It is also the
guard most likely to stop you: a repository whose rulesets were set up by hand,
or by an earlier version of this policy, will differ in exactly these ways.

Removing a bypass actor is a *strengthening*, not a weakening, so it is never
blocked — an admin bypass added on github.com quietly makes every rule below it
advisory, and reverting that is the point.

When you have looked at a conflict and decided the policy is right:

```bash
bash scripts/github-policy.sh apply --repo O/R --allow-weakening
```

`--allow-weakening` is never implied by `--yes`. It buys permission to *ask*,
not permission to skip asking: each such change is still printed with the
reasons spelled out, still marked destructive, and still confirmed one
repository at a time.

> A common case: a repository has a required check named for a CI job it really
> has, but no `repositories.<owner/repo>.required_checks.contexts` entry in the
> policy. The policy therefore resolves to *no* contexts and applying it would
> strip the gate. The right fix is almost always to add the contexts to the
> policy file, not to pass `--allow-weakening`.

---

## Organizations

```bash
bash scripts/github-policy.sh plan --org ProductionMasterAI
```

Organizations differ in one way that matters: rulesets can be defined **above**
the repository, and a repository inherits them. Those are not yours to edit from
here.

When an inherited ruleset imposes something stricter than the policy — more
required approvals, signed commits, strict status checks, a CODEOWNERS review —
the repository is reported as `CONFLICT`, named, and **left alone**. There is no
flag that overrides this, and the tool will not route around an organization
rule. It is reported whether or not the repository's own rulesets drift, so a
repository that is compliant underneath a stricter org rule still tells you the
org rule is there.

`--org` needs `admin:org` to read those parent rulesets.

---

## Repository-specific overrides

Anything a single repository needs differently lives under
`repositories.<owner/repo>` in the policy file — never in the script and never
in a skill's prose. Three things can be set per repository:

| Key | Effect |
|---|---|
| `required_checks.contexts` | the CI job names that gate a merge **here** |
| `rules.disable` | rule types to leave out for this repository |
| `rules.enforcement` | `active` / `evaluate` / `disabled` for this repository |

A repository not listed inherits the defaults with an **empty** context list:
protected, but not gated on checks it does not have.

Adding a CI job does not make it blocking. Its `name:` has to be added to that
repository's `contexts` list and applied — which is deliberate, because a
context naming a job that does not exist blocks every pull request forever.

After editing the policy: bump its `version`, run `make check-github-policy`
(offline), then `github-policy.sh plan` to see what it means live.

---

## Verifying and rolling back

```bash
bash scripts/github-policy.sh verify --repo Tamircohen28/job-tracker-web
```

`verify` re-reads live state and re-compares. Exit `0` means everything matches;
exit `3` means something is absent, drifted, or blocked.

**Running `apply` twice is a no-op.** The second run renders the desired state,
normalizes both sides, compares, finds them equal, and sends nothing — the
report says `ALREADY COMPLIANT` and no write ever leaves the machine.

### If something goes wrong

This tool only ever creates or updates the two rulesets it owns, by name. It
never deletes a ruleset, never touches one it did not render, never changes a
default branch, and never enables force pushes or default-branch deletion. So
the blast radius of a bad run is those two rulesets on the repositories you
confirmed.

To recover:

1. `bash scripts/github-policy.sh audit --repo O/R` — see the live state first.
2. Fix the policy file, not the repository: edit
   `config/github/repository-policy.json`, bump its `version`, then re-run
   `plan` and `apply`. Re-applying a corrected policy overwrites the ruleset
   with the corrected content.
3. If a re-apply is refused as a weakening, that is the guard doing its job —
   read the reasons, and either correct the policy file or re-run with
   `--allow-weakening` once you agree with it.
4. To remove a ruleset entirely, delete it in the GitHub UI
   (*Settings → Rules → Rulesets*). Deleting is deliberately not something this
   tool can do — an accidental delete of a governance rule is exactly the
   unrecoverable action it exists to prevent.
5. If a ruleset has locked you out and you are an admin, GitHub's ruleset page
   also lets you set `enforcement` to `evaluate`, which reports without blocking.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | compliant, or a plan was printed, or an apply finished, or there was no terminal so the plan was printed instead |
| `3` | drift: something is absent, drifted, or blocked by a conflict |
| `1` | failure: bad flag, missing `gh`/`jq`, unreadable policy, API failure |

---

## Machine-readable output

```bash
bash scripts/github-policy.sh plan --all --json
```

`--json` owns stdout alone; human output goes to stderr. Each change record
carries `blocked` and `reason`, so a caller can tell "this has not been done
yet" from "this cannot be done, and here is why".

---

## See also

- [`config/github/repository-policy.json`](../../config/github/repository-policy.json) — the policy itself
- [Configuration](configuration.md) — how machine config is rendered
- [Agent-kit repos](agent-kit.md) — scaffolding and maintaining distribution repos
