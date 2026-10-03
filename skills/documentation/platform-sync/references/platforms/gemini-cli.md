# Platform reference data — `gemini-cli`

Data consumed by the `platform-sync` engine (`references/analysis-protocol.md`).

- **Display name:** Gemini CLI
- **Platform:** `gemini` (display name "Gemini") in `core/capabilities/platforms.json`. The
  registry is rooted at the platform; surfaces live under `.platforms.gemini.surfaces`.
- **Registry id (surface):** `gemini_cli`, under `.platforms.gemini.surfaces.gemini_cli`;
  `gemini` in a skill's `compatibility` block (the frontmatter schema uses the shorter key).
  Filenames here follow the surface id with underscores rendered as hyphens: `gemini-cli.md`.
- **Sibling surface:** `gemini_code_assist` ("Gemini Code Assist") is **unverified** — a
  different host that does not install CLI extensions, so this repo's `.gemini/` mirror has
  no established install path there and has never been exercised on it. It carries no
  capabilities block. It is **not a target**: never audit it, never emit an improvement step
  for it, and never claim it does or does not work.
- **Status:** first-class target as of this refactor. Everything below is analysed the
  same way as every other target; nothing here is speculative-by-design. Where the
  capability registry marks a Gemini capability `unknown`, the engine must report it as
  unverified rather than assuming either direction.

## Detection signals

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Gemini config dir | `.gemini/` (any contents) | strong |
| Settings | `.gemini/settings.json` | strong |
| Context file | `GEMINI.md` at repo root | strong |
| Extension manifest | `gemini-extension.json` | strong |
| Commands | `.gemini/commands/**/*.toml` | medium |
| Agents file | `AGENTS.md` at repo root | medium — shared with Codex and OpenCode |

`AGENTS.md` alone is a medium signal: it means the repo has canonical agent policy Gemini
CLI could consume, which is itself worth reporting even if no `.gemini/` exists.

## Sources — P0 (fetch always; failure aborts this platform only)

| Topic | URL |
|---|---|
| GitHub releases (latest version tag) | https://github.com/google-gemini/gemini-cli/releases |
| Raw README (canonical feature list) | https://raw.githubusercontent.com/google-gemini/gemini-cli/main/README.md |

## Sources — P1

| Fetch when local config contains / lacks | URL |
|---|---|
| any `.gemini/` config, or settings to review | https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/configuration.md |
| `gemini-extension.json`, or extensions to propose | https://github.com/google-gemini/gemini-cli/blob/main/docs/extensions/index.md |
| `.gemini/commands/` | https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/commands.md |
| MCP servers declared elsewhere but not here | https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md |
| `GEMINI.md` or `AGENTS.md` present | https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/index.md |

## Sources — P2

| Topic | URL |
|---|---|
| Docs index | https://github.com/google-gemini/gemini-cli/tree/main/docs |
| Google Cloud Gemini CLI overview | https://cloud.google.com/gemini/docs/codeassist/gemini-cli |

Gemini CLI documentation lives in the repository. Paths move between releases: if a P1 URL
404s, fall back to the docs index (P2), locate the current path, and cite the URL you
actually fetched. Never cite a URL you did not fetch.

## Local config to read

| Path | What to note |
|------|--------------|
| `.gemini/settings.json` | Declared MCP servers, context file names, tool config |
| `GEMINI.md` | Context/instructions — and whether it duplicates `AGENTS.md` |
| `gemini-extension.json` | Extension name, version, declared commands and MCP servers |
| `.gemini/commands/**/*.toml` | Custom command definitions |
| `AGENTS.md` | Canonical agent policy available to inherit |
| `skills/**/SKILL.md` | Portable Agent Skills the target could consume |

## Feature-scan areas

- **Context-file duplication** — a `GEMINI.md` that restates `AGENTS.md` verbatim is
  duplicated canonical source (non-negotiable #2). Recommend a pointer, not a copy.
- **Extension manifest** — a repo distributing to other targets via manifests with no
  `gemini-extension.json` has an unreachable target. Verify against the fetched extension
  docs before recommending a specific schema.
- **MCP** — servers declared for other targets but absent from `.gemini/settings.json`.
- **Custom commands** — slash commands shipped for other targets with no
  `.gemini/commands/*.toml` equivalent.
- **Skills** — how the installed version discovers Agent Skills, if at all. Confirm from
  the fetched docs; if the release under analysis does not document skill discovery, say
  so plainly instead of proposing a skills layout.

## Version detection

Declared: `gemini-extension.json` → `version`, else
`targets.gemini.validated_against` in `docs/engineering/build-and-release/platform-targets.json`,
else `project-only`.
Latest: newest tag on the releases feed.

## Capability boundaries

Gemini CLI has no Claude-style `hooks.json`, no plugin-declared statusline, and no Claude
plugin marketplace. Consult the capability registry entry for the `gemini_cli` **surface**
before porting any feature from another target:

```bash
jq -r --arg p gemini_cli '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)
     | .capabilities | to_entries[] | "\(.key): \(.value.status)"' core/capabilities/platforms.json
```

Honour `unknown` as unknown — report it as unverified rather than recommending or ruling out
the feature. That is a *measured* row that came back inconclusive, and it is a different
thing from the `gemini_code_assist` surface, which has no rows at all because it was never
measured.
