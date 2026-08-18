# Capability model

This framework runs on six harnesses that do not agree on what an agent can do. Claude
Code has hooks; OpenCode has a JS plugin API instead. Cursor has skills but will not run
a Claude-shaped hook bundle. Gemini installs as a git-URL extension; nobody else does.

The capability model is how a skill finds that out **before** it depends on something,
instead of failing halfway through in front of a user.

---

## The two files

| File | Role |
|---|---|
| [`core/capabilities/schema.json`](../../../core/capabilities/schema.json) | JSON Schema (draft 2020-12) defining the shape and the legal status values. |
| [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json) | The registry itself: one entry per platform, one row per capability. |

Validated by `scripts/check-capability-registry.sh`, which also asserts that every target
shipped in `docs/engineering/build-and-release/platform-targets.json` has a registry
entry. A platform that ships without a capability row is a platform whose gaps are
invisible, so that check is a hard failure.

## Platform ids

Registry ids are **snake_case**, identical to the keys in
`docs/engineering/build-and-release/platform-targets.json`: `claude_code`,
`claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode`. Capability keys are
snake_case too.

**There is a second namespace, and mixing them up is the foreseeable authoring mistake.**
A skill's frontmatter `compatibility:` block uses **kebab-case** — `claude-code`,
`claude-desktop`, `codex`, `cursor`, `gemini`, `opencode` — because it is frontmatter and
follows frontmatter convention. Note `gemini`, not `gemini-cli`.

| Where | Convention | Example |
|---|---|---|
| Registry `platforms` keys, `platform-targets.json` | snake_case | `gemini_cli` |
| Skill frontmatter `compatibility:` | kebab-case | `gemini` |
| Capability ids (everywhere) | snake_case | `github_cli` |

Each is enforced in its own place, so a mix-up fails loudly rather than silently. To
bridge them, every platform carries an `aliases` array (`claude_code` also answers to
`claude-code` and `claude`; `gemini_cli` answers to `gemini`). Normalize by matching an
incoming id against ids and aliases together. `check-capability-registry.sh` proves two
things about that table: it is collision-free, and **every id the frontmatter schema
allows resolves through it** — so the two namespaces cannot drift apart unnoticed.

Each platform also carries `doc_urls`, the authoritative upstream documentation, kept in
sync with the `doc_urls` array in `platform-targets.json`. Tools that fetch platform docs
should prefer this over their own bundled URL lists.

## Capability keys

Nineteen keys, fixed by the `enum` at `$defs.capabilityKey` in `schema.json`. That enum
is the single capability vocabulary — skill frontmatter validation reads it directly, so
a skill cannot declare a capability the registry does not define:

`skills`, `skill_auto_invocation`, `subagents`, `parallel_subagents`, `agent_teams`,
`hooks`, `mcp`, `statusline`, `shell`, `git`, `github_cli`, `background_tasks`,
`worktree_isolation`, `plugin_marketplace`, `extension_install`, `slash_commands`,
`ask_user_question`, `artifacts`, `session_transcripts`.

Each is defined once, at the top of the registry, under `capability_definitions` — with
a `summary` of what it means and a `degradation` line stating what a skill does without
it. Definitions live in one place so "hooks" cannot quietly mean two different things in
two platform entries.

## Status values

| Status | Meaning | Skill should |
|---|---|---|
| `native` | First-class platform feature. | Use it. |
| `native-experimental` | Shipped, but flagged or documented as unstable. | Use it, never require it. |
| `partial` | Present with material limits, spelled out in `notes`. | Use it inside the stated limits. |
| `emulated` | The framework builds it from lower primitives, usually shell + git. | Use it; expect the manual steps. |
| `adapter` | Provided through a platform-specific translation, not the canonical artifact. | Use the adapter; never hand-edit generated output. |
| `unsupported` | Verified absent. | Take the `fallback`. |
| `unknown` | Not verified. | **Treat exactly as `unsupported`.** |

`unknown` is the load-bearing value. It exists so the registry can be honest about the
large fraction of platform behaviour nobody here has measured. It is never an optimistic
placeholder: at runtime it resolves to "not available", and it must never be advertised
to a user as working.

**`unsupported` and `unknown` behave identically at runtime but mean different things,
and the difference is measurement.** `unsupported` is a positive claim: it was tried and
it failed, and the note should carry the error text. `unknown` says nobody looked. Never
write `unsupported` for something merely unattempted — that fabricates evidence just as
surely as writing `native` does, and it tells the next maintainer the question is settled
when it is open. Gemini's `subagents` row is `unsupported` because `agents/*.md` were
loaded and rejected with `tools.0: Invalid tool name`; its `hooks` row is `unknown`
because Gemini accepted the outer shape and nobody checked whether the events fire.

