#!/usr/bin/env node
/**
 * Optional OpenCode usage-capture plugin.
 *
 * Observe-only: never mutates chat.params, messages, or headers. Writes the
 * same JSONL schema as scripts/usage-capture/collector.py, either by POSTing
 * /ingest on 127.0.0.1 or by appending the daily file directly.
 *
 * Not loaded by this repo's opencode.json. Add the absolute path of this file
 * to your OpenCode `plugin` list to opt in. Bodies stay off unless
 * TAMIRS_USAGE_CAPTURE_BODIES=1.
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

function walk(node, visit) {
  if (!node) return
  if (Array.isArray(node)) {
    for (const item of node) walk(item, visit)
    return
  }
  if (typeof node === "object") {
    visit(node)
    for (const v of Object.values(node)) walk(v, visit)
  }
}

function inventory(messages) {
  const skills = new Set()
  const commands = new Set()
  walk(messages, (node) => {
    const skill = node.skill || node.skill_name || node.skillName
    if (typeof skill === "string" && skill) skills.add(skill)
    if (node.tool === "skill" || node.name === "Skill" || node.toolName === "Skill") {
      const input = node.input || node.args || {}
      const named = input.skill || input.name || input.skill_name
      if (typeof named === "string") skills.add(named)
    }
    const text = typeof node.text === "string" ? node.text : (typeof node.content === "string" ? node.content : "")
    const slash = text.trim().match(/^\/([a-z0-9]+(?:-[a-z0-9]+)*)\b/)
    if (slash) commands.add(slash[1])
  })
  return {
    skill_name: [...skills][0],
    command_name: [...commands][0],
  }
}

function requestBytes(messages) {
  try {
    return Buffer.byteLength(JSON.stringify(messages || []), "utf8")
  } catch {
    return undefined
  }
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

async function persist(record) {
  const rec = omitEmpty({
    ts: israelParts(),
    harness: "opencode",
    gateway_kind: opaqueLabel(process.env.TAMIRS_USAGE_CAPTURE_GATEWAY_KIND),
    endpoint_label: opaqueLabel(process.env.TAMIRS_USAGE_CAPTURE_ENDPOINT_LABEL),
    ...record,
  })
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

async function maybeWriteBody(messages, requestId) {
  if (process.env.TAMIRS_USAGE_CAPTURE_BODIES !== "1") return undefined
  try {
    const fs = await import("node:fs/promises")
    const path = await import("node:path")
    const dir = path.join(logDir(), "bodies")
    await fs.mkdir(dir, { recursive: true, mode: 0o700 })
    const file = path.join(dir, String(requestId || Date.now()) + ".request.json")
    await fs.writeFile(file, JSON.stringify(messages, null, 2), { encoding: "utf8", mode: 0o600 })
    return file
  } catch {
    return undefined
  }
}

function unwrapEvent(input) {
  const ev = input && (input.event || input)
  if (!ev || typeof ev !== "object") return { type: "", payload: {} }
  const type = ev.type || ev.event || ev.name || ""
  const payload = ev.properties || ev.payload || ev.info || ev
  return { type, payload, raw: ev }
}

export default async function usageCapturePlugin() {
  let lastModel
  let lastMessages
  let lastBytes
  let lastInv

  return {
    "chat.params": async (input) => {
      try {
        const model = input && (input.model || input)
        lastModel = (model && (model.modelID || model.id || model.model)) || lastModel
      } catch {
        // observe-only, fail-open
      }
    },

    "experimental.chat.messages.transform": async (_input, output) => {
      try {
        const messages = (output && output.messages) || []
        lastMessages = messages
        lastBytes = requestBytes(messages)
        lastInv = inventory(messages)
      } catch {
        // do not mutate output.messages
      }
    },

    event: async (input) => {
      try {
        const { type, payload } = unwrapEvent(input)
        if (type === "session.created" || type === "session.updated" && payload && payload.status === "created") {
          await persist({ event: "session_start", session_id: payload.sessionID || payload.id })
          return
        }
        if (type === "command.executed") {
          await persist({
            event: "skill_activated",
            session_id: payload.sessionID,
            command_name: payload.command || payload.name,
            skill_name: payload.skill || payload.name,
          })
          return
        }
        const ended = type === "session.next.step.ended" || /\.step\.ended$/.test(String(type))
        if (!ended) return
        const tokens = payload.tokens || payload.usage || {}
        const requestId = payload.id || payload.requestID || payload.request_id || String(Date.now())
        const bodyRef = await maybeWriteBody(lastMessages, requestId)
        await persist({
          event: "api_request",
          session_id: payload.sessionID || payload.session_id,
          request_id: requestId,
          model: lastModel || payload.model || (payload.modelID),
          duration_ms: payload.duration || payload.duration_ms || payload.ms,
          input_tokens: tokens.input || tokens.input_tokens,
          output_tokens: tokens.output || tokens.output_tokens,
          cache_read_tokens: tokens.cache || tokens.cacheRead || tokens.cache_read,
          cache_creation_tokens: tokens.cacheWrite || tokens.cache_creation,
          cost_usd: payload.cost || payload.cost_usd,
          request_bytes: lastBytes,
          body_ref: bodyRef,
          body_length: lastBytes,
          stop_reason: payload.reason || payload.finish || payload.finishReason,
          success: payload.error ? false : true,
          ...(lastInv || {}),
        })
      } catch {
        // fail-open
      }
    },
  }
}
