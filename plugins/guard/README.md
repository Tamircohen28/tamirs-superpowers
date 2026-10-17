# tamirs-superpowers-guard

The in-process guard for [tamirs-superpowers](../../README.md): a plugin of Claude Code
function hooks ("mods", Claude Code 2.1.287+) that **holds** a destructive shell command
until you answer, and **refuses** a file write in the main checkout while an orchestration
objective is active. Claude Code and the Claude Desktop Code tab only.

## What it does

| Option (`/config`, on by default) | What happens |
|---|---|
| `hold_destructive_commands` | A `Bash` call whose command is a force push (`git push --force`, `-f`, `--force-with-lease`), `git branch -D`, `git worktree remove --force`, `git reset --hard`, `git clean -f`, `rm -rf` on anything that is not clearly a temp path, `git checkout -- .` or `git restore .` pauses in Claude Code's own question dialog, showing the command with **Proceed** and **Cancel**. Proceed runs it; Cancel refuses it with the guard's reason. Where nothing can draw the dialog (`claude -p`, the Agent SDK) the call goes through unheld and the debug log says so — a hold nobody can answer must not become a silent deny. |
| `deny_main_checkout_writes` | While an objective is active (`SUPERPOWERS_OBJECTIVE_ID`, or an `objective.json` with `status: active` under `.dev-files/objectives/`) and the session sits in the **main checkout** rather than a worktree, an `Edit`/`Write`/`MultiEdit`/`NotebookEdit` of a file inside the repository is refused, naming the objective's worktrees (`.agent-worktrees/<objective>/task-NNN` or `.../integration`). Writes under `.dev-files/` and inside any agent worktree pass. The same rule as the core plugin's `hooks/enforce-worktree-edits.sh`, which stays canonical. |

`/guard` answers with both options' current values, what each does, and what the guard has
held or refused this session.

## Why it is a separate plugin

The core plugin ships a mod too (`mod/register.tsx`), and keeps it to a footprint Anthropic's
plugin directory lists without review: it holds no tool call and denies nothing. A hook that
can refuse a tool call reads to the directory as `MOD_HOOKS_POLICY_EVENT`, and one that
answers for the person as `MOD_ANSWERS_PERMISSION` — both are holds on the listing. This
plugin does exactly those two things, so it lives in its own folder (`plugins/guard`), is
listed by the repository's own marketplace, and never enters the Claude-only distribution
the directory reads. Install it only if you want the in-process holds; the bash guards in
the core plugin run either way. Design and the directory's rules:
[`docs/engineering/architecture/guard-plugin.md`](../../docs/engineering/architecture/guard-plugin.md).

## Install

At the prompt of a terminal session, with the core plugin already installed:

```text
/plugin install tamirs-superpowers-guard --marketplace Tamircohen28/tamirs-superpowers
```

From a shell:

```text
claude plugin install tamirs-superpowers-guard --marketplace Tamircohen28/tamirs-superpowers
```

In the desktop app, where `/plugin` does not run: click **+** next to the prompt box, then
**Plugins**, **Add marketplace** with `Tamircohen28/tamirs-superpowers`, then **Add plugin**.

A plugin installed from a terminal at the user scope loads in the Desktop Code tab too. Both
options can be set from the shell with `claude plugin configure tamirs-superpowers-guard`.

## Develop and test

```bash
claude --plugin-dir plugins/guard                        # run it from this folder, hot-reloaded
claude plugin validate plugins/guard/.claude-plugin/plugin.json   # what the engine sees: hooks, calls, gating hooks
claude plugin test plugins/guard                         # hooks/guard.test.tsx against the engine
bash tests/test-guard-plugin.sh                          # shape, footprint, and both of the above when claude is on PATH
```

`claude plugin validate` lists both `tool.call` hooks as *gating hooks with `.catch`*. That
is expected and is the point: each carries `.catch(($, e, next) => next(e))`, so a hook that
throws or outruns its budget lets the call through rather than refusing it — the bash guards
are the binding layer, this one is the convenience on top.

## Files

| Path | What it is |
|---|---|
| `.claude-plugin/plugin.json` | Manifest: name, the two `userConfig` booleans, `types` |
| `hooks/hooks.json` | `{ "modules": ["./register.tsx"] }` — the one module, no bash hook |
| `hooks/register.tsx` | The hooks module |
| `hooks/guard.test.tsx` | Its tests (`claude plugin test`) |
| `types/index.d.ts` | The `$.state` contract |

The version is the core plugin's, synced from `plugin-version.json` by
`scripts/check-version-truth.sh --sync`; never edit it here.