The mirror-image error is reaching for `native` or `adapter` when a capability works only
through a documented detour. That is what `partial` is for: Gemini loads zero skills from
the extension itself, yet skills do work through a second per-domain install command, so
the row is `partial` with the detour in the `fallback`. `adapter` is narrower still — it
means a *generated artifact* exists, as `.opencode/agent/` does for OpenCode subagents.
Where no artifact is generated and nothing runs, the answer is `unsupported`.

## Row shape

```json
"hooks": {
  "status": "partial",
  "since": "3.16.17",
  "validation": "jq empty .cursor-plugin/plugin.json",
  "fallback": "Treat guards as advisory; enforce the same rules in CI.",
  "notes": "Claude-shaped plugin hooks do NOT run under a Cursor plugin install."
}
```

Two invariants the schema enforces, both about honesty:

1. **`native` and `native-experimental` require a `validation` command.** Evidence over
   declarations — a status claim with no way to prove it is an opinion.
2. **Every other status requires a `fallback` or `notes`.** A gap must say what happens
   instead, so the degradation path is written down before it is needed.

A third invariant is enforced by `minProperties`/`maxProperties`: **every platform must
carry a row for every capability key.** Omission is a schema error. You cannot hide a
gap by staying silent about it — you have to write `unknown` and say why.

---

## Two vocabularies

There are two status enums in this framework and they are deliberately different,
because they answer different questions:

| | Question | Kind of claim | Enum |
|---|---|---|---|
| **Capability status** (this registry) | How does platform P implement capability C? | mechanism | `native`, `native-experimental`, `partial`, `emulated`, `adapter`, `unsupported`, `unknown` |
| **Skill compatibility** (`compatibility:` in SKILL.md, defined in `core/schemas/skill-frontmatter.json`) | Does skill S work on platform P? | outcome | `supported`, `partial`, `emulated`, `unsupported`, `unknown` |

Unifying them would lose information in one direction and demand invented information in
the other. `native` is meaningless as a statement about a skill — a skill is never
"natively implemented" — and `adapter` is a fact about the platform, not the skill. Push
skill authors to choose between `native` and `adapter` and they end up asserting
mechanism they have no way to verify, which is the failure this model exists to prevent.

`unknown` is the one value that means the same thing on both sides, because it is
epistemic rather than mechanistic: nobody measured this. It resolves to "unavailable" at
runtime in both vocabularies.

### Derivation

A skill's compatibility with a platform is **derived** from the registry, not asserted by
hand. Take the skill's `capabilities.required` list, read each one's status for that
platform, and reduce:

| Registry status of a required capability | Contributes |
|---|---|
| `native`, `native-experimental`, `adapter` | `supported` |
| `emulated` | `emulated` |
| `partial` | `partial` |
| `unknown` | `unknown` |
| `unsupported` | `unsupported` |

When the required capabilities land on different values, **the worst one wins**, in this
precedence:

```
unsupported  >  unknown  >  partial  >  emulated  >  supported
```

`unsupported` outranks `unknown` because a measured failure is a stronger claim than an
unmeasured one. `unknown` outranks `partial` because an unverified capability resolves to
unavailable at runtime, while a partial one still works within stated limits.

`adapter` derives to `supported` rather than `emulated` on purpose: an adapter means a
generated artifact exists and the platform then consumes it natively — OpenCode loads
`.opencode/agent/` as ordinary agents. `emulated` means the framework performs primitive
steps at runtime, every time, each of which can fail. From a skill's point of view the
first is indistinguishable from native and the second is not.

