// plugin-config.ts — the OpenCode /plugin-config command (ADR 004 D6).
//
// A CODE command (ctx.command.transform), not a prompt template: no model is in the
// loop, so the arguments the user typed reach the D6 writer, scripts/plugin-config.sh,
// verbatim and deterministically. The writer decides everything: it tightens at once,
// records a widening pending, and refuses `confirm` here because OpenCode has no
// host-attested channel (D5: `--auto` approves every ask, measured O1) — it then names
// the command to run in the user's own terminal. The writer is told the session is
// OpenCode through OPENCODE=1, a marker that can only make it stricter.
//
// Surface: `ctx.command.transform(e => e.add({ name, description, execute }))`, execute
// receives `{ sessionID, prompt, delivery }` and resolves to void (@opencode/plugin
// promise/command.ts at v2.2.5). How a command shows text is not part of that API, so
// the writer's output goes to the session through `ctx.session.synthetic` when the host
// offers it — unmeasured — and is otherwise left in the thrown error of a failed run.
// The write itself never depends on the display.
//
// Name clash, unmeasured: scripts/build-opencode-commands.sh also emits a prompt-template
// command .opencode/commands/plugin-config.md from the skill; which of the two OpenCode
// runs for `/plugin-config` has not been observed.

import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import path from "node:path"
import { fileURLToPath } from "node:url"

const ID = "tamirs-superpowers.plugin-config"
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..")
const WRITER = path.join(ROOT, "scripts", "plugin-config.sh")

/** The argument text of a command invocation, whatever shape the prompt arrives in. */
export function promptText(prompt: unknown): string {
  if (typeof prompt === "string") return prompt
  if (prompt && typeof prompt === "object") {
    const p = prompt as { text?: unknown; parts?: unknown }
    if (typeof p.text === "string") return p.text
    if (Array.isArray(p.parts)) {
      return p.parts
        .map((x) => (x && typeof x === "object" && typeof (x as { text?: unknown }).text === "string" ? (x as { text: string }).text : ""))
        .join(" ")
    }
  }
  return ""
}

/** Words of the first line, with a leading `/plugin-config` dropped; no shell is involved. */
export function writerArgs(text: string): string[] {
  const words = (text.split("\n")[0] || "").trim().split(/\s+/).filter(Boolean)
  if (words[0] === "/plugin-config" || words[0] === "plugin-config") words.shift()
  return words.length ? words : ["show"]
}

/** Run the writer; returns its exit code and combined output. Never throws. */
export function runWriter(args: string[]): { code: number; output: string } {
  try {
    const out = execFileSync("bash", [WRITER, ...args], {
      encoding: "utf8",
      timeout: 30_000,
      env: { ...process.env, OPENCODE: "1" },
      stdio: ["ignore", "pipe", "pipe"],
    })
    return { code: 0, output: out }
  } catch (err) {
    const e = err as { status?: number; stdout?: string; stderr?: string; message?: string }
    return { code: typeof e.status === "number" ? e.status : 1, output: `${e.stdout ?? ""}${e.stderr ?? ""}` || String(e.message ?? err) }
  }
}

export default Plugin.define({
  id: ID,
  async setup(ctx) {
    await ctx.command.transform((editor) => {
      editor.add({
        name: "plugin-config",
        description: "Show or change the tamirs-superpowers permission level (deterministic writer, no model)",
        async execute(input) {
          const { code, output } = runWriter(writerArgs(promptText(input.prompt)))
          const text = `plugin-config (exit ${code}):\n${output.trim()}`
          const session = ctx.session as unknown as { synthetic?: (a: unknown) => Promise<unknown> }
          if (typeof session.synthetic === "function") {
            try {
              await session.synthetic({ sessionID: input.sessionID, text })
              return
            } catch {
              // fall through: the write already happened or was refused by the writer
            }
          }
          if (code !== 0) throw new Error(text)
        },
      })
    })
  },
})
