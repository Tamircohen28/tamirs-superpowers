// tui.tsx — OpenCode 2 TUI plugin: the status line and the objective pane.
//
// OpenCode's analogue of this repo's Claude Code mod (mod/register.tsx) and
// statusline (scripts/statusline.sh). It is a separate plugin API from guard.ts
// — `@opencode/plugin/tui`, Solid + OpenTUI — loaded by the terminal client from
// the same plugin directory (`<dir>/tui`), never by the server.
//
// WHAT IT DRAWS, AND FROM WHAT
//   prompt.footer.status  one line after OpenCode's own health indicators:
//                         context fill of the LAST model step (prompt tokens
//                         against the model's context limit), the session's
//                         cumulative cost, and the active objective's progress.
//   session.panel         the objective's task rows, opened with /objective or
//                         `tamirs-superpowers.objective` from the command palette.
//
// WHAT IT CANNOT DRAW, AND WHY
//   Rate-limit windows. scripts/statusline.sh and mod/register.tsx draw the
//   5-hour / 7-day windows Claude Code pushes in its status payload, and the mod
//   raises the switch-dev handoff band from them. OpenCode documents NO rate-limit
//   payload anywhere a TUI plugin can see — not on SessionInfo, not in any
//   session.* event, not in `data` (checked against @opencode/client 2.0.32's
//   generated types and the V2 docs on 2026-10-17). The server plugin could in
//   principle read provider headers from ctx.session.hook("http.response"), but
//   that is undocumented and header names are provider-specific, so this plugin
//   shows what the host actually exposes and says so here rather than guessing.
//
// DATA SOURCES
//   - ctx.data.session.get(id).tokens / .cost — cumulative per session (host).
//   - "session.step.ended" events — per-step tokens; input + cache.read +
//     cache.write is the prompt the model just saw, i.e. the context fill.
//   - ctx.data.location.model.list() — ModelInfo.limit.context for the %.
//   - .dev-files/objectives/<id>/ on disk (state.ts) — the TUI runs on the
//     terminal's own machine, so this reads the LOCAL checkout; against a remote
//     server the objective shown is the local clone's, which is recorded in the
//     install doc rather than papered over.

import { Plugin } from "@opencode/plugin/tui"
import { For, Show } from "solid-js"
import { gitRoots, readObjectiveView, type ObjectiveTask, type ObjectiveView } from "./state.ts"

const ID = "tamirs-superpowers.tui"
const PANEL = "tamirs-superpowers.objective"
const REFRESH_MS = 5000

interface StepUsage {
  readonly prompt: number
  readonly output: number
}

interface State {
  objective: ObjectiveView | null
  objectiveError: string
  steps: Record<string, StepUsage>
}

function pct(n: number, d: number): string {
  if (!d || !Number.isFinite(n)) return "?"
  return `${Math.min(999, Math.round((n / d) * 100))}%`
}

function money(usd: number | undefined): string {
  return typeof usd === "number" && Number.isFinite(usd) ? `$${usd.toFixed(2)}` : ""
}

function taskLine(t: ObjectiveTask): string {
  const tail = [t.role, t.branch, t.handoff ? `handoff: ${t.handoff}` : ""].filter(Boolean).join("  ")
  return `${t.id}  ${t.status.padEnd(9)}  ${t.title}${tail ? `  (${tail})` : ""}`
}

function objectiveSummary(o: ObjectiveView | null): string {
  if (!o) return ""
  const done = o.tasks.filter((t) => t.status === "completed").length
  const running = o.tasks.filter((t) => t.status === "running").length
  return `obj ${o.id} ${done}/${o.tasks.length}${running ? ` · ${running} worker${running === 1 ? "" : "s"} running` : ""}`
}

