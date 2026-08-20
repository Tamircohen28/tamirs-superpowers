# Capability model

This framework installs into **five platforms** — Claude, Codex, Cursor, Gemini and
OpenCode — which do not agree on what an agent can do. Claude Code has hooks; OpenCode
has a JS plugin API instead. Cursor has skills but will not run a Claude-shaped hook
bundle. Gemini installs as a git-URL extension; nobody else does.

Nor does a platform agree with itself. Claude ships a terminal client and a desktop app;
Cursor ships an IDE and a CLI. Those are separate installs with separate capabilities, so
the registry names each one: a **surface**. Six surfaces are supported — Claude Code,
Claude Desktop, Codex CLI, Cursor IDE, Gemini CLI and OpenCode CLI — and four more are
listed as unverified, claiming nothing.

The capability model is how a skill finds all that out **before** it depends on
something, instead of failing halfway through in front of a user.

---

## The two files

| File | Role |
|---|---|
| [`core/capabilities/schema.json`](../../../core/capabilities/schema.json) | JSON Schema (draft 2020-12) defining the two-level shape — platforms, and the surfaces underneath them — and the legal status values. |
| [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json) | The registry itself: one entry per platform, one entry per surface it ships, and — for each supported surface — one row per capability. |

Validated by `scripts/check-capability-registry.sh`, which also asserts that every target
shipped in `docs/engineering/build-and-release/platform-targets.json` — a file keyed by
**surface** id — has a matching surface in the registry. A surface that ships without
capability rows is a surface whose gaps are invisible, so that check is a hard failure.

## Platforms and surfaces

The registry is rooted at the **platform** — the thing a user names when they say what
they use — and each platform carries a `surfaces` map of the runtime surfaces it ships:

| Platform | Surfaces |
|---|---|
| `claude` — Claude | `claude_code` (cli, supported) · `claude_desktop` (desktop, supported) |
| `codex` — Codex | `codex` (cli, supported) · `codex_ide` (ide, unverified) |
| `cursor` — Cursor | `cursor` (ide, supported) · `cursor_cli` (cli, unverified) |
| `gemini` — Gemini | `gemini_cli` (cli, supported) · `gemini_code_assist` (ide, unverified) |
| `opencode` — OpenCode | `opencode` (cli, supported) · `opencode_desktop` (desktop, unverified) |

Five platforms, ten surfaces, **six of them supported**. A surface's `kind` says what it
is — `cli`, `desktop`, `ide`, `web`, `cloud`.

### Why the split exists

Because capabilities and install paths are properties of a surface, not of a vendor. The
Claude Code CLI runs this repo's hook bundle; whether Claude Desktop does has never been
verified, and its row says so in as many words. Everything measured under `cursor` was
measured through an **IDE plugin install** — no Cursor CLI run has ever been recorded
here. The rows under `codex` are the Codex CLI's rows. A single entry per vendor can
state only one of those, and what it stated in practice was the CLI's answer, with
nothing on the page saying so.

The old flat shape made the problem visible in exactly one place and hid it everywhere
else: Claude got two entries, because its two surfaces were too obviously different to
merge, while Codex, Cursor and OpenCode got one each — as if they had only one surface.
They do not.

### `support`, and why an unverified surface is empty

Every surface carries a `support` value, and the enum has two members on purpose:

| `support` | Meaning | Carries |
|---|---|---|
| `supported` | This repo installs here, validates here, and has measured what it can do. | `install`, `validation`, and all 19 capability rows. |
| `unverified` | A real surface of the platform that this repo has **never exercised**. | `unverified_reason`, plus the identifying fields (`display_name`, `kind`, `aliases`, `doc_urls`). No `install`, no `validation`, no `capabilities`. |

The schema enforces both halves. A `supported` surface missing `install`, `validation` or
`capabilities` fails; an `unverified` surface that carries `capabilities` or `install`
fails too.

That second prohibition is the load-bearing one. **An unverified surface carries no
capabilities block at all — not a block of nineteen `unknown` rows.** Those two look
alike and are not. Nineteen `unknown` rows is nineteen statements, each implying someone
considered that capability on that surface and came up empty; a reader skims the block
and concludes the surface does nothing. No block at all says the only true thing —
*nobody measured this*. Silence about an unmeasured surface is honest; a page of invented
rows is not.

