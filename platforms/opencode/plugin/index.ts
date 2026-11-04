// index.ts — the SERVER entrypoint OpenCode 2 resolves for this plugin directory.
//
// Host resolution (packages/plugin/src/host.ts, read at v2.2.5): a local directory whose
// package.json names the package and maps `exports` resolves through them — `.` for the
// server plugin (this file) and `./tui` for the TUI plugin — and a directory without
// `exports` falls back to `<dir>/server`, then `<dir>/index`, and `<dir>/tui`. One
// directory carries both, so one server plugin: this file composes the two server
// parts. Plugin.define is the identity (promise/plugin.ts at v2.2.5), so each part's
// setup can be called directly. The guard is set up first and on its own: a failure of
// the /plugin-config command (ADR 004 D6) must never cost the guards.
import { Plugin } from "@opencode/plugin"
import guard from "./guard.ts"
import pluginConfig from "./plugin-config.ts"

export default Plugin.define({
  id: guard.id,
  async setup(ctx) {
    const cleanups = [await guard.setup(ctx)]
    try {
      cleanups.push(await pluginConfig.setup(ctx))
    } catch {
      // the command is a convenience; the guards above stay registered
    }
    return async () => {
      for (const c of cleanups) if (typeof c === "function") await c()
    }
  },
})
