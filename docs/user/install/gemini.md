# Install on Gemini CLI

**Platform:** Gemini. **Surface:** Gemini CLI — registry id `gemini_cli`. This guide covers
the CLI and nothing else.

> **Who still has Gemini CLI.** Google retired Gemini CLI for consumer tiers on **2026-06-18**:
> Google AI Pro/Ultra subscribers and free individual Code Assist users were moved to
> **Antigravity CLI** (`agy`), which has its own plugin format and its own guide,
> [antigravity.md](antigravity.md). Gemini CLI keeps serving **enterprise Code Assist
> Standard/Enterprise licences** and **paid Gemini API / Agent Platform keys**, and the
> open-source repo keeps shipping weekly stables (0.64.0 on 2026-10-13). This adapter keeps
> serving those users; nothing below is deprecated. Gemini's other surface, **Gemini Code Assist**, is **unverified**:
it is a different host that does not install CLI extensions, so the generated `.gemini/`
mirror described below has no established install path there and has never been exercised on
it. It has no install guide and no capability claims in either direction — see
[platform differences](../platform-differences.md#unverified-surfaces).

| | |
|---|---|
| **Validated against** | Gemini CLI **0.66.0** — `gemini --version` → `0.66.0`; `gemini extensions validate .` → `Extension . has been successfully validated.`; a distribution carrying the generated `hooks/hooks.json` and `policies/` installs with `gemini extensions install <path> --consent --skip-settings` and lists its MCP server and keychain setting; every `.gemini/skills/` and `.agents/skills/` symlink resolves (0 broken). Hook **firing** is not yet observed — see [Hooks and policies](#hooks-and-policies) |
| **Minimum supported** | **0.55.1** — the oldest version this adapter was actually exercised on |
| **Extension manifest** | `gemini-extension.json` (repo root) |
| **Context file** | `.gemini/GEMINI.md` |
| **Generated adapter** | `.gemini/skills/` · `.gemini/agents/` — built by `scripts/build-gemini-extension.sh`; `.agents/skills/` — `scripts/build-agents-skills.sh`; `platforms/gemini/hooks.json` · `platforms/gemini/policies/` — `scripts/build-gemini-hooks.sh` |
| **Hooks** | shipped as `hooks/hooks.json` in the Gemini distribution, every canonical hook run through `hooks/gemini-wrap.sh` |
| **Policies** | `policies/tamirs-superpowers.toml` — five deny-only rules (force push, `branch -D`, lockfiles, `.yarn/releases/`, `.github/workflows/`) |
| **Token** | manifest `settings[]` entry `GITHUB_PERSONAL_ACCESS_TOKEN`, `sensitive: true` (OS keychain) — set with `gemini extensions config tamirs-superpowers GITHUB_PERSONAL_ACCESS_TOKEN` |
| **Adapter metadata** | [`platforms/gemini/adapter.yaml`](../../../platforms/gemini/adapter.yaml) |
| **Official docs** | [Extensions reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/extensions/reference.md) · [Agent Skills](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md) · [Sub-agents](https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md) · [Hooks](https://geminicli.com/docs/hooks/) · [Policy engine](https://geminicli.com/docs/reference/policy-engine.md) |

Check your version:

```bash
gemini --version
```

## Read this first: skills come from the mirror, not the extension

On every other target, installing this plugin installs everything. On Gemini it takes two commands, and it is worth understanding why before you install rather than after.

Gemini CLI discovers skills **exactly one level below a skills root** — `<root>/skills/<name>/SKILL.md`, no deeper. This repo's canonical layout is `skills/<domain>/<name>/SKILL.md`, two levels down, and an extension installed from a git URL roots at the repo root. Pointed at the canonical tree, Gemini finds **zero** skills and says nothing about it.

Flattening the canonical tree is not an option — Claude Code and OpenCode both discover it recursively, so flat entries beside the domains would resolve every skill twice under two names. Instead the repo ships a **generated flat mirror** at `.gemini/skills/`, one symlink per skill, built by `scripts/build-gemini-extension.sh` and drift-checked in CI. Because they are symlinks there is still exactly one copy of every skill in the repo.

That mirror is what you install from, and it is why the skills command is one line rather than seven.

`gemini extensions validate` will not tell you any of this. It parses the manifest and stops; it reports success on an extension whose context file does not exist. Use `scripts/check-gemini-adapter.sh` for anything real.

## Method A — install from this repo

```bash
gemini extensions install https://github.com/Tamircohen28/tamirs-superpowers --consent
gemini skills install   https://github.com/Tamircohen28/tamirs-superpowers --path .gemini/skills --consent
```

The first command gives you the context file, the `github` MCP server and the token setting. The second gives you every skill — `--path .gemini/skills` points at the flat mirror, which is the one shape Gemini's one-level scan can read (`--path .agents/skills` is the same tree under the name Gemini's `.agents` alias and Antigravity read).

Three prompts can appear on the first command; the first two are new since this guide was last written, the third since 0.66.0:

- The **extension consent** prompt (0.60.0+) lists what the extension brings: the context file, the MCP server, and — because the shipped tree carries a hooks file — the line `⚠️  This extension contains Hooks which can automatically execute commands.` `--consent` acknowledges it non-interactively.
- The **trust** prompt (0.66.0, observed installing a local path): after `--consent`, `Do you want to trust this folder and continue with the installation? [y/N]`. No flag skips it, so an install run with no terminal (CI, a script with stdin closed) waits forever; answer `y` on stdin when you must script it.
- The **settings** prompt asks for `GITHUB_PERSONAL_ACCESS_TOKEN` and stores it in the OS keychain. Answer it, or pass `--skip-settings` and set it later:

  ```bash
  gemini extensions config tamirs-superpowers GITHUB_PERSONAL_ACCESS_TOKEN
  ```

  Until it is set, `gemini extensions list` shows `GITHUB_PERSONAL_ACCESS_TOKEN: [not set]` and the `github` server refuses to start; nothing else is affected.

**Hooks need the release tree, not the bare git URL.** An extension installed from the git URL roots at the repo root, where `hooks/hooks.json` is the *Claude Code* file: its commands name `${CLAUDE_PLUGIN_ROOT}`, which Gemini never exports, so none of them can run there (and the Claude-only events in it are simply ignored). The generated Gemini hooks file lives at `platforms/gemini/hooks.json` in the repo and at `hooks/hooks.json` only in the Gemini distribution — the `tamirs-superpowers-<version>-gemini.tar.gz` asset on each GitHub release, or `bash scripts/build-dist.sh <dir> --target gemini` from a clone. Install that tree from its local path:

```bash
tar -xzf tamirs-superpowers-<version>-gemini.tar.gz -C ~/tamirs-superpowers-gemini
gemini extensions install ~/tamirs-superpowers-gemini --consent
```

That is exactly the shape measured on 0.64.0 (see the table above). Context, MCP and the token setting work either way; only hooks and policies depend on which tree you install.

`--path skills` finds nothing, and neither does omitting `--path`: both land on the two-level canonical tree. Drop `--consent` if you would rather read the third-party-code warning and accept it interactively.

## Pin a release instead of tracking the default branch

Both install commands track the repo's default branch by default, so every reinstall picks up
whatever has landed since. `--ref` takes any git ref — a tag, branch or commit — which is how
you get a stable channel:

```bash
gemini extensions install https://github.com/Tamircohen28/tamirs-superpowers \
  --ref v4.5.0 --consent
gemini skills install     https://github.com/Tamircohen28/tamirs-superpowers \
  --ref v4.5.0 --path .gemini/skills --consent
```

Two related flags, both verified on **0.60.0**:

| Flag | Effect |
|---|---|
| `--ref <git ref>` | Install from that tag/branch/commit instead of the default branch |
| `--auto-update` | Let Gemini update this extension on its own — the opposite trade to `--ref` |
| `--pre-release` | Opt into pre-release versions |

`--ref` and `--auto-update` pull in opposite directions: pinning a tag and then enabling
auto-update means the pin is the thing that moves. Pick one. For a reproducible machine —
CI, a shared box, anything you want to be able to roll back — pin the tag and update
deliberately.

This repo's tags follow `plugin-version.json`, so `--ref v<version>` matches the version the
README badge shows.

## Method B — local clone (contributors)

With the repo as your working directory, **the skills need no install at all** — `.gemini/skills/` is a workspace skills root, so Gemini reads all of them in place, along with the sub-agents in `.gemini/agents/`:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git ~/src/tamirs-superpowers
cd ~/src/tamirs-superpowers
gemini skills list --all        # every skill, no install step
```

Trust the folder when Gemini asks. An untrusted folder is the one failure mode that looks exactly like a broken mirror: workspace skills and agents are skipped, and the only clue is a line reading `Skipping project agents due to untrusted folder`.

To get the extension (context + MCP) from a clone, `link` points Gemini at your working tree so edits are live with no reinstall:

```bash
gemini extensions link ~/src/tamirs-superpowers --consent
```

To use the skills from a clone while working *elsewhere*, install from the clone path:

```bash
gemini skills install ~/src/tamirs-superpowers --path .gemini/skills --consent
```

## Regenerating the mirror

`.gemini/skills/` and `.gemini/agents/` are **generated and committed**, in the same pattern as `.opencode/agents/`. Never edit them by hand — edit `skills/` or `agents/` and rebuild:

```bash
make gemini-extension          # regenerate
make gemini-extension-check    # fail on drift (runs in CI)
```

The generator refuses to produce an empty mirror and fails loudly if two domains ever ship the same skill name, since Gemini's skill namespace is flat.

## Verify

```bash
gemini extensions list
gemini skills list --all
```

`gemini extensions list` should show the extension enabled, with its context file resolved:

```
✓ tamirs-superpowers (2.0.1)
 Enabled (User): true
 Context files:
  /Users/you/src/tamirs-superpowers/.gemini/GEMINI.md
```

`gemini skills list --all` should list every skill in the repo — and no `demo` or `example-skill`. Those two are gold fixtures; they sit deeper than the generator's two-level glob, so they are never mirrored. If they appear, a `--path` argument pointed at `skills/repo/_contract/fixtures`.

MCP:

```bash
gemini mcp list
```

The `github` server runs `scripts/github-mcp.sh`, which expects its token in `GITHUB_PERSONAL_ACCESS_TOKEN`. On Claude Code that variable comes from the plugin's sensitive `github_token` option; on Gemini it comes from the extension's `settings[]` entry of the same name — `sensitive: true`, so the value lives in the OS keychain and is obfuscated in the UI, and `envVar` names the variable the server receives. Set or change it with:

```bash
gemini extensions config tamirs-superpowers GITHUB_PERSONAL_ACCESS_TOKEN
gemini extensions config tamirs-superpowers GITHUB_PERSONAL_ACCESS_TOKEN --scope workspace   # per workspace
```

Measured on 0.64.0: a setting's value reaches the extension's **MCP servers** and nothing else — hooks do not see it, which is the right boundary (no hook here needs it). Exporting `GITHUB_PERSONAL_ACCESS_TOKEN` in the shell still works for a linked clone. No token is stored in the manifest or anywhere in the repo.

## Hooks and policies

The Gemini distribution ships two guard layers that the git-URL install does not (see
[Method A](#method-a--install-from-this-repo)):

**`hooks/hooks.json`** — generated from the canonical Claude file by
`scripts/build-gemini-hooks.sh`, never written by hand. Gemini reads an extension's hooks
from this one path and only its `hooks` object (measured on 0.64.0), so the generated file
is what the shipped tree carries at that path. The mapping:

| Canonical event | Gemini event | Matcher |
|---|---|---|
| `PreToolUse` (`Edit\|Write\|…`) | `BeforeTool` | `^(replace\|write_file)$` |
| `PreToolUse` (`Bash\|Shell`) | `BeforeTool` | `^(run_shell_command)$` |
| `PostToolUse` | `AfterTool` | same rewrite |
| `UserPromptSubmit` | `BeforeAgent` | — |
| `Stop` | `AfterAgent` | — |
| `PreCompact` | `PreCompress` | — |
| `SessionStart`, `SessionEnd`, `Notification` | same name | — |
| `WorktreeCreate`, `WorktreeRemove`, `DirectoryAdded`, `StopFailure`, `SubagentStop` | *dropped* | Gemini has no such event |

Every command runs the **unmodified** canonical hook through `hooks/gemini-wrap.sh`, which
rewrites the payload on the way in (`write_file`→`Write`, `replace`→`Edit`,
`run_shell_command`→`Bash`, its `dir_path` into `cwd`) and the answer on the way out
(`{"decision":"deny","reason":…}` for a block, `{}` for an allow, `additionalContext` under
the event's own `hookSpecificOutput` where Gemini defines it and `systemMessage` elsewhere).
Timeouts are converted to milliseconds; Claude's `onFailure: block` has no Gemini field, so
every guard is **fail-open** here — a guard that crashes or times out lets the action through,
as on Codex. Manage them in a session with `/hooks panel`, `/hooks enable <name>`,
`/hooks disable <name>` (names are the script stems: `enforce-worktree-edits-write`,
`guard-sensitive-files-shell`, …).

What is and is not measured: on 0.64.0 the extension **installs and loads** with the file
in place; a hook **firing** has not been observed, because that needs an authenticated
interactive session, so the capability registry still says `unknown` and this guide does not
claim more. `gemini hooks migrate --from-claude` is the host's own translator if you prefer
to wire the Claude file into your `settings.json` yourself; it copies timeouts unconverted.

**`policies/tamirs-superpowers.toml`** — five `[[rule]]`s, generated from
[`platforms/gemini/policies.source.json`](../../../platforms/gemini/policies.source.json),
every one `decision = "deny"`: `git push --force`/`-f` (`--force-with-lease` is allowed),
`git branch -D`, and `write_file`/`replace` onto lockfiles, `.yarn/releases/` and
`.github/workflows/`. Gemini honours only deny/ask in an extension policy, so this layer can
narrow, never widen, and it holds even with every hook disabled. What it cannot express —
a push to a branch another agent holds, worktree isolation, gitignored build output, the
`PM_ALLOW_PROTECTED=1` override — stays with the hooks; the source file lists each. To
override a rule, add a higher-tier rule in `~/.gemini/policies/*.toml`.

## Update

Extension:

```bash
gemini extensions update tamirs-superpowers
```

Skills do not update in place — reinstall from the mirror:

```bash
gemini skills uninstall retro
gemini skills install https://github.com/Tamircohen28/tamirs-superpowers --path .gemini/skills --consent
```

A linked extension (Method B) needs no update command; `git pull` is enough.

> Extension management only takes effect after restarting the CLI session — that includes `install`, `update`, `enable`, and `disable`.

## Uninstall

```bash
gemini extensions uninstall tamirs-superpowers
gemini skills uninstall <name>          # one per skill; there is no bulk removal
```

## Machine-level setup

The extension and skills mirror cover this repo. Global rules in `~/.gemini` are a separate,
optional step:

```bash
bash scripts/setup.sh plan  --targets gemini    # writes nothing
bash scripts/setup.sh apply --targets gemini
bash scripts/setup.sh remove --targets gemini
```

| Module | Writes | What it does |
|---|---|---|
| `gemini-md` | `~/.gemini/GEMINI.md` | Renders `core/global-rules.md` inside `>>> tamirs-superpowers >>>` markers |
| `settings` | `~/.gemini/settings.json` | Asserts `context.fileName` = `["GEMINI.md", "AGENTS.md"]` and nothing else |

That one key is why a rule written once is picked up whichever CLI you reach for. `hooks` and
MCP entries in `settings.json` are untouched, so wiring another tool wrote survives.

`plan` writes nothing and is the default when there is no terminal, so a hook or CI run can
never adopt anything silently. `apply` shows a diff and asks per change, defaulting to
**No**. Re-running is a no-op — idempotence is a content comparison. Full reference:
[setup](../setup.md) · [platform setup](../platform-setup.md).

## What does not port

Everything in this table was measured against 0.55.1, not inferred. `unsupported` means it was tried and it failed.

| Feature | Status on Gemini | What actually happens |
|---------|------------------|-----------------------|
| Context (`.gemini/GEMINI.md`) | ✅ | `contextFileName` accepts a subpath; loads on every session |
| MCP (`github`) | ✅ | Declared in the manifest with `${extensionPath}`, so it resolves wherever the extension lands |
| Skills | ✅ via generated mirror | Extension `skills/` discovery is one level deep and canonical skills are two, so `.gemini/skills/` is a generated flat symlink mirror. One install command, or free in-workspace |
| Sub-agents | ✅ via generated mirror | `.gemini/agents/*.md` is generated with `tools` as an array of *Gemini* tool names. Verified: all agents load with no errors. `model:` is deliberately omitted — a Claude alias like `sonnet` passes validation and then fails at invocation |
| Hooks | ✅ shipped (firing unverified) | A generated `hooks/hooks.json` in the Gemini distribution — see [Hooks and policies](#hooks-and-policies). Loads on 0.64.0; firing not yet observed, so the registry row stays `unknown`. Fail-open: no `onFailure` equivalent |
| Policies | ✅ deny-only | `policies/tamirs-superpowers.toml`, generated; five deny rules that hold even with hooks disabled |
| Token setting | ✅ keychain | `settings[]` entry, `sensitive: true`; reaches the MCP server, not hooks |
| Custom commands | ❌ not shipped | Gemini reads `commands/*.toml` at the extension root; this repo ships no `commands/` directory on any target |
| Statusline | ❌ | No extension-declared statusline |
| Marketplace | ❌ | Gemini installs from a Git URL; there is no catalog to register with |

### One known wart, if you install the extension from a git URL

The generated `.gemini/agents/` adapters load cleanly. But an extension installed from a git URL roots at the **repo root**, so Gemini also reads the *canonical* Claude-shaped `agents/` sitting there, and prints one error per file on every invocation:

```
[ExtensionManager] Error loading agent from tamirs-superpowers: Failed to load agent from .../agents/security-reviewer.md: Validation failed: Agent Definition:
tools.0: Invalid tool name
```

Noisy, not fatal — the extension still loads, skills still work, and the sub-agents you actually want come from `.gemini/agents/`. There is no fix available from this side: `gemini extensions install` has no subdirectory flag, and no manifest field relocates `agents/`. It is called out because the message names this extension and reads like a broken install.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `gemini skills list --all` shows none of this repo's skills | The extension does not carry them. Run the second command in Method A, or trust the folder if you are working inside a clone |
| `No valid skills found ... at path "skills"` | Expected — `--path` scans one level. Pass `.gemini/skills`, not `skills` |
| `Skipping project agents due to untrusted folder` | Trust the folder. Until you do, workspace skills and agents are silently skipped |
| `.gemini/ is out of sync` in CI | The mirror is generated. Run `make gemini-extension` and commit the result |
| `extensions validate` passes but nothing works | It only checks the manifest. Run `bash scripts/check-gemini-adapter.sh` |
| `Error loading agent ... Invalid tool name` naming `agents/` | Known and documented above — the canonical Claude agents at the extension root. The working sub-agents are in `.gemini/agents/`. Nothing to fix |
| `has missing settings: GITHUB_PERSONAL_ACCESS_TOKEN` at install, or `[not set]` in `extensions list` | Run `gemini extensions config tamirs-superpowers GITHUB_PERSONAL_ACCESS_TOKEN`; the value goes to the keychain and the MCP server |
| MCP `github` fails on first call | Set the setting above (or, for a linked clone, export `GITHUB_PERSONAL_ACCESS_TOKEN` in the shell that starts `gemini`); the server stores nothing and reads nothing else |
| Hooks never run | You installed from the git URL, whose `hooks/hooks.json` is the Claude file. Install the Gemini release tree (Method A) — or, to confirm a hook ran at all, `/hooks panel` lists the loaded names |
| `Skill conflict detected: "<name>" from .../.agents/skills/... is overriding the same skill from .../.gemini/skills/...` (one line per skill, in a clone) | Expected and harmless: the two generated mirrors name the same skills and `.agents/skills/` wins by precedence, so each loads once (measured: one `[Enabled]` line per canonical skill, no error). The warning is the price of shipping the tree every other host reads |
| Changes to a linked clone have no effect | Restart the CLI session — extension state is read at startup |
| Fixture skills `demo` / `example-skill` appear | A `--path` pointed into `skills/repo/_contract/fixtures`. Uninstall them and use the domain paths |

## Validating the adapter

```bash
make gemini-extension-check                    # the generated mirror matches skills/ and agents/
bash scripts/build-gemini-hooks.sh . --check   # hooks.json and policies match their sources
bash scripts/build-agents-skills.sh . --check  # .agents/skills matches skills/
bash scripts/check-gemini-adapter.sh           # manifest, paths, version truth, mirror completeness, no Node deps
bash tests/test-gemini-adapter.sh              # behavior tests
bash tests/test-gemini-hooks.sh                # generator drift, generated shape, wrapper translations, policy regexes
make validate                                  # the full repo gate
```

`check-gemini-adapter.sh` runs with or without the CLI installed — it skips the `gemini extensions validate` step with a message rather than failing, so CI stays honest on a runner that has no Gemini.
