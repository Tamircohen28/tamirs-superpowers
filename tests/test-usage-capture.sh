#!/usr/bin/env bash
# tests/test-usage-capture.sh — collector, enable.sh, and the env-gated hook.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="$ROOT/scripts/usage-capture/collector.py"
ENABLE="$ROOT/scripts/usage-capture/enable.sh"
HOOK="$ROOT/hooks/usage-capture-ensure.sh"
FIXTURES="$ROOT/tests/fixtures/usage-capture"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

TMPROOT="$(mktemp -d)"
trap 'if [[ -n "${COLLECTOR_PID:-}" ]]; then kill "$COLLECTOR_PID" 2>/dev/null || true; fi; rm -rf "$TMPROOT"' EXIT

echo "=== usage-capture ==="

# --- CLI contract -----------------------------------------------------------
if python3 "$COLLECTOR" --help >/dev/null; then
  ok "collector --help exits 0"
else
  bad "collector --help exits 0" "non-zero"
fi

if bash "$ENABLE" --help >/dev/null; then
  ok "enable.sh --help exits 0"
else
  bad "enable.sh --help exits 0" "non-zero"
fi

out="$(python3 "$COLLECTOR" --dry-run --dir "$TMPROOT/usage" --port 17431 --json 2>/dev/null)"
if printf '%s' "$out" | jq -e '.ok == true and .bind == "127.0.0.1" and .dry_run == true' >/dev/null; then
  ok "collector --dry-run prints bind and dir"
else
  bad "collector --dry-run prints bind and dir" "got: ${out:-<empty>}"
fi

if python3 "$COLLECTOR" --bind 0.0.0.0 --dry-run >/dev/null 2>"$TMPROOT/bind.err"; then
  bad "collector refuses non-loopback bind" "exited 0"
else
  if grep -q 'non-loopback' "$TMPROOT/bind.err"; then
    ok "collector refuses non-loopback bind"
  else
    bad "collector refuses non-loopback bind" "stderr: $(cat "$TMPROOT/bind.err")"
  fi
fi

if python3 "$COLLECTOR" --not-a-flag >/dev/null 2>"$TMPROOT/unk.err"; then
  bad "collector unknown flag fails" "exited 0"
else
  ok "collector unknown flag fails"
fi

if bash "$ENABLE" --not-a-flag >/dev/null 2>"$TMPROOT/eunk.err"; then
  bad "enable.sh unknown flag fails" "exited 0"
else
  ok "enable.sh unknown flag fails"
fi

# --- live collector ---------------------------------------------------------
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
LOGDIR="$TMPROOT/usage"
python3 "$COLLECTOR" --dir "$LOGDIR" --port "$PORT" >/dev/null 2>&1 &
COLLECTOR_PID=$!

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if python3 - "$PORT" <<'PY' 2>/dev/null
import socket, sys
port = int(sys.argv[1])
s = socket.create_connection(("127.0.0.1", port), timeout=0.3)
s.sendall(b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
data = s.recv(1024)
sys.exit(0 if b"ok" in data else 1)
PY
  then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" == 1 ]]; then
  ok "collector listens on loopback"
else
  bad "collector listens on loopback" "never became healthy on $PORT"
fi

post() {
  local path="$1" file="$2"
  python3 - "$PORT" "$path" "$file" <<'PY'
import json, sys, urllib.request
port, path, file = sys.argv[1], sys.argv[2], sys.argv[3]
body = open(file, "rb").read()
req = urllib.request.Request(
    "http://127.0.0.1:%s%s" % (port, path),
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=2) as resp:
    print(resp.read().decode())
PY
}

if [[ "$ready" == 1 ]]; then
  resp="$(post /v1/logs "$FIXTURES/otlp-api-request.json" 2>"$TMPROOT/post.err" || true)"
  if printf '%s' "$resp" | jq -e '.ok == true and .written == 1' >/dev/null 2>&1; then
    ok "OTLP logs write one api_request"
  else
    bad "OTLP logs write one api_request" "resp=${resp:-<empty>} err=$(cat "$TMPROOT/post.err")"
  fi

  file="$(find "$LOGDIR" -name '*.jsonl' | head -1)"
  if [[ -n "$file" ]] && jq -e '.event == "api_request" and .model == "claude-sonnet-4-6" and .skill_name == "plan-dev" and .gateway_kind == "litellm" and .endpoint_label == "dev-gateway" and .input_tokens == 800' "$file" >/dev/null && ! grep -q 'https://llm.example.internal' "$file"; then
    ok "JSONL has model, skill, opaque LiteLLM label, tokens"
  else
    bad "JSONL has model, skill, opaque LiteLLM label, tokens" "file=${file:-missing} content=$(cat "$file" 2>/dev/null)"
  fi

  if [[ -n "$file" ]] && grep -q 'SECRET PROMPT TEXT' "$file"; then
    bad "prompt text is not persisted" "found secret in $file"
  else
    ok "prompt text is not persisted"
  fi

  mode="$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$file")"
  if [[ "$mode" == "0o600" ]]; then
    ok "JSONL is mode 600"
  else
    bad "JSONL is mode 600" "got $mode"
  fi

  resp="$(post /v1/traces "$FIXTURES/otlp-llm-span.json" 2>/dev/null || true)"
  if printf '%s' "$resp" | jq -e '.ok == true and .written == 1' >/dev/null 2>&1 \
     && grep -q '"ttft_ms":180' "$file" \
     && grep -q '"event":"llm_request"' "$file" \
     && grep -q '"gateway_deployment":"claude-primary"' "$file" \
     && grep -q '"request_id_hash"' "$file" \
     && ! grep -q '"request_id":"req-99"' "$file"; then
    ok "OTLP traces record TTFT and safe LiteLLM correlation metadata"
  else
    bad "OTLP traces record TTFT and safe LiteLLM correlation metadata" "resp=${resp:-<empty>} $(cat "$file")"
  fi

  ingest="$TMPROOT/ingest.json"
  printf '%s\n' '{"harness":"opencode","event":"api_request","model":"gpt-test","duration_ms":50,"request_bytes":1234}' >"$ingest"
  resp="$(post /ingest "$ingest" 2>/dev/null || true)"
  if printf '%s' "$resp" | jq -e '.ok == true and .written == 1' >/dev/null 2>&1 \
     && grep -q '"harness":"opencode"' "$file" \
     && grep -q '"request_bytes":1234' "$file"; then
    ok "/ingest writes the shared schema"
  else
    bad "/ingest writes the shared schema" "resp=${resp:-<empty>}"
  fi

  invalid_gateway="$TMPROOT/invalid-gateway.json"
  printf '%s\n' '{"harness":"opencode","event":"api_request","gateway_kind":"https://litellm.example","endpoint_label":"https://litellm.example"}' >"$invalid_gateway"
  resp="$(post /ingest "$invalid_gateway" 2>/dev/null || true)"
  if printf '%s' "$resp" | jq -e '.ok == true and .written == 1' >/dev/null 2>&1 \
     && ! grep -q 'https://litellm.example' "$file"; then
    ok "collector drops non-opaque gateway metadata"
  else
    bad "collector drops non-opaque gateway metadata" "resp=${resp:-<empty>}"
  fi
