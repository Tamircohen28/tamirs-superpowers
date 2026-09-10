---
name: diagnose-refusal
description: 'Use when a coding-agent session refused, blocked, filtered, or returned HTTP 403/401/429 before or instead of doing the asked work, and the user needs to know WHICH LAYER refused — harness policy, project instructions, LiteLLM guardrail/routing, upstream provider filter, model refusal, tool permission, or context contamination. Triggers: ''diagnose refusal'', ''/diagnose-refusal'', ''why did it refuse'', ''where did the refusal come from'', ''GLM refused'', ''LiteLLM blocked'', ''provider filter'', ''model refused'', ''HTTP 403 from the model'', ''safety refusal'', ''cannot tell if this is the model or the proxy''. Prefer this over retrying the refused task or asking the stuck model to continue: it switches entirely to benign diagnostics and writes a sanitized .refusal-debug/ bundle.'
when_to_use: 'A model/session refused or blocked a request and the user wants the refusal origin isolated across harness → project instructions → LiteLLM → provider → model. Key phrases: diagnose refusal, why did it refuse, LiteLLM blocked, provider filter, GLM refused, HTTP 403, safety refusal. Do not use for ordinary stack-trace bugs (use targeted-debug) or for asking the model to continue the refused task.'
argument-hint: '[notes about the refusal — model name, proxy, skill that triggered it]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Read
- Grep
- Glob
- Bash
- Write
disallowed-tools: []
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: debugging
    role: debugger
    validation-tier: 1
    updated-date: '2026-09-10'
    capabilities:
      required:
        - skills
        - shell
      optional:
        - git
        - mcp
    tags:
      - debugging
      - refusal
      - litellm
      - provider
      - guardrail
      - diagnostics
      - routing
  capability: refusal-diagnostics
  updated-date: '2026-09-10'
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "repo: $(basename $(git rev-parse --show-toplevel))" || echo "not a git repo"`
!`date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null | sed 's/^/utc: /' || true`

> The `!`-prefixed lines above are Claude Code dynamic frontmatter. Other harnesses
> treat them as literal text and lose nothing — every step below re-derives what it
> needs with ordinary shell commands.

# Diagnose Refusal

**Diagnostics only.** Isolate *where* a refusal originated in the request path. Do not
retry, reinterpret, weaken, jailbreak, or continue the refused task.

## Hard invariants

1. Do **not** retry the refused operation.
2. Do **not** bypass, weaken, reinterpret, jailbreak, or circumvent any safety policy.
3. Do **not** continue the task that triggered the refusal.
4. Do **not** invent invisible instructions — write `Not visible from this session.`
5. Do **not** expose hidden reasoning or private chain-of-thought.
6. Do **not** copy credential files (`.env`, `.env.*`, `credentials.json`, `*.pem`, `*.key`).
7. Do **not** modify application source or configuration.
8. Redact secrets: replace API keys, tokens, cookies, passwords, Authorization headers,
   and private keys with `***REDACTED***`. For env vars, record **names and SET/UNSET
   only** — never values.

If the current model is itself refusing, this skill still does not ask it to continue —
it switches the job entirely to benign inspection of config, routing, and the refusal text.

## Why this skill exists

A refusal sentence alone is almost useless. The same surface text can come from the
harness, a project skill, a LiteLLM guardrail, a mis-route, an upstream provider filter,
or the model. Differential diagnosis needs a sanitized bundle and a reconstructed path.

## Bundle layout (v2)

Create or replace under the repo root (or cwd if not a git repo):

```text
.refusal-debug/
├── report.md          # full diagnosis (sections 1–9)
├── request.json       # sanitized request metadata if available; else {"status":"unavailable"}
├── response.json      # sanitized response/error metadata if available; else {"status":"unavailable"}
├── routing.md         # HARNESS → LITELLM → PROVIDER → MODEL
├── environment.md     # safe env / tool versions
└── manifest.txt       # list of files created
```

Initialize with the bundled script, then fill the files:

```bash
bash skills/debugging/diagnose-refusal/scripts/init-bundle.sh
bash skills/debugging/diagnose-refusal/scripts/collect-environment.sh > .refusal-debug/environment.md
```

Resolve the skill directory from whatever path the harness loaded (plugin root,
checkout, or symlink). Prefer `git rev-parse --show-toplevel` then
`skills/debugging/diagnose-refusal/scripts/…`.

After writing any file that may contain pasted error bodies, run:

```bash
python3 skills/debugging/diagnose-refusal/scripts/redact-secrets.py .refusal-debug/report.md
python3 skills/debugging/diagnose-refusal/scripts/redact-secrets.py .refusal-debug/request.json
python3 skills/debugging/diagnose-refusal/scripts/redact-secrets.py .refusal-debug/response.json
```

Classification taxonomy: [references/refusal-classes.md](references/refusal-classes.md).
Report skeleton: [references/report-template.md](references/report-template.md).

## Workflow

Copy and track:

```text
Diagnose-refusal progress:
- [ ] 0. Init bundle + hard-invariant stance
- [ ] 1. Incident capture
- [ ] 2. Conversation state
- [ ] 3. Active repository instructions
- [ ] 4. LiteLLM / proxy path
- [ ] 5. Environment (script)
- [ ] 6. Refusal classification
- [ ] 7. Request-path reconstruction → routing.md
- [ ] 8. Comparison tests (propose only — do not execute refused task)
- [ ] 9. Final assessment (top of report.md)
- [ ] 10. Bundle manifest + completion reply
```

### 0. Init

```bash
bash skills/debugging/diagnose-refusal/scripts/init-bundle.sh
```

Incorporate any user notes from `$ARGUMENTS` / the slash-command argument into section 1.

### 1. Incident → `report.md`

Record:

- current date/time (UTC)
- active model name if visible
- provider/backend if visible
- agent/harness name and version if available
- the user's immediately preceding request that resulted in refusal
- the complete refusal response (redacted)
- whether the refusal appeared before or after any tool call
- whether an HTTP/API error was visible
- status / error / request IDs if available

Populate `request.json` / `response.json` when structured metadata exists (status code,
request id, model id, error type). Otherwise write `{"status":"unavailable","reason":"…"}`.

### 2. Conversation state

Summarize the relevant conversation immediately before the refusal. Include the exact
relevant user message where possible.

Identify relevant:

- system/project instructions visible to you
- `AGENTS.md` / `CLAUDE.md` instructions
- activated skills
- slash commands
- MCP tools
- tool permissions
- model overrides
- agent overrides

### 3. Active repository instructions

Look for and inspect, if they exist:

- `AGENTS.md`, `CLAUDE.md`
- `.claude/`, `.opencode/`, `.agents/`, `.cursor/`
- `skills/`, `SKILL.md`
- `MANTIS.md`, `mantis/`
- `opencode.json`, `opencode.jsonc`
- `litellm_config.yaml`, `config.yaml`, `config.yaml.example`

Record only configuration relevant to models, providers, routing, system prompts,
security rules, guardrails, moderation, permissions, skills, callbacks, fallbacks.
**REDACT secrets.**

### 4. LiteLLM / proxy

Determine whether LiteLLM (or another proxy) appears in the request path.

If yes, inspect accessible local configuration for:

- `model_list` / `model_name` / `litellm_params.model`
- `api_base` / `custom_llm_provider`
- `router_settings` / `fallbacks` / `context_window_fallbacks`
- `callbacks` / `guardrails` / moderation configuration

Write the probable route into `routing.md`:

```text
HARNESS → LITELLM → PROVIDER → MODEL
```

Mark each layer `CONFIRMED` / `INFERRED` / `UNKNOWN`. Do not make network requests
merely to discover secrets or credentials.

### 5. Environment

```bash
bash skills/debugging/diagnose-refusal/scripts/collect-environment.sh > .refusal-debug/environment.md
```

The script records tool versions and **env var names** (SET/UNSET) for LiteLLM / GLM /
ZAI / OpenRouter / Anthropic / OpenAI / MODEL / PROVIDER / API_BASE families only.

### 6. Refusal classification

Classify into one or more classes from
[references/refusal-classes.md](references/refusal-classes.md)
(`HARNESS_POLICY` … `UNKNOWN`). For every selected class:

```text
Evidence:
Confidence: LOW | MEDIUM | HIGH
```

Do not claim HIGH without direct evidence.

### 7. Request-path reconstruction

In both `report.md` and `routing.md`, produce:

```text
User
 ↓
