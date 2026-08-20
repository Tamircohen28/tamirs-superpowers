# Install on Gemini CLI

**Platform:** Gemini. **Surface:** Gemini CLI — registry id `gemini_cli`. This guide covers
the CLI and nothing else. Gemini's other surface, **Gemini Code Assist**, is **unverified**:
it is a different host that does not install CLI extensions, so the generated `.gemini/`
mirror described below has no established install path there and has never been exercised on
it. It has no install guide and no capability claims in either direction — see
[platform differences](../platform-differences.md#unverified-surfaces).

| | |
|---|---|
| **Validated against** | Gemini CLI **0.55.1** |
| **Minimum supported** | **0.55.1** — the oldest version this adapter was actually exercised on |
| **Extension manifest** | `gemini-extension.json` (repo root) |
| **Context file** | `.gemini/GEMINI.md` |
| **Generated adapter** | `.gemini/skills/` · `.gemini/agents/` — built by `scripts/build-gemini-extension.sh` |
| **Adapter metadata** | [`platforms/gemini/adapter.yaml`](../../../platforms/gemini/adapter.yaml) |
| **Official docs** | [Extensions reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/extensions/reference.md) · [Agent Skills](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md) · [Sub-agents](https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md) |

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

The first command gives you the context file and the `github` MCP server. The second gives you every skill — `--path .gemini/skills` points at the flat mirror, which is the one shape Gemini's one-level scan can read.

`--path skills` finds nothing, and neither does omitting `--path`: both land on the two-level canonical tree. Drop `--consent` if you would rather read the third-party-code warning and accept it interactively.

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

`.gemini/skills/` and `.gemini/agents/` are **generated and committed**, in the same pattern as `.opencode/agent/`. Never edit them by hand — edit `skills/` or `agents/` and rebuild:

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

The `github` server runs `scripts/github-mcp.sh`, which takes its token from `gh auth token`. No token is stored in the manifest. Run `gh auth login` first, or the server exits with an authentication error on its first call.

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
| Hooks | ❌ none shipped | **This adapter ships no hooks, by design** — that is a statement about this adapter, not a verdict on Gemini's hooks, which were never tested. Gemini's runtime events — read from the shipped 0.55.1 bundle, not the docs — are `BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`, `BeforeModel`, `AfterModel`, `BeforeToolSelection`, `SessionStart`, `SessionEnd`, `Notification`, `PreCompress`. Three of those (`SessionStart`, `SessionEnd`, `Notification`) are shared with Claude, but this repo's `PreToolUse`, `PostToolUse`, `UserPromptSubmit` and `Stop` handlers name events Gemini does not have, and its `DirectoryAdded`/`WorktreeCreate`/`WorktreeRemove` guards have no counterpart at all — so the worktree guards would need real translation nobody has done. Do not be reassured if you drop the Claude file in yourself: Gemini silently accepts both the Claude shape *and* a completely invented event name, so it loading proves nothing about it firing. `gemini hooks migrate --from-claude` exists if you want to translate your own |
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
| MCP `github` fails on first call | `gh auth login`. The server reads `gh auth token` at startup and stores nothing |
| Changes to a linked clone have no effect | Restart the CLI session — extension state is read at startup |
| Fixture skills `demo` / `example-skill` appear | A `--path` pointed into `skills/repo/_contract/fixtures`. Uninstall them and use the domain paths |

## Validating the adapter

```bash
make gemini-extension-check              # the generated mirror matches skills/ and agents/
bash scripts/check-gemini-adapter.sh   # manifest, paths, version truth, mirror completeness, no Node deps
bash tests/test-gemini-adapter.sh      # behavior tests
make validate                          # the full repo gate
```

`check-gemini-adapter.sh` runs with or without the CLI installed — it skips the `gemini extensions validate` step with a message rather than failing, so CI stays honest on a runner that has no Gemini.
