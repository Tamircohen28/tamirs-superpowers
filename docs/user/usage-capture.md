# Local usage capture

Opt-in recorder for per-request LLM metrics on **this machine**. One JSONL file per
Asia/Jerusalem calendar day under `~/.local/share/tamirs-superpowers/usage/`. Nothing is
exported to a cloud collector.

Default: model, timestamps, duration / time-to-first-token, tokens, skill and command
**names**, session id, an opaque endpoint label, LiteLLM deployment metadata when emitted,
and an HMAC-hashed request correlation ID. Prompt text and API bodies are
off unless you pass `--bodies` (those files contain conversation history and often secrets).

This is not [`session-report`](skills.md): that skill reads Claude Code transcripts after
the fact. Usage capture records live request timing, including a custom
`ANTHROPIC_BASE_URL`.

## LiteLLM gateway

Use an opaque label — never the LiteLLM URL — when the harness routes through LiteLLM:

```bash
bash scripts/usage-capture/enable.sh --gateway-kind litellm --endpoint-label corp-gateway
```

The log records the gateway kind, label, requested model, returned deployment metadata when
available, and a local HMAC of a request ID. LiteLLM's internal retries, fallback decisions,
queue time, and provider latency are not visible to this client collector; inspect LiteLLM's
own local access logs to add those later.

For Claude Code, verify that your LiteLLM deployment accepts the Anthropic Messages route
used by `ANTHROPIC_BASE_URL`. OpenCode uses LiteLLM's OpenAI-compatible base URL. The
recorder does not translate either protocol.

Operator surface: the `/usage-capture` skill.

## Claude Code

```bash
bash scripts/usage-capture/enable.sh          # metadata only
bash scripts/usage-capture/enable.sh --bodies # also write API JSON under usage/bodies/
bash scripts/usage-capture/enable.sh --disable
python3 scripts/usage-capture/collector.py --status --json
```

Restart Claude Code after enable/disable so `~/.claude/settings.json` `env` is picked up.
The SessionStart hook starts the collector only when `TAMIRS_USAGE_CAPTURE=1`.

## OpenCode CLI

Lifecycle guards still do not run. For metrics, add an **absolute** path to
`skills/toolkit/usage-capture/opencode-plugin.mjs` in *your* OpenCode `plugin` list — not
in this repo's `opencode.json`. Start the same collector, then restart OpenCode. This path
is documented as **partial** until a live 1.18.x fire is recorded.

For LiteLLM metadata in OpenCode, export the same opaque labels before starting it:

```bash
export TAMIRS_USAGE_CAPTURE_GATEWAY_KIND=litellm
export TAMIRS_USAGE_CAPTURE_ENDPOINT_LABEL=corp-gateway
```

## Query

```bash
jq -s 'map(select(.event=="api_request")) | sort_by(-.duration_ms) | .[:10]' \
  ~/.local/share/tamirs-superpowers/usage/$(TZ=Asia/Jerusalem date +%Y-%m-%d).jsonl
```
