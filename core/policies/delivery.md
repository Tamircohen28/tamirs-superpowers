# Policy: delivery

## Default

**One user objective = one pull request.**

A worker task ends at `commit + handoff`. It does not open a PR, does not run
CI, and does not merge. Delivery happens once, at objective level, from the
integration branch, after Tier 2 validation and review have passed
(`validation.md`).

This is the default because the alternative — a PR per task — produces review
fragments no one can evaluate independently, N× the CI cost, and a merge order
that has to be babysat.

## Exceptions — the complete list

More than one PR is correct only when one of these holds:

1. **The tasks are truly independent deliverables** — separately reviewable,
   separately revertable, and useful on their own.
2. **Security isolation requires separation** — for example a credential
   rotation or a sensitive fix that must not sit in a large diff.
3. **Deployment sequencing requires separation** — a migration that must ship
   and settle before the code that depends on it.
4. **The user explicitly asked for multiple PRs.**
5. **The objective exceeds a configured size or risk threshold**, where the
   project has set such a threshold.

An objective delivering as anything other than `single-pr` records which
exception applies in `objective.delivery.exception_reason`. "It felt cleaner"
is not on the list.

## Auto-merge is policy, not invariant

Auto-merge is a **configurable preference**, explicitly demoted out of the hard
rules (`safety.md`). It is enabled when — and only when — the repository's
configuration and the user's preference both allow it.

Never force auto-merge against branch protection, a required-review setting, or
a stated user preference. When auto-merge is unavailable, delivery stops at
"PR open and green" and says so; it does not merge by another route.

Likewise, **strict branch-update-before-merge is loose by default.** Requiring
every branch to be fully current before merge is a repository setting, not a
universal rule.

## Delivery preconditions

Before a PR is opened:

- every task in the objective is `completed`, `cancelled`, or explicitly
  deferred with the deferral recorded;
- the integration branch contains every merged worker branch;
- Tier 2 validation passed, with real output;
- every `blocking` review finding is resolved;
- no secret is present in the diff (`safety.md`, invariant 1).

## After the PR is open

`pr-dev` remains the delivery lifecycle driver: it understands objective
metadata, the integration branch, loose vs strict update policy, merge queue
and auto-merge availability, branch protection, and CI supersession.

**Opening a PR and merging it are separate steps.** Absent an explicit
instruction or an active delivery skill that carries that authorization,
delivery ends at "PR is open, here is the URL".

## When there is no GitHub

`github_cli` is a capability, not an assumption. Without it, delivery ends at a
pushed (or purely local) integration branch, and reports exactly that — never a
claim that a PR was opened (`safety.md`, invariant 8).
