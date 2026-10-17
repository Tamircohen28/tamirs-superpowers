# Generated adapters

Every file in this repository that a script writes from a canonical source, with the
source, the generator, and the command that fails CI when the two disagree.

The rule is the same for every row: **edit the source, regenerate, never the output.**
A generated file opens with a `GENERATED FILE — DO NOT EDIT` marker naming its source,
its generator and the `make` target that rebuilds it. A hand edit to the output survives
exactly until the next regenerate, and fails the `--check` gate before that — the gate
regenerates into a temp dir and diffs, so it never writes to the working tree.

Why generate rather than hand-sync is covered once in
[`adapter-contract.md`](adapter-contract.md) and [`overview.md`](overview.md): the
platform files are thin adapters, and a restated rule or a copied agent drifts. Each
generator's own header says *why that platform needs a translation at all* (OpenCode
turns an allowlist into explicit denies; Gemini reads skills one level deep; Codex has no
plugin route for agents), so this page does not repeat those arguments — it is the
inventory.

## Inventory

| Output | Source | Generator | Regenerate | Check (CI) |
|--------|--------|-----------|------------|------------|
| `.gemini/skills/<name>` (symlinks, flat) | `skills/<domain>/<name>/` | `scripts/build-gemini-extension.sh` | `make gemini-extension` | `make gemini-extension-check` |
| `.gemini/agents/<name>.md` | `agents/<name>.md` | `scripts/build-gemini-extension.sh` | `make gemini-extension` | `make gemini-extension-check` |
| `.opencode/agents/<name>.md` (OpenCode 2: `mode: subagent`, `permissions:` ruleset) | `agents/<name>.md` | `scripts/build-opencode-agents.sh` | `make opencode-agents` | `make opencode-agents-check` |
| `.opencode/commands/<skill>.md` (OpenCode 2: `subagent: false`) | `skills/<domain>/<skill>/SKILL.md` | `scripts/build-opencode-commands.sh` | `make opencode-commands` | `make opencode-commands-check` |
| `.cursor/commands/<skill>.md` | `skills/<domain>/<skill>/SKILL.md` | `scripts/build-cursor-commands.sh` | `make cursor-commands` | `make cursor-commands-check` |
| `.cursor/rules/<rule>.mdc` (generated entries) | `rules/dev/<rule>.md` + [`platforms/cursor/rules.map.json`](../../../platforms/cursor/rules.map.json) | `scripts/build-cursor-rules.sh` | `make cursor-rules` | `make cursor-rules-check` |
| `.codex/agents/<name>.toml` | `agents/<name>.md` | `scripts/build-codex-agents.sh` | `make codex-agents` | `make codex-agents-check` |
| `platforms/codex/hooks.json` | `hooks/hooks.json` (Codex event subset, no `modules`) | `scripts/build-codex-hooks.sh` | see the script's `--help` | its `--check` |
| platform manifests (`.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, root `plugin.json`) | `plugin-version.json` + `platforms/manifest.source.json` | `scripts/build-manifests.sh` | see the script's `--help` | its `--check` |
| `platforms/gemini/hooks.json` | `hooks/hooks.json` (Gemini event subset, matchers on Gemini tool names, every command through `hooks/gemini-wrap.sh`, timeouts in ms, no `onFailure`) | `scripts/build-gemini-hooks.sh` | `bash scripts/build-gemini-hooks.sh .` | its `--check` (`tests/test-gemini-hooks.sh` plants drift) |
| `platforms/gemini/policies/tamirs-superpowers.toml` | [`platforms/gemini/policies.source.json`](../../../platforms/gemini/policies.source.json) (deny-only `[[rule]]`s) | `scripts/build-gemini-hooks.sh` | `bash scripts/build-gemini-hooks.sh .` | its `--check` |
| `platforms/antigravity/plugin.json`, `platforms/antigravity/mcp_config.json` | `.claude-plugin/plugin.json` + the `antigravity` section of `platforms/manifests.source.json` | `scripts/build-antigravity-plugin.sh` | `bash scripts/build-antigravity-plugin.sh .` | its `--check` (`tests/test-antigravity-adapter.sh` plants drift) |
| `.agents/skills/<name>` (symlinks, flat) | `skills/<domain>/<name>/` | `scripts/build-agents-skills.sh` | `bash scripts/build-agents-skills.sh .` | its `--check` (`tests/test-agents-skills.sh` plants drift) |

The last two rows are being added in the same release as this page (the V5 Phase 1
"one-source build" in
[`../roadmap/v5-upgrade-plan.md`](../roadmap/v5-upgrade-plan.md)); their `make` targets
are named by those scripts' own headers once they land, and the row here is the pointer,
not the contract.

Every `--check` target above is wired into `make validate`, so a stale adapter fails the
same gate as a broken test. `tests/test-generators.sh` goes one step further for the two
newest generators: it plants drift in a scratch copy and asserts the `--check` fails,
because a drift gate that passes on a drifted tree is worse than none.

## What each generator deliberately does not emit

The translations are lossy on purpose; the omissions are the contract.

- **Model names, anywhere.** `build-codex-agents.sh` never writes `model` or
  `model_reasoning_*`, and `build-cursor-rules.sh` has no model field to write. The
  canonical `model:` is a Claude alias with no meaning on another host, and a pinned
  model in a shipped file is a claim nothing here re-validates. (`build-opencode-agents.sh`
  maps the alias to a provider-prefixed id because OpenCode requires one; that map is
  re-checked by hand on every pin move, as its header records.)
- **Full copies of a rule.** A Cursor `.mdc` is frontmatter plus a short pointer summary
  from the map, never the body of `rules/dev/<rule>.md`. The five adapters with no
  `rules/dev` source (`commit-conventions`, `hooks-guide`, `plugin-structure`,
  `skills-guide`, `skill-frontmatter`) are `manual: true` in the map: verified to exist
  and open with frontmatter, never rewritten, never pruned.
- **Undocumented capability keys.** `build-codex-agents.sh` emits `[features]
  shell_tool = false` for an agent whose canonical `tools:` allowlist has no Bash, and
  nothing else: `apps`, `plugins`, `memories` and `request_permissions_tool` are
  documented Codex reductions, but nothing in the canonical frontmatter maps onto them,
  so they are not guessed at. `build-opencode-agents.sh` likewise emits only OpenCode 2
  Core permission actions (`read edit glob grep shell subagent skill question webfetch
  websearch external_directory`) — never the deprecated V1 keys `bash`/`task`/
  `doom_loop`/`lsp`/`list`/`todowrite` — and never an `allow` rule, because a rule
  appended after OpenCode's base policy overrides the host's own `.env` asks (last
  match wins). Enforced by `scripts/check-opencode-permission-keys.sh` and
  `tests/test-opencode-v2.sh`.

## Adding a generator

1. Put the generator in `scripts/build-<target>-<thing>.sh` with the shared contract:
   `[repo-root] [--check]`, `-h`/`--help`, unknown flags fail fast, exit `1` on drift,
   `2` on a malformed source, and a header that says *why* the translation exists
   ([`rules/dev/user-facing-script-standards.md`](../../../rules/dev/user-facing-script-standards.md)).
2. Open every output with the generated-file marker naming source, generator and the
   regenerate command; the marker is what `tests/test-*-adapter.sh` and
   `tests/test-generators.sh` key on to tell generated from manual.
3. Prune outputs whose source is gone in a normal run, and report them as drift in
   `--check`.
4. Add `make <thing>` and `make <thing>-check`, put the check in `validate`, and add a
   row above.
5. Plant drift in a scratch copy and assert `--check` fails — `tests/test-generators.sh`
   is the pattern.
