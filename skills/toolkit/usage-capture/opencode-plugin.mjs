#!/usr/bin/env node
/**
 * Optional OpenCode 2 usage-capture plugin.
 *
 * Observe-only: registers no hook, no transform and no tool — it only reads
 * the public event stream through `ctx.event.subscribe()` and never mutates a
 * message, a request or a header. Writes the same JSONL schema as
 * scripts/usage-capture/collector.py, either by POSTing /ingest on 127.0.0.1
 * or by appending the daily file directly.
 *
 * OPENCODE 2 ONLY. The previous revision of this file was an OpenCode 1 hooks
 * object (`chat.params`, `experimental.chat.messages.transform`, `event`);
 * "V1 plugin implementations do not run in V2"
 * (https://opencode.ai/v2/docs/build/plugins/migrate-v1/). The V2 shape is a
 * default export with `id` and `setup(ctx)` — exactly what `Plugin.define()`
 * from `@opencode/plugin` returns (it is an identity function, see
 * packages/plugin/src/promise/plugin.ts). The object is exported directly rather
 * than through that import so this file keeps its one property that matters:
 * zero imports, loadable by `node` for a test with a fake ctx, and nothing on
 * the machine is read other than its own TAMIRS_USAGE_CAPTURE_* variables.
 *
 * Not loaded by this repo's opencode.json. Add the absolute path of this file
 * to your OpenCode `plugins` list to opt in. Bodies stay off: V2 exposes no
 * outgoing request body to a passive subscriber (that was the V1
 * messages.transform hook), so TAMIRS_USAGE_CAPTURE_BODIES is accepted but
 * records nothing on OpenCode 2 — stated here rather than silently.
 *
 * Event -> record mapping (names from @opencode/client 2.0.32's event union):
 *   session.created          -> session_start
 *   session.skill.activated  -> skill_activated  (skill_name = data.name)
 *   session.model.selected   -> remembered; stamps `model` on later requests
 *   session.step.ended       -> api_request      (tokens, cost, finish reason)
 *   session.step.failed      -> api_error
 *   session.usage.recorded   -> api_request with query_source title|compaction
 */
const DEFAULT_PORT = "17431"
const DEFAULT_DIR = "~/.local/share/tamirs-superpowers/usage"
const TZ = "Asia/Jerusalem"

function expandHome(p) {
  if (!p) return p
  if (p.startsWith("~/")) {
    const home = process.env.HOME || process.env.USERPROFILE || ""
    return home + p.slice(1)
  }
  return p
}

function logDir() {
  return expandHome(process.env.TAMIRS_USAGE_CAPTURE_DIR || DEFAULT_DIR)
}

function port() {
  return String(process.env.TAMIRS_USAGE_CAPTURE_PORT || DEFAULT_PORT)
}

function opaqueLabel(value) {
  return typeof value === "string" && /^[A-Za-z0-9_.-]{1,80}$/.test(value) ? value : undefined
}

function israelParts(date = new Date()) {
  const fmt = new Intl.DateTimeFormat("en-GB", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
    timeZoneName: "longOffset",
  })
  const parts = {}
  for (const p of fmt.formatToParts(date)) {
    if (p.type !== "literal") parts[p.type] = p.value
  }
  let offset = parts.timeZoneName || "+00:00"
  offset = offset.replace("GMT", "").replace("UTC", "")
  if (offset === "" || offset === "Z") offset = "+00:00"
  if (/^[+-]\d{2}$/.test(offset)) offset = offset + ":00"
  if (!offset.startsWith("+") && !offset.startsWith("-")) offset = "+" + offset
  return parts.year + "-" + parts.month + "-" + parts.day + "T" +
    parts.hour + ":" + parts.minute + ":" + parts.second + offset
}

function dayStamp() {
  return israelParts().slice(0, 10)
}

function omitEmpty(rec) {
  const out = {}
  for (const [k, v] of Object.entries(rec)) {
    if (v === undefined || v === null || v === "") continue
    out[k] = v
  }
  return out
}

