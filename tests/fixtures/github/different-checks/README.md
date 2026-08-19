# `different-checks` — required contexts unlike this repo's nine

**Represents:** another repo in the fleet whose CI reports `build`, `test` and
`lint (node 20)` — a perfectly correct configuration that shares no context name
with `tamirs-superpowers`.

**Covers: required status checks are per-repo, never global.**
`ground-truth-rulesets.md` says so in as many words. A policy that carries the
nine contexts of this repository into every repo would block merges everywhere
else on checks that do not exist. The canonical policy must express contexts as
per-repo configuration — or as the intersection every repo genuinely has — and
this fixture is the test that catches the globalising implementation.

**Expected:** the *structure* of the PR & CI ruleset is compared (linear history,
non-strict checks, 0 approvals, thread resolution required) while the context
*list* is treated as repo-local. A run here must not rewrite `build`/`test`/`lint`
into the nine names from `compliant`.

**Secondary coverage:** `lint (node 20)` contains a space and parentheses — a
context list joined and re-split naively will corrupt it.

**Contents:** as `compliant`, with `ruleset-21049069.json` carrying the three
foreign contexts, plus a one-workflow `workflows.json`.
