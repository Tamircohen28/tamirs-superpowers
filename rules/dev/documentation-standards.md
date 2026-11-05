# Documentation standards

**Applies when:** writing or editing any Markdown a human reads — `README.md`, `docs/**` — or drawing a diagram anywhere in the tree, including inside a skill, a reference file or a generated artifact.
**Which list:** configurable policy. The footer texts, the URLs and the human-facing globs are data in [`config/docs/doc-standards.json`](../../config/docs/doc-standards.json); the shape of the standard — themed Mermaid, one footer, one checker — is not negotiated per file.
**Enforced by:** [`scripts/check-doc-standards.sh`](../../scripts/check-doc-standards.sh), as `make check-doc-standards` inside `make validate`; [`tests/test-doc-standards.sh`](../../tests/test-doc-standards.sh) holds the checker to every violation kind.

## Why

Two gaps were found while scoping doc standards on 2026-11-05. No rule said how a diagram is drawn, so skills and docs mixed box-drawing text with one unstyled Mermaid block and nothing produced by the skills looked like it came from one project. And the only footer check in the tree was hardcoded to a different repository, so it could never pass here and no human-facing doc carried a footer at all. A standard that is practised rather than checked is a wish; this rule has one checker and one data file so that every doc, and every repo scaffolded from this plugin, reads the same definition.

## Audience

Two audiences, one definition. The globs live in the config so the checker and scaffolded repos cannot disagree.

| Audience | Files | Standard |
|----------|-------|----------|
| Human-facing | `README.md` and `docs/**/*.md`, minus `docs/agent-guidelines/**`, `docs/changelog/**`, `docs/CHANGELOG.md` and generated files (the config's `exclude` list) | Footer required; every diagram is themed Mermaid; checked |
| Agent-facing | `AGENTS.md`, `CLAUDE.md`, `rules/`, `core/`, `skills/`, `agents/`, platform adapters | No footer; diagrams follow the same Mermaid rule by convention — the skills that write docs point here — but are not checked |

## Diagrams

- **Every diagram is a fenced ```` ```mermaid ```` block.** Never box-drawing or ASCII art. A directory tree inside a ```` ```text ```` fence is not a diagram and stays allowed; `--strict` flags box-drawing characters anywhere else.
- **The first line of every Mermaid block is the canonical init directive**, kept verbatim in one file: [`config/docs/mermaid-init.txt`](../../config/docs/mermaid-init.txt). Copy it, or let `--fix` insert it; never retype it. It selects `theme: base` — the only theme Mermaid lets you customise — with dark fills, light borders and white text for nodes, subgraphs, edge labels, actors and notes, and mid-slate lines and signal text so edges stay readable on GitHub's transparent canvas in both colour modes.
- **No per-node styling.** `classDef`, `class`, `style` and `fill:` are forbidden inside a block (docs-review's standing ban). Hierarchy comes from subgraphs and node shapes, not from colour.
- **Dark is the default.** A user may ask for another palette for one artifact ("unless said otherwise"). In a repo doc, write `<!-- doc-standards-ok: <reason> -->` on the line directly above the fence and the checker leaves that block's directive alone. In an HTML artifact (`field-notebook-ui`, `dark-terminal-doc`) use the requested palette for that artifact only.
- **Put the title in prose, not in Mermaid's `title:`** — a diagram title is drawn on the canvas, where white text disappears on a light page.
- **What was verified.** The variable set comes from the Mermaid theming reference: only `base` is customisable, colours must be hex, and the note colours are set explicitly because they do not derive from the primary colour. GitHub honours the directive in rendered Markdown by observation, not by its own documentation — check a diagram on github.com in both colour modes before relying on a variable the file has not used before.

## Footer

Every human-facing doc ends with the same centred footer: a `---` rule, then one `<p align="center">` holding two links separated by `&nbsp;·&nbsp;`, as the last non-empty content of the file.

```markdown
---

<p align="center"><a href="QUESTION_URL">Have a Question?</a>&nbsp;·&nbsp;<a href="ISSUE_URL">Open an Issue</a></p>
```

- `Have a Question?` links to the repo creator's profile: `footer.question_url` in the config, or `https://<host>/<owner>` derived from `origin` when the value is null.
- `Open an Issue` links to `https://<host>/<owner>/<repo>/issues/new/choose` (GitLab hosts: `/-/issues/new`): `footer.issue_url`, or derived the same way.
- `README.md` keeps its `MIT © …` line directly above the footer, under the same `---` rule.
- Run the fixer rather than typing the footer: it appends or repairs it from the config, so no two docs can drift.

## Enforcement

```bash
bash scripts/check-doc-standards.sh            # path:line kind: detail on stdout; exit 1 on any violation
bash scripts/check-doc-standards.sh --fix      # append or repair footers, insert or replace init lines
bash scripts/check-doc-standards.sh --strict   # also flag box-drawing lines outside ```text fences
make check-doc-standards                       # the validate target
```

| Kind | Meaning | `--fix` |
|------|---------|---------|
| `footer-missing` | the file does not end with the footer | appended |
| `footer-wrong` | a centred footer is last but its links or the `---` above it differ | rewritten |
| `mermaid-init-missing` | a Mermaid block whose first line is not the canonical directive | inserted |
| `mermaid-init-wrong` | a Mermaid block opening with a different directive | replaced |
| `mermaid-style` | `classDef` / `class` / `style` / `fill:` inside a block | reported |
| `box-drawing` | `--strict` only: U+2500–U+257F outside a ```` ```text ```` fence | reported |

`make validate` runs `--strict`: the last box diagrams in `docs/` were redrawn as Mermaid in #371, so a box-drawing line outside a ```` ```text ```` fence is now a gate failure, not a warning.

## Skills that write docs or diagrams

Point here; never restate. `skill-creator` (and the body rules in [`skill-quality-standards.md`](skill-quality-standards.md)), `plan-dev`, `mcp-builder`, `repo-standards` (through its rubric, `skills/repo/_contract/standards-rubric.md`: `S2-05` footer, `S2-06` themed Mermaid, polish runs `--fix` — the skill body itself is a platform-claims path watched by the co-change gate, so the pointer lives in the rubric the skill reads), `repo-scaffold` (Agent A writes the footer on every doc and a dark Mermaid architecture overview), `docs-review` (Axes 1, 4 and 5 run the checker), `field-notebook-ui` and `dark-terminal-doc` (diagrams inside artifacts use the same dark palette unless the user asks otherwise). `multi-agent-repo` carries no pointer: it writes `AGENTS.md` and platform adapters, agent-facing files this rule excludes.

## Scaffolded repositories

The checker and its data ship to every scaffolded repo as `skills/repo/_contract/templates/check-doc-standards.sh.tmpl` and `templates/config/docs/`, wired as `make check-doc-standards`; the copies are regenerated and asserted by `skills/repo/_contract/scripts/sync-contract-scripts.sh`, never hand-maintained. A scaffolded repo's agents read the same standard from `docs/agent-guidelines/documentation-standards.md`, rendered from `templates/docs/agent-guidelines/documentation-standards.md.tmpl`.
