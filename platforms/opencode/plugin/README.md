# OpenCode 2 plugin — tamirs-superpowers

The OpenCode half of what `hooks/` and `mod/` do on Claude Code. One plugin
directory, two entrypoints, loaded by path from this repo's
[`opencode.json`](../../../opencode.json) (`"plugins": ["./platforms/opencode/plugin"]`)
— OpenCode 2 resolves `index.ts` as the server plugin and `tui.ts` as the TUI plugin
from the same directory, the layout its own discovery uses for
`.opencode/plugins/<name>/`.

| File | Runs in | Does |
|------|---------|------|
| `index.ts` → `guard.ts` | the OpenCode server (`@opencode/plugin`) | `ctx.permission.hook("evaluate")`: runs [`hooks/permission-guard.sh`](../../../hooks/permission-guard.sh) on every `shell` call and every bundled GitHub MCP call (`github_<tool>`) and denies what it denies (ADR 004 permission levels); denies a write to an R4 protected path (permission policy, guard files, host settings, ADR 004 D10.1); denies an `edit` to the main checkout while an objective is active, and a write to a generated file (lockfiles, `.github/workflows/`, `.yarn/releases/`, shadcn `components/ui/`, gitignored build output); on `shell`, refuses a force push and a push to a branch another agent's live claim holds, and applies the same path rules to every write target the canonical parse finds (`python3 hooks/lib/write-targets.py --protected`, as `hooks/guard-sensitive-files.sh` runs it: redirects, copies and extractions, git replays, patch headers; `rules.ts`'s port only where python3 is absent). `ctx.shell.hook("create.before")` throws the same reasons as a backstop for shells created outside the permission flow. |
| `plugin-config.ts` | the OpenCode server (composed in `index.ts`) | `/plugin-config` as a code command (`ctx.command.transform`, ADR 004 D6): the typed arguments go verbatim to `scripts/plugin-config.sh`, the deterministic writer, with no model in the loop. It tightens at once; a widening is recorded pending and must be confirmed in your own terminal, because OpenCode has no host-attested channel (D5). |
| `tui.ts` → `tui.tsx` | the terminal client (`@opencode/plugin/tui`) | `prompt.footer.status`: context fill of the last model step, session cost, objective progress. `session.panel` + `/objective`: the objective's task rows. |
| `rules.ts` | anywhere | The pure decision functions both of the above call, the protected-path table, and the payload and verdict halves of the permission-guard bridge. No I/O, no imports — unit-tested with plain Node. |
| `state.ts` | both | Git-root resolution (a linked worktree's `.git` file → main checkout) and the `.dev-files/objectives/<id>/` readers. |

The decisions mirror `hooks/enforce-worktree-edits.sh`, `hooks/guard-sensitive-files.sh`
and `hooks/protect-other-branches.sh` (claim store: `hooks/lib/agent-claim.sh`, the same
`~/.agent-work-claims/<key>.json` files, so an OpenCode session and a Claude Code
session see each other's branch claims). What is deliberately *not* mirrored, and
why, is in the header of `guard.ts`. What the status line cannot show (rate-limit
windows: OpenCode documents no such payload) is in the header of `tui.tsx`.

## Permission levels (ADR 004)

The permission guard is **not ported**: `guard.ts` runs the canonical
`hooks/permission-guard.sh` with a payload `rules.ts` builds, so the action catalog, the
conditions and `scripts/resolve-permission.sh` are the same code on every host. The
payload uses the guard's OpenCode dialect (`"host": "opencode"`): no option store and no
raise channel, which are OpenCode's rows of the ADR (D3: no install-time setting; D5: no
host-attested channel).

- **Ask only at R2.** A plugin `deny` is final under `opencode --auto` (measured, spike O1b);
  an `ask` is approved by it (O1c). So the guard's ask reaches OpenCode's prompt only for an
  R2 call (D8's OpenCode row); every R3 and R4 ask is a deny naming the setting that would
  allow it, to run in your own terminal (`bash scripts/plugin-config.sh standard`, `make setup`).
- **Never widens.** The plugin never sets `allow`, sets `ask` only from the guard's own R2
  answer, and never calls
  `ctx.session.update`, which can override a `deny` in your `opencode.json` (measured O2).
- **Fails closed.** A missing guard, a timeout, unreadable output or an exception is a deny.
- **Protected paths** (ADR 004 D10.1) are checked first and no variable unlocks them. The
  decision is `hooks/lib/write-targets.py --protected`'s, the shell hook's own; the fallback
  table in `rules.ts` is held equal to `core/permissions/actions.json` by the unit tests.
  An R4 ask there (a source checkout's guard file, a git replay onto a protected path) is a
  deny on OpenCode.

## Overrides

None of these reaches the permission layer: an environment switch may only tighten (ADR 004 D3).

| Variable | Effect |
|---|---|
| `PM_ALLOW_PROTECTED=1` | skip the generated-file rules (lockfiles, `.yarn/releases/`, shadcn UI, build output) for an edit the user asked for (same as the shell hook); never a `.github/workflows/` file (R4 `workflow.edit`, ADR 004 D10.5) and never a protected path |
| `TAMIRS_OPENCODE_GUARD=0` | disable the legacy guards (worktree, generated files, branch claims); the permission guard, the workflow rule and the protected paths stay on |
| `AGENT_CLAIM_DIR`, `AGENT_CLAIM_STALE_SECONDS`, `AGENT_CLAIM_ID` | claim store location, staleness window, this agent's identity (shared with the shell hooks) |
| `SUPERPOWERS_OBJECTIVE_ID`, `OBJECTIVES_ROOT`, `SUPERPOWERS_AGENT_WORKTREE_ROOT`, `SUPERPOWERS_ROLE` | the objective vocabulary `hooks/lib/objective-common.sh` reads |

## Checking it

```bash
node --test platforms/opencode/plugin/rules.test.mjs          # pure rules, no install
cd platforms/opencode/plugin && npm install && npm run check   # tsc --noEmit against @opencode/plugin 2.2.5
bash tests/test-opencode-v2.sh                                  # both, plus the generated adapters
```

`npm install` here fetches `@opencode/plugin` and the TUI peer packages
(`@opentui/core`, `@opentui/solid`, `solid-js`) for the type-check only; nothing is
bundled, and OpenCode resolves `@opencode/plugin` itself at runtime ("Discovered
plugins can import `@opencode/plugin/tui` directly; OpenCode resolves the package at
runtime"). `node_modules/` is gitignored.

## Verified and unverified

Measured on `@opencode/cli` 2.0.32 without a provider key: `opencode plugin list` and
`opencode debug agents` run offline (see `docs/user/install/opencode.md`). **Not**
yet measured live: that a `deny` set in `permission.hook("evaluate")` stops the edit
with the message shown to the agent, and that a throw in `shell.hook("create.before")`
stops the shell — both are the documented contract, neither has been exercised with
this plugin in a session with a provider. A probe plugin's evaluate-hook `deny` was
measured to hold under `--auto` on 2.2.5, with the `ask` auto-approved (spike O1,
`docs/engineering/research/permissions/spikes/cursor-gemini-opencode.md`), which is why
the permission layer only ever denies. `core/capabilities/platforms.json` records
`hooks` for OpenCode as `adapter` on that basis.
