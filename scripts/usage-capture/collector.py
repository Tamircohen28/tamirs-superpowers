#!/usr/bin/env python3
"""Local-only usage-capture collector.

Writes one JSONL file per Asia/Jerusalem calendar day under
~/.local/share/tamirs-superpowers/usage/. Accepts Claude Code OTLP/HTTP JSON
at /v1/logs and /v1/traces, and a harness-neutral POST /ingest. Binds 127.0.0.1
only. Never forwards telemetry off-machine.

Usage:
  python3 scripts/usage-capture/collector.py --help
  python3 scripts/usage-capture/collector.py --dir /tmp/usage --port 17431
  python3 scripts/usage-capture/collector.py --daemon
  python3 scripts/usage-capture/collector.py --status --json
  python3 scripts/usage-capture/collector.py --stop
  python3 scripts/usage-capture/collector.py --dry-run --verbose

Example:
  python3 scripts/usage-capture/collector.py --dir "$HOME/.local/share/tamirs-superpowers/usage" --port 17431 --daemon
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import signal
import socket
import sys
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse

try:
    from zoneinfo import ZoneInfo

    ISRAEL_TZ = ZoneInfo("Asia/Jerusalem")
except Exception:  # pragma: no cover - zoneinfo missing on ancient Python
    ISRAEL_TZ = timezone(timedelta(hours=3), name="IST")

DEFAULT_PORT = 17431
DEFAULT_DIR = os.path.expanduser("~/.local/share/tamirs-superpowers/usage")
LOOPBACK = "127.0.0.1"
MAX_BODY = 32 * 1024 * 1024
PID_NAME = "collector.pid"

# Fields persisted on a JSONL line. Unknown keys are dropped; empty values omitted.
KEEP = (
    "ts",
    "harness",
    "event",
    "session_id",
    "prompt_id",
    "request_id_hash",
    "model",
    "query_source",
    "duration_ms",
    "ttft_ms",
    "input_tokens",
    "output_tokens",
    "cache_read_tokens",
    "cache_creation_tokens",
    "request_bytes",
    "skill_name",
    "command_name",
    "plugin_name",
    "agent_name",
    "mcp_server",
    "mcp_tool",
    "tool_name",
    "gateway_kind",
    "endpoint_label",
    "gateway_deployment",
    "response_model",
    "gateway_retry_count",
    "success",
    "status_code",
    "stop_reason",
    "cost_usd",
    "body_ref",
    "body_length",
)

# Content-bearing OTEL attributes that must never land in the daily log.
DROP_ATTRS = {
    "prompt",
    "response",
    "body",
    "tool_input",
    "tool_parameters",
    "tool_output",
    "user.email",
    "user_prompt",
    "system_prompt",
    "system_prompt_preview",
    "new_context",
    "response.model_output",
    "tamirs.endpoint",
    "endpoint",
    "http.url",
    "url.full",
}

EVENT_MAP = {
    "api_request": "api_request",
    "claude_code.api_request": "api_request",
    "api_error": "api_error",
    "claude_code.api_error": "api_error",
    "user_prompt": "user_prompt",
    "claude_code.user_prompt": "user_prompt",
    "skill_activated": "skill_activated",
    "claude_code.skill_activated": "skill_activated",
    "tool_result": "tool_result",
    "claude_code.tool_result": "tool_result",
    "api_request_body": "api_request",
    "claude_code.api_request_body": "api_request",
    "api_response_body": "api_request",
    "claude_code.api_response_body": "api_request",
    "session_start": "session_start",
    "llm_request": "llm_request",
    "claude_code.llm_request": "llm_request",
}

ATTR_RENAME = {
    "session.id": "session_id",
    "prompt.id": "prompt_id",
    "event.name": "event",
    "skill.name": "skill_name",
    "plugin.name": "plugin_name",
    "agent.name": "agent_name",
    "mcp_server.name": "mcp_server",
    "mcp_tool.name": "mcp_tool",
    "gen_ai.request.model": "model",
    "gen_ai.response.model": "response_model",
    "litellm.deployment": "gateway_deployment",
    "litellm.model_group": "gateway_deployment",
    "litellm.retry_count": "gateway_retry_count",
}

VERBOSE = False
STATE = {
    "dir": DEFAULT_DIR,
    "port": DEFAULT_PORT,
    "dry_run": False,
}


def log(msg: str) -> None:
    if VERBOSE:
        sys.stderr.write(msg + "\n")


def israel_now() -> datetime:
    raw = os.environ.get("TAMIRS_USAGE_CAPTURE_NOW", "").strip()
    if raw:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=ISRAEL_TZ)
        return dt.astimezone(ISRAEL_TZ)
    return datetime.now(ISRAEL_TZ)


def israel_ts(dt: datetime | None = None) -> str:
    return (dt or israel_now()).isoformat(timespec="seconds")


def usage_dir() -> str:
    return os.path.abspath(STATE["dir"])


def pid_path() -> str:
    return os.path.join(usage_dir(), PID_NAME)


def ensure_dir(path: str) -> None:
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def otel_value(value: Any) -> Any:
    if not isinstance(value, dict):
        return value
    if "stringValue" in value:
        return value["stringValue"]
    if "intValue" in value:
        try:
            return int(value["intValue"])
        except (TypeError, ValueError):
            return value["intValue"]
    if "doubleValue" in value:
        return float(value["doubleValue"])
    if "boolValue" in value:
        return bool(value["boolValue"])
    if "arrayValue" in value:
        return [otel_value(v) for v in value["arrayValue"].get("values", [])]
    if "kvlistValue" in value:
        out = {}
        for item in value["kvlistValue"].get("values", []):
            out[item.get("key", "")] = otel_value(item.get("value", {}))
        return out
    return None


def attrs_to_dict(attrs: Any) -> dict[str, Any]:
    out: dict[str, Any] = {}
    if not isinstance(attrs, list):
        return out
    for item in attrs:
        if not isinstance(item, dict):
            continue
        key = item.get("key")
        if not key:
            continue
        out[str(key)] = otel_value(item.get("value", {}))
    return out


def rename_attrs(raw: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, val in raw.items():
        if key in DROP_ATTRS:
            continue
        out[ATTR_RENAME.get(key, key)] = val
    if "model" not in out and raw.get("gen_ai.request.model"):
        out["model"] = raw["gen_ai.request.model"]
    return out


def canonicalize(event: dict[str, Any], harness: str = "claude_code") -> dict[str, Any] | None:
    data = {k: v for k, v in event.items() if k not in DROP_ATTRS}
    name = str(data.get("event") or data.get("name") or data.get("body") or "")
    mapped = EVENT_MAP.get(name) or EVENT_MAP.get(name.split(".")[-1] if name else "")
    if not mapped:
        log("skip unknown event %s" % (name or "<empty>",))
        return None
    data["event"] = mapped
    data.setdefault("harness", harness)
    data.setdefault("ts", israel_ts())
    request_id = data.pop("request_id", None)
    if request_id:
        hashed = hash_identifier(str(request_id))
        if hashed:
            data["request_id_hash"] = hashed
    for field in ("gateway_kind", "endpoint_label"):
        value = data.get(field)
        if value is not None and not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", str(value)):
            data.pop(field, None)
    cleaned: dict[str, Any] = {}
    for key in KEEP:
        val = data.get(key)
        if val is None or val == "":
            continue
        cleaned[key] = val
    if "event" not in cleaned or "harness" not in cleaned:
        return None
    return cleaned


def hash_identifier(value: str) -> str | None:
    """Return a local HMAC for correlation without retaining an upstream ID."""
    try:
        ensure_dir(usage_dir())
        key_path = os.path.join(usage_dir(), ".usage-capture-hmac-key")
        try:
            with open(key_path, "rb") as handle:
                key = handle.read()
        except FileNotFoundError:
            key = os.urandom(32)
            with open(key_path, "xb") as handle:
                handle.write(key)
            os.chmod(key_path, 0o600)
        return hmac.new(key, value.encode("utf-8"), hashlib.sha256).hexdigest()[:24]
    except OSError:
        return None


def append_jsonl(record: dict[str, Any]) -> str | None:
    cleaned = canonicalize(record, harness=str(record.get("harness") or "claude_code"))
    if cleaned is None:
        return None
    if STATE["dry_run"]:
        log("dry-run %s" % json.dumps(cleaned, ensure_ascii=False))
        return None
    directory = usage_dir()
    ensure_dir(directory)
    day = israel_now().strftime("%Y-%m-%d")
    path = os.path.join(directory, "%s.jsonl" % day)
    line = json.dumps(cleaned, ensure_ascii=False, separators=(",", ":")) + "\n"
    new_file = not os.path.exists(path)
    with open(path, "a", encoding="utf-8") as handle:
        try:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        except (ImportError, OSError):
            pass
        handle.write(line)
        handle.flush()
        os.fsync(handle.fileno())
    if new_file:
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    log("wrote %s" % path)
    return path


def resource_gateway(resource: dict[str, Any]) -> dict[str, str]:
    attrs = attrs_to_dict(resource.get("attributes", []))
    result: dict[str, str] = {}
    for source, target in (("tamirs.gateway_kind", "gateway_kind"), ("tamirs.endpoint_label", "endpoint_label")):
        if attrs.get(source):
            result[target] = str(attrs[source])
    return result


def handle_logs(payload: dict[str, Any]) -> int:
    written = 0
    for resource_log in payload.get("resourceLogs") or []:
        gateway = resource_gateway(resource_log.get("resource") or {})
        for scope in resource_log.get("scopeLogs") or []:
            for rec in scope.get("logRecords") or []:
                attrs = rename_attrs(attrs_to_dict(rec.get("attributes") or []))
                body = otel_value(rec.get("body") or {})
                if body and "event" not in attrs:
                    attrs["body"] = body
                    attrs.setdefault("event", body)
                for key, value in gateway.items():
                    attrs.setdefault(key, value)
                if append_jsonl(attrs):
                    written += 1
    return written


def handle_traces(payload: dict[str, Any]) -> int:
    written = 0
    for resource_span in payload.get("resourceSpans") or []:
        gateway = resource_gateway(resource_span.get("resource") or {})
        for scope in resource_span.get("scopeSpans") or []:
            for span in scope.get("spans") or []:
                attrs = rename_attrs(attrs_to_dict(span.get("attributes") or []))
                name = span.get("name") or ""
                attrs.setdefault("event", name)
                for key, value in gateway.items():
                    attrs.setdefault(key, value)
                if "duration_ms" not in attrs:
                    try:
                        start = int(span.get("startTimeUnixNano") or 0)
                        end = int(span.get("endTimeUnixNano") or 0)
                        if end > start:
                            attrs["duration_ms"] = int((end - start) / 1_000_000)
                    except (TypeError, ValueError):
                        pass
                if append_jsonl(attrs):
                    written += 1
    return written


def handle_ingest(payload: Any) -> int:
    records = payload if isinstance(payload, list) else [payload]
    written = 0
    for rec in records:
        if not isinstance(rec, dict):
            continue
        rec.setdefault("harness", "opencode")
        if append_jsonl(rec):
            written += 1
    return written


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        if VERBOSE:
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, code: int, body: dict[str, Any]) -> None:
        raw = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(raw)

    def _read_json(self) -> Any:
        length = int(self.headers.get("Content-Length") or "0")
        if length < 0 or length > MAX_BODY:
            raise ValueError("body too large")
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path in ("/health", "/"):
            self._send(200, {"ok": True, "service": "usage-capture"})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype and ctype not in ("application/json", "application/json; charset=utf-8"):
            if "protobuf" in ctype or "proto" in ctype:
                self._send(415, {"ok": False, "error": "use OTEL_EXPORTER_OTLP_PROTOCOL=http/json"})
                return
        path = urlparse(self.path).path
        try:
            payload = self._read_json()
        except (ValueError, json.JSONDecodeError) as exc:
            self._send(400, {"ok": False, "error": str(exc)})
            return
        try:
            if path == "/v1/logs":
                written = handle_logs(payload if isinstance(payload, dict) else {})
            elif path == "/v1/traces":
                written = handle_traces(payload if isinstance(payload, dict) else {})
            elif path == "/ingest":
                written = handle_ingest(payload)
            else:
                self._send(404, {"ok": False, "error": "not found"})
                return
        except Exception as exc:  # noqa: BLE001 — fail-open HTTP, log the reason
            log("handler error: %s" % exc)
            self._send(500, {"ok": False, "error": "internal"})
            return
        self._send(200, {"ok": True, "written": written})


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_pid() -> int | None:
    path = pid_path()
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            return int(handle.read().strip())
    except (OSError, ValueError):
        return None


def write_pid(pid: int) -> None:
    ensure_dir(usage_dir())
    path = pid_path()
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("%s\n" % pid)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def health_ok(port: int) -> bool:
    try:
        with socket.create_connection((LOOPBACK, port), timeout=0.4) as sock:
            req = b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
            sock.sendall(req)
            data = sock.recv(1024)
            return b'"ok": true' in data or b'"ok":true' in data
    except OSError:
        return False


def status_payload() -> dict[str, Any]:
    pid = read_pid()
    running = bool(pid and pid_alive(pid) and health_ok(int(STATE["port"])))
    return {
        "ok": True,
        "running": running,
        "pid": pid if running else None,
        "port": int(STATE["port"]),
        "dir": usage_dir(),
        "bind": LOOPBACK,
    }


def stop_collector() -> int:
    pid = read_pid()
    if not pid or not pid_alive(pid):
        try:
            os.remove(pid_path())
        except OSError:
            pass
        return 0
    os.kill(pid, signal.SIGTERM)
    try:
        os.remove(pid_path())
    except OSError:
        pass
    return 0


def serve() -> None:
    ensure_dir(usage_dir())
    server = ThreadingHTTPServer((LOOPBACK, int(STATE["port"])), Handler)
    server.daemon_threads = True
    actual_port = server.server_address[1]
    STATE["port"] = actual_port
    write_pid(os.getpid())
    log("listening on %s:%s dir=%s" % (LOOPBACK, actual_port, usage_dir()))

    def shutdown(_signum: int, _frame: Any) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        try:
            if read_pid() == os.getpid():
                os.remove(pid_path())
        except OSError:
            pass


def daemonize() -> None:
    if os.fork() > 0:
        os._exit(0)
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    fd = os.open(os.devnull, os.O_RDWR)
    os.dup2(fd, 0)
    os.dup2(fd, 1)
    os.dup2(fd, 2)
    if fd > 2:
        os.close(fd)
    serve()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="collector.py",
        description="Local-only OTLP/JSONL usage collector (127.0.0.1, Israel-dated files).",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="log to stderr")
    parser.add_argument("--dir", default=os.environ.get("TAMIRS_USAGE_CAPTURE_DIR", DEFAULT_DIR), help="log directory")
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("TAMIRS_USAGE_CAPTURE_PORT", str(DEFAULT_PORT))),
        help="listen port (default 17431)",
    )
    parser.add_argument("--bind", default=LOOPBACK, help="must be 127.0.0.1")
    parser.add_argument("--dry-run", action="store_true", help="parse and print; do not listen or write")
    parser.add_argument("--daemon", action="store_true", help="fork into the background")
    parser.add_argument("--stop", action="store_true", help="stop a daemonized collector")
    parser.add_argument("--status", action="store_true", help="print running status")
    parser.add_argument("--json", action="store_true", help="machine-readable status/dry-run output")
    args = parser.parse_args(argv)
    if args.bind not in (LOOPBACK, "localhost"):
        parser.error("refusing non-loopback bind %r (must be 127.0.0.1)" % args.bind)
    if args.port < 0 or args.port > 65535:
        parser.error("port must be 0-65535")
    return args


def main(argv: list[str] | None = None) -> int:
    global VERBOSE
    args = parse_args(argv)
    VERBOSE = bool(args.verbose)
    STATE["dir"] = os.path.expanduser(args.dir)
    STATE["port"] = args.port
    STATE["dry_run"] = bool(args.dry_run)

    if args.stop:
        return stop_collector()

    if args.status:
        payload = status_payload()
        sys.stdout.write(json.dumps(payload) + "\n")
        return 0

    if args.dry_run:
        payload = {
            "ok": True,
            "dry_run": True,
            "bind": LOOPBACK,
            "port": args.port,
            "dir": usage_dir(),
        }
        sys.stdout.write(json.dumps(payload) + "\n")
        return 0

    if args.daemon:
        current = status_payload()
        if current["running"]:
            sys.stdout.write(json.dumps(current) + "\n")
            return 0
        daemonize()
        return 0

    serve()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