export default Plugin.define({
  id: ID,
  setup(ctx) {
    const [state, update] = ctx.storage.memory<State>("state", {
      initial: { objective: null, objectiveError: "", steps: {} },
    })

    const directory = () => ctx.location?.directory ?? ctx.data.location.default().directory
    const objective = () => state.objective

    const refresh = () => {
      try {
        const roots = gitRoots(directory())
        const view = roots ? readObjectiveView(roots.mainRoot) : null
        update((d) => {
          d.objective = view
          d.objectiveError = ""
        })
      } catch (err) {
        update((d) => {
          d.objectiveError = err instanceof Error ? err.message : String(err)
        })
      }
    }

    refresh()
    const timer = setInterval(refresh, REFRESH_MS)

    // Per-step prompt size: the only context-fill signal the host exposes.
    const stopSteps = ctx.data.on("session.step.ended", (event) => {
      const t = event.data.tokens
      const prompt = (t?.input ?? 0) + (t?.cache?.read ?? 0) + (t?.cache?.write ?? 0)
      update((d) => {
        d.steps[event.data.sessionID] = { prompt, output: t?.output ?? 0 }
      })
    })
    // A finished tool call is when objective state on disk most likely changed.
    const stopTools = ctx.data.on("session.tool.success", () => refresh())

    const contextLimit = (sessionID: string): number => {
      const s = ctx.data.session.get(sessionID)
      const ref = s?.model ?? ctx.ui.model.current()
      if (!ref) return 0
      const id = "modelID" in ref ? ref.modelID : ref.id
      const models = ctx.data.location.model.list() ?? []
      const m = models.find((x) => x.id === id && x.providerID === ref.providerID)
      return m?.limit?.context ?? 0
    }

    const statusText = (sessionID: string | undefined): string => {
      const parts: string[] = []
      if (sessionID) {
        const step = state.steps[sessionID]
        if (step) parts.push(`ctx ${pct(step.prompt, contextLimit(sessionID))}`)
        const s = ctx.data.session.get(sessionID)
        const cost = money(s?.cost)
        if (cost) parts.push(cost)
      }
      const obj = objectiveSummary(state.objective)
      if (obj) parts.push(obj)
      return parts.join(" · ")
    }

    const unslotFooter = ctx.ui.slot({
      append: "prompt.footer.status",
      render: ({ sessionID }) => (
        <Show when={statusText(sessionID)}>
          <text>{statusText(sessionID)}</text>
        </Show>
      ),
    })

    const unslotPanel = ctx.ui.slot({
      append: "session.panel",
      render: (panel) => (
        <Show when={panel.name === PANEL}>
          <box flexDirection="column">
            <Show
              when={objective()}
              fallback={
                <box flexDirection="column">
                  <text>No objective is active.</text>
                  <text>/plan-dev writes one under .dev-files/objectives/.</text>
                  <Show when={state.objectiveError}>
                    <text>{state.objectiveError}</text>
                  </Show>
                </box>
              }
            >
              <box flexDirection="column">
                <text>
                  {objective()!.id} — {objective()!.title} [{objective()!.status}]
                </text>
                <text>{objectiveSummary(objective())}</text>
                <For each={objective()!.tasks} fallback={<text>(no tasks yet)</text>}>
                  {(t) => <text>{taskLine(t)}</text>}
                </For>
              </box>
            </Show>
          </box>
        </Show>
      ),
    })

    // Commands must be registered from inside a reactive scope; the documented
    // pattern is an `app` slot whose render installs the keymap layer.
    const unslotApp = ctx.ui.slot({
      append: "app",
      render: () => {
        ctx.keymap.layer(() => ({
          mode: "global",
          commands: [
            {
              id: "tamirs-superpowers.objective",
              title: "Show the active orchestration objective (tamirs-superpowers)",
              group: "tamirs-superpowers",
              palette: true,
              slash: { name: "objective" },
              run: () => {
                refresh()
                ctx.ui.panel.open(PANEL)
              },
            },
          ],
        }))
        return null
      },
    })

    return () => {
      clearInterval(timer)
      stopSteps()
      stopTools()
      unslotFooter()
      unslotPanel()
      unslotApp()
    }
  },
})
