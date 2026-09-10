---
name: usage-capture
description: >-
  Use when the user wants to record local Claude Code or OpenCode LLM request
  metrics, enable usage capture, inspect daily JSONL usage logs, turn on API
  body sidecars, or find latency bottlenecks from live requests. Triggers:
  'usage capture', 'enable usage capture', 'local usage log', 'record LLM
  requests', 'LLM latency', 'which model was used', 'request duration',
  'usage metrics'. Writes nothing off-machine. Complements session-report
  (historical Claude transcripts) rather than replacing it.
when_to_use: >-
  User wants to enable, disable, or query the local usage-capture recorder —
  'record my LLM requests', 'usage capture', 'which model and how long did
  that take', 'local usage logs', 'enable OTEL usage capture', 'OpenCode
  request metrics'. Claude Code is supported via native OTEL; OpenCode is
  partial (optional plugin). Elsewhere, say unsupported.
argument-hint: '[enable | disable | status | query | bodies]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Bash
  - Read
disallowed-tools: []
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
compatibility:
  claude-code: supported
  claude-desktop: partial
  codex: unsupported
  cursor: unsupported
  gemini: unsupported
  opencode: partial
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: none
    validation-tier: 1
    updated-date: '2026-09-10'
    capabilities:
      required:
        - shell
      optional:
        - hooks
    tags:
      - analytics
      - telemetry
      - usage
      - latency
      - opentelemetry
      - local-only
  capability: toolkit
  updated-date: '2026-09-10'
---

# Usage Capture

Opt-in, **local-only** recorder for per-request LLM metrics. One JSONL file per
Asia/Jerusalem calendar day under `~/.local/share/tamirs-superpowers/usage/`.
Nothing is sent to a collector in the cloud, to GitHub, or to Anthropic beyond
the LLM call the user already configured.

Claude Code is captured through its native OpenTelemetry export (including a
custom `ANTHROPIC_BASE_URL`). LiteLLM is supported as an explicitly labelled gateway;
its URL and raw request IDs are never persisted. OpenCode is captured by an optional JS plugin that
is **not** on by default. Cursor, Codex, and Gemini CLI are out of scope.

This is not `/session-report`. That skill post-parses Claude Code transcripts
under `~/.claude/projects` for token/cache rollups. This skill records live
request timing, model, endpoint, and skill/command inventory. Point at
`session-report` when the user wants historical Claude transcript spend.

## Compatibility

| Target | Status | Why |
|---|---|---|
| Claude Code | supported | Native OTEL logs + traces → local collector |
| Claude Desktop | partial | Same settings file *may* apply; not verified here — check for JSONL before claiming it works |
| OpenCode CLI | partial | Optional `opencode-plugin.mjs`; not loaded by this repo's `opencode.json`; live 1.18.x fire was not recorded in this change |
| Codex, Cursor, Gemini CLI | unsupported | No capture path shipped |

**Before enabling**, confirm `shell` is available. The `hooks` capability is
optional: without it, start the collector with `collector.py --daemon` yourself
instead of relying on SessionStart.

## Privacy default

Metadata only: model, Israel timestamps, duration / TTFT, tokens, skill and
command **names**, session id, custom-endpoint label. **No prompt text and no
API JSON** unless the user passes `--bodies`. Bodies are secret-bearing
(conversation history, tool results, code). Say so before turning them on.

## Workflow

### 0. Resolve the plugin / repo root

Try in order: `$CLAUDE_PLUGIN_ROOT`, `$CLAUDE_SKILL_DIR/../../../..` (skill is
`skills/toolkit/usage-capture`), then the current git toplevel. The collector
lives at `scripts/usage-capture/collector.py` and the enabler at
`scripts/usage-capture/enable.sh`.

### 1. Enable (Claude Code)

```bash
bash scripts/usage-capture/enable.sh
```

Useful flags: `--dry-run --json`, `--bodies`, `--disable`, `--dir DIR`, `--port PORT`.
For LiteLLM use `--gateway-kind litellm --endpoint-label <opaque-label>`; do not put a
gateway URL in the label. The client collector sees end-to-end latency, not LiteLLM's
internal retries/fallbacks or backend timing.

