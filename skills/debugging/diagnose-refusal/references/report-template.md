# report.md template

Put the assessment block at the **top**. Fill every `(pending)` before finishing.

~~~markdown
# Refusal diagnostic report

Most likely refusal layer: PROVIDER_FILTER
Confidence: HIGH
Primary evidence: HTTP 403 returned before assistant generation; provider request id present.
Second-most likely layer: LITELLM_GUARDRAIL
Missing evidence needed:
- LiteLLM callback log for this request id
- Confirmation of api_base host

---

## 1. Incident

- date/time (UTC):
- active model:
- provider/backend:
- harness + version:
- preceding user request:
- complete refusal response (redacted):
- before/after tool call:
- HTTP/API error visible:
- status / error / request IDs:

## 2. Conversation state

…

## 3. Active repository instructions

…

## 4. LiteLLM / proxy

…

## 5. Environment

See `environment.md`.

## 6. Refusal classification

### PROVIDER_FILTER
Evidence:
Confidence: HIGH

### LITELLM_GUARDRAIL
Evidence:
Confidence: LOW

## 7. Request-path reconstruction

User                         CONFIRMED
 ↓
Slash command / skill        CONFIRMED
 ↓
Agent/harness                CONFIRMED
 ↓
Project/system instructions  INFERRED
 ↓
LiteLLM                      CONFIRMED
 ↓
Selected provider            CONFIRMED
 ↓
Model                        CONFIRMED

Refusal most likely originated at: **Selected provider** (`PROVIDER_FILTER`).

## 8. Comparison tests

- TEST A: …
- TEST B: …
- TEST C: …
- TEST D: …

(Do not execute the original refused task.)

## 9. Final assessment

Concrete next debugging actions:
1. …
2. …
~~~

## Example completion reply

```text
Diagnostic bundle created at .refusal-debug/

Most likely refusal layer: PROVIDER_FILTER
Confidence: HIGH

Upload .refusal-debug/report.md here for deeper analysis.
```
