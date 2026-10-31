# OpenCode 2 plugin — tamirs-superpowers

The OpenCode half of what `hooks/` and `mod/` do on Claude Code. One plugin
directory, two entrypoints, loaded by path from this repo's
[`opencode.json`](../../../opencode.json) (`"plugins": ["./platforms/opencode/plugin"]`)
— OpenCode 2 resolves `index.ts` as the server plugin and `tui.ts` as the TUI plugin
from the same directory, the layout its own discovery uses for
`.opencode/plugins/<name>/`.

| File | Runs in | Does |
|------|---------|------|
| `index.ts` → `guard.ts` | the OpenCode server (`@opencode/plugin`) | `ctx.permission.hook("evaluate")`: denies an `edit` to the main checkout while an objective is active, and a write to a protected path (lockfiles, `.github/workflows/`, `.yarn/releases/`, shadcn `components/ui/`, gitignored build output); on `shell`, refuses a force push and a push to a branch another agent's live claim holds, and applies the same path rules to redirect/`tee`/`sed -i`/`cp`/`mv` targets. `ctx.shell.hook("create.before")` throws the same reasons as a backstop for shells created outside the permission flow. |
| `tui.ts` → `tui.tsx` | the terminal client (`@opencode/plugin/tui`) | `prompt.footer.status`: context fill of the last model step, session cost, objective progress. `session.panel` + `/objective`: the objective's task rows. |
| `rules.ts` | anywhere | The pure decision functions both of the above call. No I/O, no imports — unit-tested with plain Node. |
| `state.ts` | both | Git-root resolution (a linked worktree's `.git` file → main checkout) and the `.dev-files/objectives/<id>/` readers. |

The decisions mirror `hooks/enforce-worktree-edits.sh`, `hooks/guard-sensitive-files.sh`
and `hooks/protect-other-branches.sh` (claim store: `hooks/lib/agent-claim.sh`, the same
`~/.agent-work-claims/<key>.json` files, so an OpenCode session and a Claude Code
session see each other's branch claims). What is deliberately *not* mirrored, and
why, is in the header of `guard.ts`. What the status line cannot show (rate-limit
windows: OpenCode documents no such payload) is in the header of `tui.tsx`.

## Overrides

| Variable | Effect |
|---|---|
| `PM_ALLOW_PROTECTED=1` | skip the protected-path rules for an edit the user asked for (same as the shell hook) |
| `TAMIRS_OPENCODE_GUARD=0` | disable the server guard entirely |
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
stops the shell — both are the documented contract, neither has been exercised in a
session with a provider. `core/capabilities/platforms.json` records `hooks` for
OpenCode as `adapter` on that basis.