Then **restart Claude Code** so `~/.claude/settings.json` `env` is picked up.
Expect `TAMIRS_USAGE_CAPTURE=1` plus OTEL pointing at `http://127.0.0.1:17431`
with `http/json`. `OTEL_LOG_USER_PROMPTS` stays unset. `OTEL_LOG_TOOL_DETAILS=1`
so skill/command names appear.

If `OTEL_EXPORTER_OTLP_ENDPOINT` is already set to something else, the script
refuses unless `--force`.

### 2. Enable (OpenCode) — optional plugin

Do **not** add the plugin to this repo's `opencode.json`. In the user's
`~/.config/opencode/opencode.json` (or project config), add an absolute path:

```json
{
  "plugin": ["/absolute/path/to/tamirs-superpowers/skills/toolkit/usage-capture/opencode-plugin.mjs"]
}
```

Start the collector the same way (`collector.py --daemon`, or the Claude enable
script). Restart OpenCode. Mark this row `partial` in any report: types exist;
a live 1.18.x verification has not been filed.

Bodies: `TAMIRS_USAGE_CAPTURE_BODIES=1`.

### 3. Confirm it is up

```bash
python3 scripts/usage-capture/collector.py --status --json
```

After a Claude turn, a file named `YYYY-MM-DD.jsonl` (Israel date) should appear
in the log directory. Mode `0700` on the directory, `0600` on files.

### 4. Query a day

Do not invent numbers. If the file is missing, say capture is not running or no
requests landed yet — not "zero usage".

p95 duration by model:

```bash
jq -s 'map(select(.event=="api_request" and .duration_ms!=null))
  | group_by(.model)
  | map({model: .[0].model, n: length, p95: (sort_by(.duration_ms) | .[(length*0.95|floor)].duration_ms)})' \
  ~/.local/share/tamirs-superpowers/usage/$(TZ=Asia/Jerusalem date +%Y-%m-%d).jsonl
```

Top skills by input tokens:

```bash
jq -s 'map(select(.skill_name and .input_tokens))
  | group_by(.skill_name)
  | map({skill: .[0].skill_name, input_tokens: (map(.input_tokens)|add)})
  | sort_by(-.input_tokens)' \
  ~/.local/share/tamirs-superpowers/usage/$(TZ=Asia/Jerusalem date +%Y-%m-%d).jsonl
```

Slowest custom-endpoint calls:

```bash
jq -s 'map(select(.event=="api_request")) | sort_by(-.duration_ms) | .[:10]
  | map({ts, model, endpoint, duration_ms, ttft_ms, skill_name})' \
  ~/.local/share/tamirs-superpowers/usage/$(TZ=Asia/Jerusalem date +%Y-%m-%d).jsonl
```

### 5. Disable

```bash
bash scripts/usage-capture/enable.sh --disable
```

Restart Claude Code. Remove the OpenCode `plugin` path if it was added. Logs on
disk are left in place — ask before deleting.

## JSONL fields (omit rather than invent)

`ts`, `harness` (`claude_code` \| `opencode`), `event` (`api_request` \|
`api_error` \| `user_prompt` \| `skill_activated` \| `tool_result` \|
`session_start` \| `llm_request`), `session_id`, `prompt_id`, `request_id`,
`model`, `query_source`, `duration_ms`, `ttft_ms`, token fields,
`request_bytes`, `skill_name`, `command_name`, `plugin_name`, `agent_name`,
`mcp_server`, `mcp_tool`, `endpoint`, `success`, `status_code`, `stop_reason`,
`cost_usd`, `body_ref` (only with `--bodies`).

## Fallback when `hooks` is missing

`usage-capture-ensure.sh` is env-gated SessionStart. On a surface without that
event, run `python3 scripts/usage-capture/collector.py --daemon` yourself. The
skill still enables Claude settings and still documents the OpenCode plugin.

## Do not

- Merge this into `session-report` or parse `~/.claude/projects` here.
- Claim OpenCode `supported` until a live fire is recorded.
- Enable managed/org OTEL settings in v1.
- Bind the collector anywhere but `127.0.0.1`.
