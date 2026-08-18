# Provider selection

**A role is not a provider.** "Reviewer" is a job; "Codex" is a harness that can do it.
This file defines how a role gets resolved to a provider at runtime, and it exists to
prevent the single most expensive mistake this framework could make: hardcoding
"Claude implements, Codex reviews" and thereby requiring every user to hold two AI
subscriptions.

> **The framework never requires more than one AI provider.**
> If exactly one harness is available — the one you are already running in — every role
> resolves to it. Multi-provider routing is an optional optimisation for people who
> happen to have several CLIs installed, never a prerequisite for any skill.

---

## Roles

`planner`, `orchestrator`, `implementer`, `test-engineer`, `reviewer`,
`security-reviewer`, `performance-reviewer`, `debugger`, `integrator`, `research-agent`.

## Providers

`claude`, `codex`, `cursor`, `gemini`, `opencode`, plus the pseudo-provider `current`,
which means "the harness this session is already running in".

---

## Resolution order

A role resolves to exactly one provider by walking these five steps in order and taking
the first that yields a candidate. Each step narrows; none of them is allowed to produce
an empty result without falling through to the next.

### 1. Required capabilities (hard filter)

Start from the full provider list and drop every provider whose registry entry in
[`core/capabilities/platforms.json`](../capabilities/platforms.json) does not satisfy the
role's required capabilities. A capability counts as satisfied when its status is
`native`, `native-experimental`, `partial`, `emulated`, or `adapter`; it does **not**
count when the status is `unsupported` or `unknown`. `unknown` is treated as absent on
purpose — an unverified capability is not a capability.

This step is a filter, not a preference. If it empties the list, the role cannot be
delegated at all and must run inline in the current session with its scope narrowed;
see [Degradation](#degradation).

### 2. User preference (explicit wins)

If the user named a provider for this role — in the request, in project config, or in
the invocation — use it, provided it survived step 1. If the user's choice was filtered
out in step 1, say so explicitly and name the missing capability. Do not silently
substitute a different provider for one the user asked for by name.

### 3. Available harnesses (reality filter)

Drop every provider whose CLI is not actually installed and usable, using the
`validation.command` recorded for that platform in the registry. `current` is always
available by definition.

**If exactly one provider survives, it takes every role and resolution stops here.**
This is the normal, single-subscription case.

### 4. Configured role preferences (ordered lists)

Walk the user's configured preference list for this role and take the first entry that
survived steps 1 and 3.

### 5. Fallback

Use the configured `providers.default`. Its own default is `current`, so the terminal
state of this algorithm is always "do it here, yourself".

---

## Config shape

Lives in the repo's project config (or the user's global equivalent). Every field is
optional; an absent config resolves every role to `current`.

```yaml
providers:
  # Terminal fallback. `current` = the harness this session is running in.
  default: current

  # Optional hard requirement per role. Capability keys come from the registry.
  # A role with no entry here requires nothing beyond `skills`.
  requires:
    implementer: [skills, shell, git]
    test-engineer: [skills, shell]
    reviewer: [skills]
    integrator: [skills, shell, git, github_cli]
    orchestrator: [skills, subagents]

  # Ordered preference per role, consulted only after the capability and
  # availability filters. Unlisted roles fall through to `default`.
  roles:
    planner: [claude, codex, cursor, gemini, opencode]
    orchestrator: [current]
    implementer: [current]
    test-engineer: [current]
    reviewer: [codex, claude, cursor, gemini]
    security-reviewer: [codex, claude]
    performance-reviewer: [claude, codex]
    debugger: [current]
    integrator: [current]
    research-agent: [claude, gemini, codex]

  # Optional. When true, a role whose preferred provider is unavailable reports the
  # substitution instead of switching silently. Defaults to true.
  announce_substitutions: true
```

### Reading the example

`reviewer: [codex, claude, cursor, gemini]` does **not** mean "reviews happen in Codex".
It means: *if* several harnesses are installed, prefer Codex for review because a second
model reviewing the first model's work catches more. With only Claude installed, the
list collapses to Claude and nothing is lost but the cross-model diversity.

`implementer: [current]` is deliberate. Implementation happens where the user is, in the
session they are watching, against the working tree they own.

---

## Degradation

| Situation | Behaviour |
|---|---|
| One harness available | Every role uses it. No warning — this is the supported default. |
| Preferred provider missing a required capability | Fall to the next entry; announce the substitution and name the capability. |
| User named a provider that fails the capability filter | Stop and say which capability is missing. Do not substitute silently. |
| No provider satisfies the requirements | Run the role inline in the current session, sequentially, with a narrowed scope. Report the degradation. |
| Capability status is `unknown` | Treated as unavailable. Never advertise an unverified capability as working. |

## Invariants

1. No skill hardcodes a provider name. Skills request a **role**; resolution happens here.
2. No skill fails because a second provider is absent.
3. Cross-provider routing is opt-in configuration, never a default requirement.
4. Every routing decision is explainable: which step selected the provider, and why the
   others were dropped.
5. The framework is standalone — provider selection depends on the capability registry
   and the user's own config, and on nothing outside this repository.