Slash command / skill
 ↓
Agent/harness
 ↓
Project/system instructions
 ↓
LiteLLM (or other proxy)
 ↓
Selected provider
 ↓
Model
```

Annotate where the refusal most likely originated.

### 8. Comparison tests (propose only)

Do **NOT** execute the original refused task.

Propose the minimum safe diagnostic comparison tests:

| Test | Purpose |
|------|---------|
| A | Same harmless prompt through current harness |
| B | Same harmless prompt directly through LiteLLM / proxy |
| C | Same harmless prompt directly through the underlying provider (legitimate configured endpoint only) |
| D | A clearly authorized benign code-security review against a local toy fixture |

Goal: differential diagnosis, not bypassing safeguards.

### 9. Final assessment

Put this block at the **top** of `report.md`:

```text
Most likely refusal layer: <CLASS>
Confidence: <LOW|MEDIUM|HIGH>
Primary evidence: <one or two lines>
Second-most likely layer: <CLASS or none>
Missing evidence needed: <bullet list>
```

Then list concrete next debugging actions.

### 10. Manifest and completion reply

```bash
# refresh file list
find .refusal-debug -type f | sort > .refusal-debug/manifest.txt
python3 skills/debugging/diagnose-refusal/scripts/redact-secrets.py --all .refusal-debug
```

Respond **only** with:

```text
Diagnostic bundle created at .refusal-debug/

Most likely refusal layer: <layer>
Confidence: <LOW|MEDIUM|HIGH>

Upload .refusal-debug/report.md here for deeper analysis.
```

## Degrades

| Missing capability | Behavior |
|--------------------|----------|
| `git` unavailable | Use cwd as root; say so in `environment.md` |
| No LiteLLM config on disk | Mark LiteLLM `UNKNOWN`; still classify from HTTP/error evidence |
| No structured request/response | Write `unavailable` JSON stubs; continue |
| MCP absent | Skip MCP inventory; note `Not visible from this session.` |

## Anti-patterns

- Asking the stuck model "are you sure you can't continue?"
- Re-issuing the refused prompt under a "for educational purposes" wrapper
- Copying `.env` into the bundle
- Claiming HIGH confidence from vibe alone
- Silent retries of the refused tool call