`unknown` is still the right value **inside** a supported surface, where the surrounding
block establishes that the surface was measured and this one row was not. The distinction
is between a gap in a measurement and the absence of a measurement.

What an unverified surface does owe the reader is its `unverified_reason`: what is known,
what was never measured, and why the sibling surface's results were not carried over.
`cursor_cli` shares `.cursor-plugin/plugin.json` with the IDE and Cursor documents CLI
sticky skills — and it still claims nothing, because carrying the IDE's measurements
across would be an assumption wearing evidence's clothes.

These surfaces are listed so a user asking *"does this work in the Cursor CLI?"* gets an
honest **not measured** instead of silence. They are never targets: no install guide, no
badge, no row in a capability matrix that implies measurement, and never counted in
"N supported targets" prose. And "not measured" is a claim in neither direction — never
write that a skill, hook or MCP server works there, and never write that it does not.

### `primary_surface`

Each platform names one `primary_surface` — the surface this repo treats as that
platform's reference install: `claude_code`, `codex`, `cursor`, `gemini_cli`, `opencode`.
It must be a key of that platform's own `surfaces`, and it must be a supported one. It is
the answer to "the user said *Cursor* — which surface did they mean?" for anything that
has to resolve a platform-level name to something concrete.

### The flattened view consumers read

Almost every consumer asks a per-**surface** question — *can the thing I am installed
into run a subagent?* — and every `validation` command runs against a surface, never
against a vendor. So consumers do not walk two levels. They read the flat,
one-entry-per-surface view built by
[`scripts/lib/registry.sh`](../../../scripts/lib/registry.sh):

```bash
source scripts/lib/registry.sh
flat="$(registry_flat_tmp core/capabilities/platforms.json)"   # caller owns cleanup
```

Each entry keeps every field its surface declared and gains two: `platform`, the platform
id it belongs to, and `platform_display_name`. The keys are surface ids — exactly the
shape `platform-targets.json` is keyed by, and exactly the shape consumers already
expected, so the reshape cost them no logic.

