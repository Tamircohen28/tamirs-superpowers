# Adding a platform

The procedure for making a sixth agent platform — or a new **surface** of one of the five
already here — a first-class target. The *contract* — what an adapter is allowed to be —
lives in [adapter-contract.md](adapter-contract.md); this page is the checklist you work
through.

Gemini was added this way, and it is the worked example throughout.

---

## First: is this a platform or a surface?

The registry is rooted at the platform and lists its runtime surfaces underneath — see
[capability-model.md](capability-model.md#platforms-and-surfaces). Two different jobs hide
behind "add a platform", and they cost very different amounts:

| | You are adding | Work |
|---|---|---|
| **A new platform** | A vendor this repo has never shipped to at all — a new key under `platforms`, with at least one surface under it. | The full checklist below. |
| **A new surface** | Another way to install into a platform already in the registry — its CLI, its desktop app, its editor extension. | [Adding a surface](#adding-a-surface-to-an-existing-platform) — much smaller, and smallest of all if the surface is unverified. |

If the thing you are adding installs the manifest an existing platform already ships —
the Codex IDE extension reading `.codex-plugin/plugin.json`, the Cursor CLI reading
`.cursor-plugin/plugin.json` — it is a surface, not a platform. Adding it as a platform
would give the repo two entries claiming the same artifact.

### Supported surfaces vs supported targets

These two counts are both correct and they are not the same number, so check which one a
sentence means before changing it.

- **Six supported surfaces** — the registry entries with `support: "supported"`:
  `claude_code`, `claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode`.
- **Five supported targets** — `supported_targets` in
  [`platform-targets.json`](../build-and-release/platform-targets.json): `claude_code`,
  `codex`, `cursor`, `gemini_cli`, `opencode`.

`claude_desktop` is the difference, and it is not an oversight. It carries
`runtime_surface_of: "claude_code"`: it installs the Claude Code plugin from the Claude
Code listing and ships no manifest, adapter or version consumer of its own. A *target* is
something this repo distributes to; Claude Desktop is a place that same distribution runs.
So it is a fully supported surface with all 19 capability rows, and it is not a sixth
target. `check-feature-equivalence.sh` and `tests/test-docs.sh` both exclude
`runtime_surface_of` surfaces when counting targets, for exactly this reason.

## Before you start

Answer two questions honestly:

1. **What does this surface actually support?** Not what its marketing page says —
   what you can demonstrate with a command. Anything you cannot demonstrate is `unknown`,
   and a surface where you cannot demonstrate *anything* is `unverified` (see below).
2. **Does anything canonical need to change?** If the answer is "duplicate the skills in its
   format", stop. A platform that cannot read a portable skill is a platform that needs a
   *generator*, and a generator needs a drift check.

---

## Adding a surface to an existing platform

A surface is one entry in that platform's `surfaces` map. Which fields it needs depends
entirely on whether you have measured it, and the schema will not let you blur the two.

### An unverified surface — the honest minimum

Use this when the surface is real, users will ask about it, and **nobody here has run
it**. Three fields, and no capability claims of any kind:

```json
"cursor_cli": {
  "display_name": "Cursor CLI",
  "kind": "cli",
  "support": "unverified",
  "unverified_reason": "The CLI shares .cursor-plugin/plugin.json with the IDE ... but no CLI run has been recorded here. The measurements under cursor were taken against an IDE plugin install; carrying them over would be an assumption, not evidence."
}
```

- `kind` — `cli`, `desktop`, `ide`, `web` or `cloud`.
- `support` — `unverified`.
- `unverified_reason` — required, and it has a job: state **what is known**, **what was
  never measured**, and **why the sibling surface's results were not carried over**. That
  last clause is the one readers need, because the sibling's rows are right there.

The schema **rejects** `capabilities` and `install` on an unverified surface. Do not
work around that by writing nineteen `unknown` rows — an absent block says *nobody
measured this*; a block of `unknown` reads as *someone checked and found nothing*. Only
one of those is true.

Then stop. An unverified surface:

- is **not** added to `supported_targets` in
  [`platform-targets.json`](../build-and-release/platform-targets.json);
- gets **no** install guide, no README badge, no adapter descriptor, no CI validation;
- is **never** counted in "N supported targets" prose;
- appears in a capability matrix only as an explicit "not measured", never as a column of
  cells.

It is dropped from the flattened view every consumer reads, so nothing downstream needs
to learn about it. Only docs that list surfaces do.

### Promoting a surface to `supported`

This is the real work, and it is the same evidence bar as a new platform. The surface
needs, all of it, for itself:

1. **An `install` block** — `type`, the actual command, and a `doc` pointing at a real
   `docs/user/install/<surface>.md`.
2. **A `validation` block** — the command that proves the install worked, run on the real
   surface.
3. **All 19 capability rows**, measured on *that* surface. The sibling's rows are not
   evidence; if they were, the surface would not have been unverified.
4. **A `platform-sync` platform file** —
   `skills/documentation/platform-sync/references/platforms/<id>.md` — so its upstream
   changes get reviewed like every other supported surface's. `platform-sync` resolves its
   target list from the registry at run time, so this file is the only edit it needs.
5. **An entry in `supported_targets`** in `platform-targets.json` — *unless* the surface
   is a `runtime_surface_of` another, which ships no distribution artifact of its own and
   is covered by its host's target (see [surfaces vs
   targets](#supported-surfaces-vs-supported-targets)) — plus the README / `AGENTS.md` /
   `CLAUDE.md` naming that `scripts/check-doc-claims.sh` enforces.

Drop `unverified_reason` when `support` becomes `supported`. Then run the [definition of
done](#definition-of-done).

A surface may also be added as `supported` from the start, without an unverified stage —
`claude_desktop` was. The requirements are identical; there is simply no intermediate
entry.

---

## Adding a platform: the checklist

### 1. Registry entry — always first

Add a platform block to [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json):
`display_name` (the platform as a user names it — "Gemini", not "Gemini CLI"), `vendor`,
`doc_urls`, a `surfaces` map, and a `primary_surface` naming the surface that is this
platform's reference install. `primary_surface` must be a key of `surfaces` and must be a
supported one.

Then, for the platform's primary surface, every capability key from `schema.json`. For each:

- a `status` you can defend;
- a `validation` command where the status is `native` or `adapter`;
- a `fallback` (or `notes`) for everything that is not `native`.

Use `unknown` freely **within a measured surface**. It is the honest status for a
capability you have not exercised on a surface you otherwise have, it is treated as
unavailable at runtime, and it is far better than an optimistic `native` that strands a
user mid-objective. A surface you have not exercised *at all* is a different thing: that
is `unverified`, with no capability block.

Any further surfaces the platform ships go in the same map, each by the rules
[above](#adding-a-surface-to-an-existing-platform). A platform with exactly one known
surface still uses the map — the shape does not change when a second one appears.

```bash
bash scripts/check-capability-registry.sh .
```

### 2. Adapter descriptor

Add `platforms/<id>/adapter.yaml`: `id`, `display_name`, `registry_key` (the **surface**
id it installs into), a coarse capability summary, the `manifest` path, `install` (type +
doc), `validation.command`, and `notes` explaining anything surprising. It is a **pointer
file** — the registry stays authoritative, and the two must not disagree.

### 3. Manifest or config

Whatever the platform actually resolves — `gemini-extension.json`, `opencode.json`,
`.codex-plugin/plugin.json`. Point it at the canonical `skills/` tree. **Do not copy skills.**

Keep it dependency-free: do not introduce a Node or Python runtime because a platform's
extension template happens to include one. If the toolkit only needs declarative content,
ship declarative content.

### 4. Version consumer

If the manifest carries a version, add it to `consumers[]` in
[`plugin-version.json`](../../../plugin-version.json) with `required: true` (or `false` if
the file may legitimately be absent):

```bash
bash scripts/check-version-truth.sh .
bash scripts/check-version-truth.sh . --sync    # repair; never hand-edit a consumer
```

### 5. Install guide

`docs/user/install/<surface>.md`, with all four sections — **install · verify · update ·
uninstall** — plus a capability/limitation table sourced from the registry. Guides are
per **supported surface**, because the install command is a property of the surface.
Register it as `install_doc` for the target in
[`platform-targets.json`](../build-and-release/platform-targets.json) and add the surface
id to `supported_targets` — see the caveat for runtime surfaces
[below](#supported-surfaces-vs-supported-targets).

`scripts/check-doc-claims.sh` fails if a supported target is missing from the README,
`AGENTS.md` or `CLAUDE.md` — by its **surface display name** — or if its `install_doc`
does not exist.

### 6. Validation wired into CI

Two kinds, and they must stay separate:

- **Always-run static checks** — the manifest parses, the adapter and registry agree, any
  generated artifact is current. These belong in `make validate` and CI.
- **Live CLI validation** — `gemini extensions validate .`, `opencode debug skill`,
  `claude plugin validate .`. These run only where the CLI exists and must degrade to a skip,
  never a failure, when it is absent.

Add `tests/test-<platform>-adapter.sh` following `test-gemini-adapter.sh` /
`test-opencode-adapter.sh`, then wire it into the test target and the
[testing matrix](../build-and-release/testing-matrix.md).

### 7. Generated artifacts — only if the format genuinely differs

If, and only if, the platform's frontmatter is incompatible: write a generator under
`scripts/`, generate into a per-platform directory, and add a `*-check` target that fails on
drift. `.opencode/agent/` is the model — generated by `build-opencode-agents.sh`, enforced by
`make opencode-agents-check`, and never hand-edited.

### 8. Platform-sync coverage

`platform-sync` audits upstream changelogs per surface, and resolves which surfaces to
audit from the registry rather than a hardcoded list. Add
`skills/documentation/platform-sync/references/platforms/<id>.md` for the new target.
A supported target without one is a target that silently goes stale.

### 9. Docs surface

- Add a row to the README platform table (platform, its surfaces, and the registry ids).
- The [platform-differences](../../user/platform-differences.md) matrix regenerates from the
  registry — no hand-written cells.
- Add the guide to [`docs/user/install/README.md`](../../user/install/README.md).
- If the platform ships surfaces you did not measure, list them as unverified with their
  reason. Listing them is the point: it turns "does this work in the Cursor CLI?" from
  silence into an honest answer.

---

## What adding a platform must **not** require

- Duplicating skills, rules, roles, or policies into a platform-specific tree.
- A new runtime dependency (Node, Python) for declarative content.
- Editing a canonical file to make one platform happy — that is a sign the canonical model,
  not the adapter, needs the change, and it should be made once, for everyone.
- Claiming a capability you have not exercised.
- Carrying one surface's measurements over to a sibling surface because they share a
  manifest. Sharing an artifact is not sharing a runtime.
- Anyone needing a second paid AI subscription to run the workflow.

## Definition of done

```bash
bash scripts/check-capability-registry.sh .
bash scripts/check-version-truth.sh .
bash scripts/check-doc-claims.sh .
bash tests/test-<platform>-adapter.sh
make validate
```

All green, plus: the install guide has all four sections, every `native` claim has a
validation command behind it, and every non-`native` status has a fallback a user can act on.

For an **unverified** surface the definition of done is much shorter, and deliberately so:
`check-capability-registry.sh` passes, the `unverified_reason` answers all three of its
questions, and the surface appears in **no** target list, badge row or capability matrix.

## Removing or downgrading a platform or surface

Same path in reverse, and equally explicit: change the registry first (with a reason in
`notes`), then the adapter, then the docs. Never delete a target silently — a user with it
installed needs to read why it went away.

Downgrading a supported surface is *not* the same as marking it `unverified`. `unverified`
means never measured; a surface that regressed **was** measured, so it keeps its
capability block with the affected rows moved to `unsupported` and the note saying what
changed and when. See
[adapter-contract.md](adapter-contract.md#removing-or-downgrading-a-platform).
