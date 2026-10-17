// tui.ts — the TUI entrypoint OpenCode 2 resolves for this plugin directory
// (`<dir>/tui`, see index.ts). The implementation is tui.tsx because it is Solid
// JSX; this extension-less-import shim exists so a resolver that probes `.ts`
// before `.tsx` still lands on the right module.
export { default } from "./tui.tsx"
