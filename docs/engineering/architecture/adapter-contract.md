# Adapter contract

What it takes to add a platform to this framework — and, just as importantly, what it
must never take.

The test of this contract is a number: **adding a sixth platform should touch about five
files, none of which is a skill.** If a new platform ever requires editing skills, the
contract has been violated and the violation is the bug.

One adapter serves one platform; the capability registry underneath it is keyed by
**surface** — the CLI, the desktop app, the IDE extension a user actually installs into.
The two do not always match one-to-one, and where they do not, the adapter names the
surface it installs into. See
[capability-model.md](capability-model.md#platforms-and-surfaces).

---

## The shape of an adapter

```text
platforms/<id>/
├── manifest/config      # the platform's own install descriptor
├── adapter.yaml         # adapter metadata (below); registry_key points at the registry
├── install docs         # docs/user/install/<id>.md
└── tests                # the validation command, wired into CI
```

Plus **one registry entry** in
[`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json) — a
platform, with the surface this adapter installs into underneath it — and one entry in
`docs/engineering/build-and-release/platform-targets.json`, which is keyed by **surface**
id.

`platforms/<id>/adapter.yaml` is a thin pointer, not a second source of truth: it names
the manifest, the install path, and the validation command, and defers capability
questions to the registry via `registry_key`. The manifests themselves stay where their
harnesses require them — `.claude-plugin/`, `.cursor-plugin/`, `.codex-plugin/`,
`opencode.json`, `gemini-extension.json`. Those locations are dictated by the tools and
are not moving; the contract is about the *set* of artifacts, not one directory.

## Adapter metadata

```yaml
id: gemini
display_name: Gemini CLI
registry_key: gemini_cli   # the SURFACE id in the capability registry (platform: gemini)
capabilities:              # coarse summary only; the registry is authoritative
  skills: native
  subagents: native
  hooks: native
  mcp: native
install:
  type: extension
  command: gemini extensions install https://github.com/Tamircohen28/tamirs-superpowers
  doc: docs/user/install/gemini.md
validation:
  command: gemini extensions validate .
```

The same three fields — `display_name`, `install`, `validation` — are required on every
**supported surface** in the registry, and `scripts/check-capability-registry.sh` fails
without them. `registry_key` names that surface, not its platform: `gemini_cli`, not
`gemini`. An unverified surface has no adapter, because it has no install path to point
at. `install.type` is one of `marketplace`, `extension`, `plugin-dir`, `path`,
`symlink`, `manual`.

`validation.command` is the load-bearing field. It is the answer to "how do you know?"
for every `native` claim in that platform's rows.

---

## What adding a platform requires

### 1. One registry entry

A platform block with a `surfaces` map and a `primary_surface`, and — on the surface this
adapter installs into — all nineteen capability rows with honest statuses. Anything
unmeasured **on a surface you did have** is `unknown` with a note; a surface you never
exercised at all is `support: "unverified"` and carries no rows whatsoever. See
[capability-model.md](capability-model.md). This is where the real work is, and it is
bounded: it is research about the platform, not code.

### 2. One manifest or config

Whatever the harness reads to discover the plugin. It points at the **canonical** trees —
`skills/`, `agents/`, `rules/` — it does not contain copies of them.

### 3. One install doc

`docs/user/install/<id>.md`, one per supported surface, declared as `install_doc` in
`platform-targets.json` (which `scripts/check-doc-claims.sh` verifies exists) and as
`install.doc` on that surface in the registry.
It must cover: install command, local-development install, how to confirm skills were
discovered, and which capabilities are absent on this platform and what happens instead.

### 4. One validation command, wired into CI

The command from `validation.command`, run when the CLI is available and skipped with a
clear message when it is not. A missing platform CLI on a CI runner is a skip, never a
failure — otherwise every contributor needs all five platforms installed.

### 5. One version consumer, if the manifest carries a version

Add it to `consumers` in [`plugin-version.json`](../../../plugin-version.json). It will
then be checked by `scripts/check-version-truth.sh` and repaired by its `--sync`. A
consumer whose file does not exist yet is skipped with a note, so the entry can land
before the adapter does.

### 6. Adapter generation, only if the format genuinely differs

If the platform needs a translated artifact — as OpenCode does for agent frontmatter —
generate it from the canonical source with a script, and add a drift check that fails
when the generated output no longer matches. Never a hand-maintained copy: a copy is a
future divergence with a date on it.

---

## What adding a platform must NOT require

These are hard prohibitions, not preferences.

| Prohibited | Why | Do instead |
|---|---|---|
| **Copying skills** into a per-platform directory | N platforms × M skills copies is N×M drift surfaces, and the copies always win an argument with the original by being nearer. | Point the manifest at canonical `skills/`. |
| **Copying rules** | Same reasoning. `.cursor/rules/*.mdc` are thin pointers into canonical rules, and drift-checked. | Reference or generate, then drift-check. |
| **Rewriting agents** | Canonical `agents/` is the source. | Generate the platform variant (`scripts/build-opencode-agents.sh`) with a check (`make opencode-agents-check`). |
| **Provider conditionals inside skills** | `if platform == cursor` in twenty skills is the exact combinatorial mess this architecture exists to avoid, and it makes every new platform an edit to every skill. | Declare capabilities; let the registry and the degradation rules resolve it. |
| **A new canonical source of truth** | Two sources of truth are zero sources of truth. | Extend the existing canonical tree. |
| **A new runtime dependency** | Adding Node to the framework because one platform's extension template happens to include one would tax all five platforms for one. | Keep adapter content declarative. |
| **Destructive migration of existing layouts** | Breaks installed users for a cosmetic gain. | Add the new adapter alongside; use compatibility shims. |

## Definition of done

A platform is a supported target when all of the following are true:

- [ ] Registry entry exists — platform, surfaces, `primary_surface` — with all 19 rows explicit on the supported surface and no `native` without a `validation` command.
- [ ] `bash scripts/check-capability-registry.sh` passes.
- [ ] `platform-targets.json` lists the **surface id** in `supported_targets` with a real `install_doc`. A surface carrying `runtime_surface_of` is the exception: it ships no artifact of its own, so it is covered by its host's target — `claude_desktop` is supported without being a target.
- [ ] `bash scripts/check-doc-claims.sh` passes (README and AGENTS.md name the target).
- [ ] `bash scripts/check-version-truth.sh` passes with the new manifest as a consumer.
- [ ] The validation command has been run on the real CLI, and its output recorded in
      `verification_method`.
- [ ] `bash scripts/doctor.sh` detects the platform and prints its capabilities.
- [ ] No skill was edited to accommodate it.

That last line is the contract. If a skill had to change, the capability it needed was
missing from the model — add the capability key, not the conditional.

## Removing or downgrading a platform

Same discipline in reverse. Downgrade rows to `unsupported` or `unknown` with a note
saying what changed and when; do not delete rows, because a deleted row reads as "never
investigated" rather than "regressed". Remove from `supported_targets` only once the
install doc says the target is retired.

For the same reason, **a regressed surface is never flipped to `support: "unverified"`.**
That value means nobody ever measured it, and deleting a measured block to reach it
destroys the evidence and misreports the history. Keep the block; move the rows.