Rows differ in how well established they are — Gemini's and OpenCode's are
measurement-backed while several others are declaration-backed — and a derived
compatibility value is only ever as good as the row it came from. See
[Provenance](#provenance).

This is what makes per-skill compatibility tables and `platform-differences.md`
generable. `scripts/check-capability-registry.sh` asserts the derivation stays **total in
both directions** — every registry status maps to some compatibility value, and every
compatibility value is reachable — so neither enum can grow a value that silently has no
counterpart.

---

## How a skill declares capabilities

In `SKILL.md` frontmatter, under the framework's metadata namespace:

```yaml
metadata:
  tamirs:
    capabilities:
      required: [skills, shell, git]
      optional: [subagents, github_cli, background_tasks]
```

- **`required`** — the skill cannot function without these. On a platform where any of
  them is `unsupported` or `unknown`, the skill declares itself unavailable, by name,
  with the missing capability stated. It does not half-run.
- **`optional`** — the skill is better with these and correct without them. Each optional
  capability must have a working path when it is absent.

Anything not listed is not assumed. A skill that never declares `github_cli` must not
shell out to `gh`.

### The rule this replaces

Previously a skill would simply call `gh`, spawn a subagent, or rely on a `SessionStart`
hook having fired, and would break on any platform that lacked it — usually silently,
which is worse. Declaring capabilities turns that from a runtime surprise into a static
check.

## How degradation works

Degradation is written per capability, not per platform. That is what keeps the adapter
count from exploding: adding a seventh platform adds one registry entry, not a new
branch in every skill.

The order of preference:

1. **Use the native path** when the status is `native` / `native-experimental`.
2. **Use the adapter** when the status is `adapter` — never hand-edit its output; the
   drift check (`make opencode-agents-check`) exists precisely to catch that.
3. **Emulate** when the status is `emulated`: the skill performs the primitive steps
   itself. `worktree_isolation` on Codex, Cursor, Gemini and OpenCode is exactly this —
   explicit `git worktree add` / `remove`, where Claude Code gets it from hooks.
4. **Take the fallback** when the status is `unsupported` or `unknown`, and **say so**.
   Silent degradation is a defect: a user who thinks a review ran in parallel when it
   ran sequentially has been misled.

Never emit a third behaviour — pretending. A skill that cannot open a PR because
`github_cli` is absent prints the PR body for the user to file. It does not claim to
have opened one, and it does not fail the whole task.

### Worked example

`pr-dev` declares `required: [skills, shell, git]` and `optional: [github_cli, subagents,
background_tasks]`.

| Platform | Result |
|---|---|
| Claude Code | Everything native. Full run: subagents fix review threads in parallel, `gh` merges. |
| OpenCode | `subagents` is `adapter` (generated `.opencode/agent/`), `github_cli` depends on the host. Runs, sequentially, with `gh` if present. |
| Any platform, `gh` absent | Runs through the diff and review work, then prints the PR body and the exact `gh pr create` command for the user. Reports the degradation. |

## Where capabilities are consumed

- **`scripts/doctor.sh`** — reports the capabilities of the detected platform, plus the
  fallback line for anything not native. This is the user-facing view of the registry.
- **Provider selection** — [`core/providers/selection.md`](../../../core/providers/selection.md)
  filters candidate providers by the role's required capabilities before anything else.
  `unknown` filters a provider out.
- **Static skill checks** — a skill declaring a capability no platform provides, or
  using a key not in the enum, is a validation failure rather than a runtime one.

## Maintaining the registry

Change a row when, and only when, you have evidence:

1. Run the `validation` command on the real harness.
2. Update `status`, and `since` if a version floor is now known.
3. Update `notes` with what you actually observed, and `fallback` if the gap changed.
4. Bump `last_reviewed`.
5. Run `bash scripts/check-capability-registry.sh`.

Moving a row from `unknown` to `native` without running its validation command is the
one change this model exists to prevent. When in doubt, leave it `unknown` — an
understated registry costs a little capability; an overstated one costs user trust.

### Provenance

**Not every row in this registry is equally well established, and a measurement outranks
this registry whenever the two conflict.** That precedence is a project rule, not a
courtesy: it is what corrected `gemini_cli` from nine `native` rows to five.

| Platform | Provenance |
|---|---|
| `gemini_cli` | **Measured.** Gemini CLI 0.55.1 against a probe extension, 2026-08-19. Error text recorded in `docs/user/install/gemini.md`. |
| `opencode` | **Measured.** OpenCode 1.18.11 on the maintainer machine, including the `hooks` and symlink-discovery findings. |
| `claude_code` | Mostly verified through this repo's own validators, which run against it on every change. |
| `codex`, `cursor` | Declaration-backed: derived from `platform-targets.json`, which records its own `verification_method` per target. |
| `claude_desktop` | Largely unverified — nine `unknown` rows, and honestly so. |

The Gemini entry is the cautionary case worth remembering. It was originally written from
REFACTOR-SPEC §13.4, which enumerates what Gemini extensions *can* package, and six
capabilities were marked `native` on that basis. A probe then showed the extension loads
**zero** skills (discovery scans one level; canonical skills are two deep) and rejects
`agents/*.md` outright. The spec was not wrong about Gemini in general; it was wrong about
*this repo on* Gemini, which is the only question the registry asks.

So: a specification, a vendor changelog, or a documentation page is a reason to go and
measure, never a substitute for having measured. When a measurement contradicts a row,
the row is what changes — and its note should carry the observed error text, so the next
maintainer inherits the evidence rather than the conclusion.
