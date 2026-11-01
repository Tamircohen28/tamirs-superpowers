// index.ts — the SERVER entrypoint OpenCode 2 resolves for this plugin directory.
//
// Host resolution (packages/plugin/src/host.ts, read at v2.2.5): a local directory whose
// package.json names the package and maps `exports` resolves through them — `.` for the
// server plugin (this file) and `./tui` for the TUI plugin — and a directory without
// `exports` falls back to `<dir>/server`, then `<dir>/index`, and `<dir>/tui`. One
// directory carries both. The implementation lives in guard.ts so the file name says
// what it does; this shim exists only to be found.
export { default } from "./guard.ts"
