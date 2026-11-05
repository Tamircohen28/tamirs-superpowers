# Documentation standards

**Applies when:** writing or editing `README.md` or anything under `docs/`, or drawing a diagram anywhere in this repository.
**Data:** `config/docs/doc-standards.json` (which files are human-facing, what the footer links to) and `config/docs/mermaid-init.txt` (the one canonical Mermaid init line).
**Enforced by:** `scripts/check-doc-standards.sh` — `make check-doc-standards`; `--fix` appends or repairs footers and inserts the init line.

## Diagrams

- Every diagram is a fenced ```` ```mermaid ```` block. Never box-drawing or ASCII art; a directory tree inside a ```` ```text ```` fence is not a diagram and stays allowed.
- The first line of every Mermaid block is the init directive from `config/docs/mermaid-init.txt`, copied verbatim (or inserted by `--fix`). It gives dark fills with white text for nodes, subgraphs, edge labels, actors and notes.
- No `classDef`, `class`, `style` or `fill:` inside a block. Hierarchy comes from subgraphs and shapes, not colour.
- Dark is the default. One block may keep another palette when the user asks: put `<!-- doc-standards-ok: <reason> -->` on the line directly above the fence.
- Put the diagram's title in prose, not in Mermaid's `title:`.

## Footer

Every human-facing doc ends with a `---` rule and one centred paragraph holding two links, `Have a Question?` and `Open an Issue`, separated by `&nbsp;·&nbsp;`, as the last non-empty content of the file. `README.md` keeps its license line directly above the footer. Never type the footer — run the fixer, so no two docs can drift:

```bash
bash scripts/check-doc-standards.sh --fix
```

## Checking

```bash
bash scripts/check-doc-standards.sh            # path:line kind: detail; exit 1 on any violation
bash scripts/check-doc-standards.sh --strict   # also flag box-drawing lines outside ```text fences
```
