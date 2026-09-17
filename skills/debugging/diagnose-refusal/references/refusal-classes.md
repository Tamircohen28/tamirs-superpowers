# Refusal classification taxonomy

Use these class ids verbatim in `report.md` and the completion reply.

| Id | Meaning |
|----|---------|
| `HARNESS_POLICY` | Coding-agent harness refused before contacting the provider. |
| `PROJECT_INSTRUCTION` | `CLAUDE.md`, `AGENTS.md`, skill instructions, or repo config appears responsible. |
| `LITELLM_GUARDRAIL` | A LiteLLM (or other proxy) guardrail / moderation / callback appears responsible. |
| `LITELLM_ROUTING` | Request may have been routed to a different deployment / provider / model than expected. |
| `PROVIDER_FILTER` | Upstream inference provider rejected or transformed the request. |
| `MODEL_REFUSAL` | Provider returned a successful generation; the model itself produced refusal language. |
| `TOOL_PERMISSION` | Model wanted to continue but a tool / permission boundary prevented execution. |
| `CONTEXT_CONTAMINATION` | Earlier conversation state or instructions appear to influence the current response. |
| `UNKNOWN` | Not enough evidence. |

## Confidence rules

- **HIGH** — direct evidence (HTTP status before generation, explicit guardrail log line, harness block message, visible permission denial).
- **MEDIUM** — strong circumstantial evidence (route mismatch + refusal shape, skill text matching refusal phrasing).
- **LOW** — plausible but unverified.

Never infer HIGH without direct evidence.

## Differentiating signals

| Signal | Tips toward |
|--------|-------------|
| Error before any assistant token / tool call | `HARNESS_POLICY`, `LITELLM_GUARDRAIL`, `PROVIDER_FILTER`, `LITELLM_ROUTING` |
| HTTP 401 / 403 / 429 with provider request id | `PROVIDER_FILTER` or proxy auth — not `MODEL_REFUSAL` |
| Normal 200 stream that then says "I can't help with that" | `MODEL_REFUSAL` (or `CONTEXT_CONTAMINATION` / `PROJECT_INSTRUCTION`) |
| Tool call attempted, permission denied | `TOOL_PERMISSION` |
| Model name in response ≠ model name configured | `LITELLM_ROUTING` |
| Refusal quotes wording from `AGENTS.md` / a skill | `PROJECT_INSTRUCTION` |

## Multi-class

Select every class that has evidence. Order by confidence descending. The
"most likely refusal layer" in the final assessment is the highest-confidence
class (ties → earlier in the table above).