fi

kill "$COLLECTOR_PID" 2>/dev/null || true
wait "$COLLECTOR_PID" 2>/dev/null || true
COLLECTOR_PID=""

# --- Israel date roll -------------------------------------------------------
ROLL="$TMPROOT/roll"
mkdir -p "$ROLL"
TAMIRS_USAGE_CAPTURE_NOW='2026-09-10T23:00:00+03:00' python3 - "$ROLL" "$COLLECTOR" <<'PY'
import importlib.util, sys
d, path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("collector", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.STATE["dir"] = d
mod.STATE["dry_run"] = False
mod.append_jsonl({"harness": "claude_code", "event": "api_request", "model": "a"})
PY
TAMIRS_USAGE_CAPTURE_NOW='2026-09-11T01:00:00+03:00' python3 - "$ROLL" "$COLLECTOR" <<'PY'
import importlib.util, sys
d, path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("collector", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.STATE["dir"] = d
mod.STATE["dry_run"] = False
mod.append_jsonl({"harness": "claude_code", "event": "api_request", "model": "b"})
PY
if [[ -f "$ROLL/2026-09-10.jsonl" && -f "$ROLL/2026-09-11.jsonl" ]]; then
  ok "Israel calendar day rolls the JSONL file"
else
  bad "Israel calendar day rolls the JSONL file" "files: $(ls "$ROLL")"
fi

# --- enable.sh dry-run (HOME sandbox) ---------------------------------------
export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"
out="$(bash "$ENABLE" --dry-run --json --dir "$LOGDIR" --port 17431 --gateway-kind litellm --endpoint-label dev-gateway 2>/dev/null || true)"
if printf '%s' "$out" | jq -e '.ok == true and .dry_run == true and .env.TAMIRS_USAGE_CAPTURE == "1" and (.env.OTEL_RESOURCE_ATTRIBUTES | contains("tamirs.gateway_kind=litellm"))' >/dev/null 2>&1 \
   && [[ ! -f "$HOME/.claude/settings.json" ]]; then
  ok "enable.sh --dry-run does not write settings"
else
  bad "enable.sh --dry-run does not write settings" "got: ${out:-<empty>}"
fi

if bash "$ENABLE" --dry-run --endpoint-label 'https://litellm.example' >/dev/null 2>"$TMPROOT/label.err"; then
  bad "enable.sh refuses a gateway URL as a label" "exited 0"
else
  ok "enable.sh refuses a gateway URL as a label"
fi

out="$(bash "$ENABLE" --json --dir "$LOGDIR" --port "$PORT" 2>/dev/null || true)"
if [[ -f "$HOME/.claude/settings.json" ]] \
   && jq -e '.env.OTEL_EXPORTER_OTLP_PROTOCOL == "http/json" and .env.OTEL_LOG_TOOL_DETAILS == "1" and (.env | has("OTEL_LOG_USER_PROMPTS") | not)' "$HOME/.claude/settings.json" >/dev/null; then
  ok "enable.sh writes Claude OTEL env (prompts off)"
else
  bad "enable.sh writes Claude OTEL env (prompts off)" "settings=$(cat "$HOME/.claude/settings.json" 2>/dev/null) out=$out"
fi
python3 "$COLLECTOR" --dir "$LOGDIR" --port "$PORT" --stop >/dev/null 2>&1 || true

# --- hook is silent when unset ----------------------------------------------
unset TAMIRS_USAGE_CAPTURE TAMIRS_USAGE_CAPTURE_DIR TAMIRS_USAGE_CAPTURE_PORT 2>/dev/null || true
"$HOOK" </dev/null >"$TMPROOT/hook.out" 2>"$TMPROOT/hook.err"
rc=$?
if [[ "$rc" -eq 0 && ! -s "$TMPROOT/hook.out" ]]; then
  ok "hook no-ops with empty stdout when unset"
else
  bad "hook no-ops with empty stdout when unset" "rc=$rc out=$(cat "$TMPROOT/hook.out") err=$(cat "$TMPROOT/hook.err")"
fi

echo
printf 'usage-capture: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
