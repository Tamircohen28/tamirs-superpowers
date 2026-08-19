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
- it refuses to make any repository *less* protected than it already is;
- it never removes a required CI check silently;
- it never removes a **bypass actor** — see
  [Bypass actors are preserved, not asserted](#bypass-actors-are-preserved-not-asserted).

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
| `--org-level` | organization **owner**, plus a plan that supports organization rulesets (Team or Enterprise) |

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

## Bypass actors are preserved, not asserted

A ruleset's `bypass_actors` list — who may merge around the rules — is
**repository-specific state that this tool carries through unchanged**. It is
treated exactly like required status-check contexts: read from the live ruleset,
written back as-is, and **never counted as drift**.

- an existing bypass actor is never removed;
- a bypass actor is never added — a ruleset being created gets none;
- a difference in `bypass_actors` never makes a repository non-compliant.

The reason is that removing one *looks* like a strengthening and behaves like a
lockout. On a solo-contributor account the repository-admin bypass **is** the
merge path — `--admin` is how changes land. Asserting the canonical empty list
would revoke the author's ability to merge into their own default branch, and
the diff would read as tightening a control while actually removing the
operator's only key. That is the "a policy tool can lock the author out" risk
arriving from the one direction nobody watches.

Existing bypass actors are reported so they stay visible:

```
Bypass actors (preserved, not asserted by policy):
⚠ Default Branch - PR & CI — 1 preserved: RepositoryRole 5 (always)
```

**The accepted trade-off, stated plainly:** a repository carrying an
*over-broad* bypass — say one granted to Everyone — will never be corrected by
this tool. That is a deliberate choice: the risk of silently locking the author
out of their own repositories was judged worse than the risk of leaving a
too-generous exemption in place. The line above is how you find one; removing it
is a decision you make in the GitHub UI, not something this tool will do for
you.

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

`bypass_actors` is not on this list, because it is never changed at all — see
[above](#bypass-actors-are-preserved-not-asserted).

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
bash scripts/github-policy.sh plan  --org ProductionMasterAI
bash scripts/github-policy.sh apply --org ProductionMasterAI --org-level
```

An organization is not a personal account with more repositories in it. It is
the one place where the policy can stop being copied.

`orgs/{org}/rulesets` carries `conditions.repository_name` targeting, so **one**
ruleset governs every repository in the organization — including every
repository created after it. Copying the same ruleset onto each repository in
turn is not a smaller version of that: it produces N copies that drift the
moment anybody edits one, and it leaves tomorrow's repository ungoverned until
somebody remembers to run a sweep. Change the policy once at the organization
level, rather than visiting thirty repositories.

So `--org` **always reports the organization-level answer first**, on every
verb. The report opens with a block like this:

```
Organization-level rulesets — ProductionMasterAI
  ✓ organization rulesets are readable — 0 live

  Targeting: organization-level is available and preferred
  one organization ruleset targeting repository_name ~ALL governs all 8
  repositories, and every repository created after it — change the policy once
  here instead of visiting 8 repositories.
```

### Writing it needs `--org-level`

`apply --org X` on its own does what it has always done: the per-repository
sweep. Adding `--org-level` writes the organization ruleset instead.

That extra word is not ceremony. An organization ruleset governs repositories
that **do not exist yet**, which is a strictly larger blast radius than the
sweep you asked for — and silently widening the blast radius of a command is the
same class of mistake as applying a policy without showing the diff. Without the
flag the run prints the recommendation and takes the narrow path:

```
Change the policy ONCE here instead of visiting 8 repositories:
  bash scripts/github-policy.sh apply --org ProductionMasterAI --org-level
```

The [LIVE-TARGET GATE](#exit-codes) applies to organization writes exactly as it
does to repository writes: without a terminal, `--yes` alone is not enough.

### The one thing that stays per-repository

**Required status-check contexts.** A context is a CI job *name*, names differ
per repository, and a name no workflow produces blocks every pull request in
that repository forever. There is no honest organization-wide context list, so
the org copy of `Default Branch - PR & CI` carries the pull-request rule and
linear history but **no check gate** — the rule is dropped rather than sent
gating on nothing. The per-repository sweep is still what supplies contexts.

The report says so every time; it is not something to discover from a diff.

### When organization-level is not available

Organization rulesets depend on the organization's **plan**, on your token's
scopes, and on the organization's own access policies. When any of those says
no, the tool reports the reason and falls back to per-repository policy. It is a
**fallback, not a failure** — the run continues and the exit code is unchanged.

| What the report says | What it means | What fixes it |
|---|---|---|
| *unavailable on this organization's plan* | organization rulesets need GitHub Team or Enterprise | nothing in the CLI — this is billing |
| *needs the `admin:org` scope* | your token cannot read them | `gh auth refresh -h github.com -s admin:org` |
| *not an organization owner* | your account cannot read them | somebody with owner access |
| *blocked by an organization or enterprise policy* | OAuth-app restrictions, SAML, or an IP allow list | an organization admin |
| *organization does not exist or this token cannot see it* | wrong name, or no visibility | check the name |
| *a repository filter is in effect* | see below | drop `--include`/`--exclude` |

Measured on this account, 2026-08-19: `ProductionMasterAI` (plan `team`) answers
`200 []` — available, with no organization rulesets yet. `SentinelAIOrg` (plan
`free`) answers `403 "Upgrade to GitHub Team to enable this feature."` — the
plan wall, reported as such and not as a permissions problem.

### Why a repository filter forces per-repository

`--include` and `--exclude` are POSIX EREs matched against `owner/name`.
GitHub's `repository_name` targeting takes fnmatch-style globs with their own
`~ALL` magic. `sandbox$` is a valid ERE *and* a valid literal glob that matches
nothing — so translating one into the other does not fail, it silently changes
which repositories are governed, in the direction of governing more of them than
you asked for. There is no safe automatic translation, so a filter means
per-repository and the reason is printed rather than the behaviour being quietly
different.

### Inherited rules are never edited from below

When an organization ruleset imposes something stricter than the policy — more
required approvals, signed commits, strict status checks, a CODEOWNERS review —
the repository is reported as `CONFLICT`, named, and **left alone**. There is no
flag that overrides this, and the tool will not route around an organization
rule. It is reported whether or not the repository's own rulesets drift, so a
repository that is compliant underneath a stricter org rule still tells you the
org rule is there.

The same guard applies in the other direction at organization level: an existing
organization ruleset that is stricter than canonical is reported as `CONFLICT`
and never overwritten — most of all up here, where one ruleset governs every
repository in the organization at once.

---

## Classic branch protection under a ruleset

Classic branch protection and rulesets are **not alternatives**. GitHub
evaluates every rule targeting the branch and **the stricter requirement wins**.
A repository can therefore pass a ruleset audit perfectly while a classic rule
nobody has opened in a year is what actually gates merges.

GitHub's **"Convert to ruleset"** button is how repositories end up in that
state: it copies classic protection into a new ruleset and **leaves the classic
protection enabled**. The two then apply simultaneously.

The `Legacy` block reports the overlap, and one line outranks everything else in
the report:

```
Legacy:
  ⚠ classic branch protection is present on main — migrate it to rulesets
  ⚠ classic branch protection AND 2 ruleset(s) both target main. GitHub applies
    both and the stricter requirement wins, so the rulesets above are not the
    whole story.
  !! a classic rule still forces "branch must be up to date"
     (required_status_checks.strict = true) on main. The canonical policy turns
     this OFF deliberately, and because GitHub aggregates classic protection
     with rulesets, this classic rule silently defeats
     strict_required_status_checks_policy: false — every merge invalidates every
     other open PR.
```

That `!!` line is the whole reason this check exists. The policy turns strict
off [for a stated architectural reason](#why-branch-must-be-up-to-date-is-off);
a leftover classic rule reinstates it **invisibly**, because the ruleset
everybody reads still says `false`. If you have ever wondered why every pull
request wants you to update the branch, this is the answer.

A repository in this state is reported **NON-COMPLIANT** even when its rulesets
are perfect. Reporting `COMPLIANT` there would be reporting the document instead
of the behaviour.

### The migration, and why the last step is yours

```
  1. Read both.
  2. Bring the ruleset up to canonical FIRST, while classic protection is still
     in force — the branch is over-protected for the duration, never under.
  3. Verify the ruleset alone carries everything you still want.
  4. Only then remove the classic protection, by hand.
```

**This tool will never do step 4**, at any verbosity and with any flag. Classic
protection is read here and never written. Deleting branch protection because a
ruleset *appears* to have taken over is un-protecting a branch on a belief, and
the confirmation belongs to a person looking at both.

---

## How many approving reviews a repository should require

Not a preference, and not a number to copy from another repository. It is
derived from two facts the API already knows:

```
count = 1 if (bypass_actor_present AND collaborators > 1) else 0
```

On a solo repository the owner authors every pull request, so a review
requirement is not strict — it is **unsatisfiable**. GitHub will not let you
approve your own PR, so the only way anything lands is `--admin`, and `--admin`
does not skip only the review rule: it bypasses **required status checks, linear
history and thread resolution at the same time**. Requiring one approval on a
solo repository therefore converts a green-CI gate into a bypass habit. That is
a net *loss* of safety wearing the costume of an increase.

The count is only meaningful **because** a bypass actor exists. With a bypass
actor and more than one collaborator, the two settings read together as: anyone
else's change needs a review, and the owner keeps an escape hatch on their own
repository. Without the bypass actor, raising the count to 1 is not stricter —
it is a lock on a door with no key.

The real gate on a solo repository is `required_review_thread_resolution`. A bot
review — Copilot, CodeQL, a Claude reviewer — opens threads, and the merge
blocks until they are resolved. That is a review requirement a single human can
genuinely satisfy without a bypass.

**Reading the collaborator count costs one extra API call per repository**, so
it is issued lazily: only when a bypass actor is present, because without one
the derived answer is `0` for any collaborator count. If the count cannot be
read, the derivation resolves to `0` — the safe direction, since an
unsatisfiable requirement conjured from a failed API call would push every merge
onto `--admin`.

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