One number to keep straight: six surfaces are supported, but
`platform-targets.json` lists **five** supported *targets*. `claude_desktop` carries
`runtime_surface_of: "claude_code"` — it installs the Claude Code plugin from the Claude
Code listing and ships nothing of its own — so it is a fully supported surface and not a
separate distribution target. See
[platform-targets.md](../build-and-release/platform-targets.md#five-targets-six-supported-surfaces).

**Unverified surfaces are omitted from the flat view, deliberately.** They carry no
capabilities block, so including them would force every consumer to invent a reading for
a missing one — and the obvious invention, *absent means no*, is precisely the claim the
registry refuses to make. Consumers that want to *list* unverified surfaces (docs,
install guides, a "does it work on X?" answer) read `platforms.json` directly.

## Ids and namespaces

Platform ids, surface ids and capability ids are all **snake_case**. Surface ids are the
ones that matter to most consumers, because they are the keys in
`docs/engineering/build-and-release/platform-targets.json`: `claude_code`,
`claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode`. Platform ids are `claude`,
`codex`, `cursor`, `gemini`, `opencode` — three of which are spelled the same as their
primary surface, which is deliberate and safe because both levels share one namespace
(below).

**There is a second namespace, and mixing them up is the foreseeable authoring mistake.**
A skill's frontmatter `compatibility:` block uses **kebab-case** — `claude-code`,
`claude-desktop`, `codex`, `cursor`, `gemini`, `opencode` — because it is frontmatter and
follows frontmatter convention. Note `gemini`, not `gemini-cli`.

| Where | Convention | Example |
|---|---|---|
| Registry `platforms` keys | snake_case | `gemini` |
| Registry `surfaces` keys, `platform-targets.json` | snake_case | `gemini_cli` |
| Skill frontmatter `compatibility:` | kebab-case | `gemini` |
| Capability ids (everywhere) | snake_case | `github_cli` |

Each is enforced in its own place, so a mix-up fails loudly rather than silently. To
bridge them, platforms and surfaces both carry an `aliases` array, and **ids and aliases
from both levels live in one flat namespace**: `claude_code` also answers to
`claude-code`, the platform `claude` answers to `anthropic`, and the frontmatter id
`gemini` resolves to the *platform* `gemini` while `gemini_cli` is one of its surfaces.
Normalize an incoming id by matching it against every id and alias at both levels.
`check-capability-registry.sh` proves two things about that table: it is collision-free
across platforms and surfaces together, and **every id the frontmatter schema allows
resolves through it** — so the two namespaces cannot drift apart unnoticed.

`doc_urls` appears at both levels: on a platform, the authoritative upstream docs across
all its surfaces; on a surface, the ones specific to that surface, kept in sync with the
`doc_urls` array in `platform-targets.json`. Tools that fetch platform docs should prefer
these over their own bundled URL lists.

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

## What a row is about

**A capability row describes THIS REPO'S ARTIFACTS ON THAT SURFACE — not the platform's
abstract feature set.** The question a row answers is *"if I install this plugin into the
Gemini CLI, do my hooks run?"*, never *"is Gemini a hooks-capable product?"* The second is
a vendor question, and this registry is not a vendor comparison. It is also why rows hang
off surfaces rather than platforms: an artifact is installed into a surface, so only a
surface can answer.

This is not a new rule; it is what every existing row already means. `cursor.hooks` is
`partial` because *our* bundle does not fully run there, not because Cursor lacks hooks.
`opencode.hooks` is `unsupported` because *we* ship no plugin module, not because OpenCode
lacks a plugin API — it has one. Read the other way, both rows are simply wrong, and a
definition that falsifies most of the existing data is the wrong definition.

The practical consequence, row by row: **when a row says `unsupported`, it means our
artifact does not work on that surface.** A reader who wants to know what the vendor's product can
do has to go and measure it themselves — this registry will not tell them, and was never
trying to.

## Status values

| Status | Meaning | Skill should |
|---|---|---|
| `native` | First-class platform feature. | Use it. |
| `native-experimental` | Shipped, but flagged or documented as unstable. | Use it, never require it. |
| `partial` | Present with material limits, spelled out in `notes`. | Use it inside the stated limits. |
| `emulated` | The framework builds it from lower primitives, usually shell + git. | Use it; expect the manual steps. |
| `adapter` | Provided through a platform-specific translation, not the canonical artifact. | Use the adapter; never hand-edit generated output. |
| `unsupported` | Verified absent **for our artifact on that platform** — see [What a row is about](#what-a-row-is-about). Not a claim about the vendor's product. | Take the `fallback`. |
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

A third invariant is enforced by `minProperties`/`maxProperties`: **every supported
surface must carry a row for every capability key.** Omission is a schema error. You
cannot hide a gap by staying silent about it — you have to write `unknown` and say why.

An unverified surface is not an exception to that rule but the same rule applied one
level up: it carries no capabilities block at all, because it has no measurements to
report. See [`support`, and why an unverified surface is empty](#support-and-why-an-unverified-surface-is-empty).

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
hand. Resolve the platform to a surface first — `compatibility:` is written per platform,
and the rows live on surfaces, so a platform-level answer means its `primary_surface`.
Then take the skill's `capabilities.required` list, read each one's status on that
surface, and reduce:

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

Degradation is written per capability, not per surface. That is what keeps the adapter
count from exploding: a sixth platform — or a third surface on an existing one — adds one
registry entry, not a new branch in every skill.

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

| Surface | Result |
|---|---|
| Claude Code | Everything native. Full run: subagents fix review threads in parallel, `gh` merges. |
| OpenCode | `subagents` is `adapter` (generated `.opencode/agent/`), `github_cli` depends on the host. Runs, sequentially, with `gh` if present. |
| Any surface, `gh` absent | Runs through the diff and review work, then prints the PR body and the exact `gh pr create` command for the user. Reports the degradation. |

## Where capabilities are consumed

- **`scripts/lib/registry.sh`** — flattens the registry to one entry per supported
  surface. Every other consumer below goes through it rather than walking the two levels
  itself.
- **`scripts/doctor.sh`** — reports the capabilities of the detected surface, plus the
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

Promoting a surface from `unverified` to `supported` is a bigger change than editing a
row, because it means writing nineteen of them from scratch plus an install path — that
procedure is [adding a platform](adding-a-platform.md#adding-a-surface-to-an-existing-platform).
Until it is done, the surface keeps its `unverified_reason` and claims nothing.

Moving a row from `unknown` to `native` without running its validation command is the
one change this model exists to prevent. When in doubt, leave it `unknown` — an
understated registry costs a little capability; an overstated one costs user trust.

### Provenance

**Not every row in this registry is equally well established, and a measurement outranks
this registry whenever the two conflict.** That precedence is a project rule, not a
courtesy: it is what corrected `gemini_cli` from nine `native` rows to five.

| Surface | Provenance |
|---|---|
| `gemini_cli` | **Measured.** Gemini CLI 0.55.1 against a probe extension, 2026-08-19. Error text recorded in `docs/user/install/gemini.md`. |
| `opencode` | **Measured.** OpenCode 1.18.11 on the maintainer machine, including the `hooks` and symlink-discovery findings. |
| `claude_code` | Mostly verified through this repo's own validators, which run against it on every change. |
| `codex`, `cursor` | Declaration-backed: derived from `platform-targets.json`, which records its own `verification_method` per target. |
| `claude_desktop` | Largely unmeasured — nine `unknown` rows, and honestly so. Supported all the same: it installs from the Claude Code listing and the rows that are known are known. |

The four `unverified` surfaces — `codex_ide`, `cursor_cli`, `gemini_code_assist`,
`opencode_desktop` — have no provenance because they have no rows. Their
`unverified_reason` is the whole of what is known about them.

The Gemini entry is the cautionary case worth remembering. It was originally written from
REFACTOR-SPEC §13.4, which enumerates what Gemini extensions *can* package, and six
capabilities were marked `native` on that basis. A probe then showed the extension loads
**zero** skills (discovery scans one level; canonical skills are two deep) and rejects
`agents/*.md` outright. The spec was not wrong about Gemini in general; it was wrong about
*this repo on* Gemini, which is the only question the registry asks.

**A note on checking prose against this registry.** Sweeping the repo for documentation
that contradicts a row is worth doing, but it cannot find an error *in* the row — a doc
faithfully restating a wrong note reads as correct, and every doc downstream of it
inherits the error while passing the check. That happened here: an imprecise clause in
the `gemini_cli.hooks` note ("has its own event vocabulary") propagated into two other
files, and the sweep cleared all three. Only re-reading the primary evidence caught it.
When a row's wording is load-bearing, verify it against the source — the shipped bundle,
the CLI, the error text — not against the things that quote it.

**Ask how a claim was measured before building on it — including when it comes from a
teammate.** "Measurements outrank declarations" is not only a rule about rows in this
file; it governs claims arriving in review comments, handoff notes and messages. A
secondhand assertion used as the load-bearing premise of an argument is a declaration
wearing a measurement's clothes, and it does not become evidence by being repeated
confidently by someone closer to the platform. This registry had a row challenged on the
strength of an event list that turned out to be a summarised documentation fetch; the
challenge dissolved the moment someone read the shipped bundle. Ask for the provenance
first. It is one question, and it is cheaper than the correction.

**Re-sweep staged patches, not just shipped prose.** A correction's blast radius is bigger
than the file that carried the original claim, and the most dangerous copies are the ones
not yet applied: a paste-ready patch sitting in a request file, a suggested diff in a
review comment, a snippet in a handoff note. Shipped prose gets re-read by whoever owns
the file; a staged patch gets pasted by someone with no reason to re-derive it, straight
into an artifact its author never touches. Both instances of the stale Gemini hooks
wording that survived the first sweep were of this kind — one in a request file's
paste-ready JSON patch, one in a request item asserting a CHANGELOG section was missing
after it had been added. When you correct a measurement, grep the in-flight work too.

So: a specification, a vendor changelog, or a documentation page is a reason to go and
measure, never a substitute for having measured. When a measurement contradicts a row,
the row is what changes — and its note should carry the observed error text, so the next
maintainer inherits the evidence rather than the conclusion.