async function appendFile(record) {
  const fs = await import("node:fs/promises")
  const path = await import("node:path")
  const dir = logDir()
  await fs.mkdir(dir, { recursive: true, mode: 0o700 }).catch(() => {})
  const file = path.join(dir, dayStamp() + ".jsonl")
  const line = JSON.stringify(record) + "\n"
  await fs.appendFile(file, line, { encoding: "utf8", mode: 0o600 })
}

// Exported for the test: a sink other than fetch/append can be injected.
export async function persist(record, sink) {
  const rec = omitEmpty({
    ts: israelParts(),
    harness: "opencode",
    gateway_kind: opaqueLabel(process.env.TAMIRS_USAGE_CAPTURE_GATEWAY_KIND),
    endpoint_label: opaqueLabel(process.env.TAMIRS_USAGE_CAPTURE_ENDPOINT_LABEL),
    ...record,
  })
  if (sink) return sink(rec)
  const url = "http://127.0.0.1:" + port() + "/ingest"
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(rec),
    })
    if (res.ok) return
  } catch {
    // collector down — write the file ourselves
  }
  try {
    // The collector HMACs request IDs. If it is unavailable, do not write an
    // upstream identifier directly to the fallback JSONL file.
    const { request_id, ...withoutRequestId } = rec
    await appendFile(withoutRequestId)
  } catch {
    // fail-open
  }
}

function modelId(ref) {
  if (!ref || typeof ref !== "object") return undefined
  const id = ref.modelID || ref.id
  return ref.providerID && id ? ref.providerID + "/" + id : id
}

/**
 * Translate one V2 event into zero or one usage record. Pure; exported for the
 * test. `models` is the per-session model memory (sessionID -> model id).
 */
export function recordFor(event, models) {
  if (!event || typeof event !== "object") return undefined
  const type = String(event.type || "")
  const data = event.data && typeof event.data === "object" ? event.data : {}
  const sessionID = data.sessionID
  switch (type) {
    case "session.created":
      if (data.model) models.set(sessionID, modelId(data.model))
      return { event: "session_start", session_id: sessionID }
    case "session.model.selected":
      models.set(sessionID, modelId(data.model))
      return undefined
    case "session.skill.activated":
      return { event: "skill_activated", session_id: sessionID, skill_name: data.name || data.id }
    case "session.step.ended": {
      const t = data.tokens || {}
      const cache = t.cache || {}
      return {
        event: "api_request",
        session_id: sessionID,
        request_id: data.assistantMessageID,
        model: models.get(sessionID),
        input_tokens: t.input,
        output_tokens: t.output,
        cache_read_tokens: cache.read,
        cache_creation_tokens: cache.write,
        cost_usd: data.cost,
        stop_reason: data.finish,
        success: data.finish !== "error",
      }
    }
    case "session.step.failed":
      return {
        event: "api_error",
        session_id: sessionID,
        request_id: data.assistantMessageID,
        model: models.get(sessionID),
        success: false,
      }
    case "session.usage.recorded": {
      const t = data.tokens || {}
      const cache = t.cache || {}
      return {
        event: "api_request",
        session_id: sessionID,
        query_source: data.source,
        model: models.get(sessionID),
        input_tokens: t.input,
        output_tokens: t.output,
        cache_read_tokens: cache.read,
        cache_creation_tokens: cache.write,
        cost_usd: data.cost,
        success: true,
      }
    }
    default:
      return undefined
  }
}

export default {
  id: "tamirs-superpowers.usage-capture",
  setup(ctx) {
    const controller = new AbortController()
    const models = new Map()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          try {
            const rec = recordFor(event, models)
            if (rec) await persist(rec)
          } catch {
            // observe-only, fail-open
          }
        }
      } catch {
        // stream closed (abort on unload) or unavailable — nothing to do
      }
    })()
    return () => controller.abort()
  },
}
