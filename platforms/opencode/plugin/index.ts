// index.ts — the SERVER entrypoint OpenCode 2 resolves for this plugin directory.
//
// Host resolution (packages/plugin/src/host.ts at v2.0.32) tries `<dir>/server`
// then `<dir>/index` for the server plugin and `<dir>/tui` for the TUI plugin, so
// one directory carries both. The implementation lives in guard.ts so the file
// name says what it does; this shim exists only to be found.
export { default } from "./guard.ts"
