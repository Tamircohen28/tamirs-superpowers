---
name: dark-terminal-doc
description: 'Use when the user wants a polished, shareable single-file HTML technical document with a dark developer / terminal aesthetic — including comparison tables (A vs B), reference sheets, cheatsheets, changelogs, release notes, feature breakdowns, and API docs. Trigger phrases: "make a comparison table", "write a reference doc", "create a feature breakdown", "styled HTML doc", "dark terminal doc", "developer-facing HTML", "comparison cheatsheet", "technical reference page", "release notes HTML", "offline HTML doc", "single-file HTML page", "API cheatsheet", "git cheatsheet", "vs comparison".

  '
when_to_use: 'User asks for a polished, shareable HTML technical document — comparison table, reference sheet, changelog, release notes, feature breakdown, API cheatsheet. Trigger phrases: "make a comparison table", "write a reference doc", "create a feature breakdown", "styled HTML doc", "dark terminal doc", "produce a technical document", "offline HTML doc", "single-file HTML page", "release notes HTML", "API reference page", "git cheatsheet", "vs comparison doc".

  '
argument-hint: '[document type and topic — e.g. ''comparison table: Claude vs GPT-4'', ''reference sheet: git commands'', ''release notes: v2.0'']'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Write
- Read
- Bash
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: document-generation
  tags:
  - html
  - documentation
  - design
  - content
  - dark-terminal
  - comparison-table
  - reference-sheet
  - single-file
  updated-date: '2026-06-16'
---

# Dark Terminal Document Design System

## Why this skill exists

Standard markdown renders poorly in meetings, portfolios, and async handoffs. Notion exports are generic, Confluence is ugly, and spinning up a React/Next.js site for a one-off comparison table is overkill. This skill produces a **single self-contained HTML file** — no dependencies, no build step, no framework — that looks like a polished internal developer tool: dark IDE aesthetic, dense tables, semantic status colors. The output opens directly in any browser, can be emailed as an attachment, or dropped into GitHub Pages.

Naive approaches fail because: ad-hoc inline styles drift from the design system, font loading order breaks the monospace/sans split, and brand accent colors used directly in body text create contrast issues (they need pastelizing).

---

## Workflow

1. **Confirm the document type** from the user's request:
   - Comparison doc (two subjects side by side) → use all columns + summary cards
   - Reference/cheatsheet (one subject, many rows) → Command / Syntax / Description
   - Changelog/release notes (chronological) → Change / Impact / Description
   - Feature breakdown (one product, feature × status) → Feature / Status / Notes

2. **Identify brand colors** for comparison docs. For single-subject docs, pick one `--brand-a` accent and omit `--brand-b`.

3. **Load the CSS design system** from `references/css-design-system.md` and copy the token block verbatim. Override only `--brand-a` and `--brand-b`.

4. **Use the HTML skeleton** from `references/html-skeleton.md`. Fill section headers with emoji prefixes. Every row that has a clear winner gets a `winner-badge` after the explanatory text in the notes column.

5. **Write the file** as a single `.html` file using the `Write` tool. No external CSS files, no JS frameworks, no CDN scripts (Google Fonts import is the only external call — degrades gracefully offline).

6. **Verify** by describing the output structure to the user — number of sections, rows, and which brand wins the summary (for comparison docs).

---

## Hard Rules

1. **Always produce a single self-contained `.html` file.** No external CSS files, no JavaScript frameworks, no CDN scripts beyond the Google Fonts import.
2. **Never use solid backgrounds for tags or badges.** All fills must use `rgba` with 12–15% opacity so the dark `--bg` bleeds through.
3. **Brand accent colors (`--brand-a`, `--brand-b`) must be pastelized for body text** in data cells. Using the full-saturation color directly on body text causes glare and contrast issues.
4. **Winner badges belong in the notes column, after the explanatory text** — badge is a visual summary, not a lead-in.
5. **Never use light backgrounds, Inter/Roboto fonts, purple gradients, glassmorphism, or rounded hero cards.** This is a terminal aesthetic, not a marketing page.
6. **Summary cards are mandatory for comparison docs** — three boxes: brand-a wins / brand-b wins / tie. Single-subject docs (cheatsheets, changelogs) may omit them.
7. **Max-width is 1200px throughout,** not 960px — comparison tables need horizontal breathing room.
8. **Section headers must use `text-transform: uppercase`, `letter-spacing: 2px`, and an emoji prefix** to create visual rhythm and scanability in long tables.

---

## What NOT To Do

| Wrong | Right |
|-------|-------|
| `color: #D97757` in a table data cell | `color: #EBA98C` (pastelized) |
| `.tag { background: #4CAF7D; }` | `.tag-yes { background: rgba(76,175,125,0.15); }` |
| `<span class="winner-badge">wins</span> Context is better` | `Context is better <span class="winner-badge winner-brand-a">brand-a wins</span>` |
| Splitting CSS into a separate `.css` file | All styles inline in `<style>` block |
| `font-family: Inter, sans-serif` | `font-family: 'Syne', sans-serif` |
| `box-shadow` on `.table-wrap` | `border: 1px solid var(--border)` only |
| `border-radius: 8px` on `.table-wrap` | `border-radius: 16px` |
| Prose descriptions using IBM Plex Mono | Prose in Syne; metadata/labels in IBM Plex Mono |

---

## Quick-Reference Checklist

Before handing off the HTML file, verify:

- [ ] Single `.html` file — no external dependencies except Google Fonts import
- [ ] CSS variables match the token reference exactly (`--bg`, `--surface`, `--surface2`, `--border`, `--text`, `--muted`, `--yes`, `--no`, `--partial`, `--brand-a`, `--brand-b`)
- [ ] `--brand-a` and `--brand-b` overridden to match the document's subjects
- [ ] Table header columns use `th-brand-a`, `th-brand-b`, `th-meta` classes
- [ ] Data cells use `col-brand-a`/`col-brand-b` with pastelized hex values, not full-saturation vars
- [ ] Section headers: uppercase, 2px letter-spacing, emoji prefix
- [ ] Tags use rgba fills (not solid colors)
- [ ] Winner badges placed after explanatory text in notes column
- [ ] Summary cards present (for comparison docs only)
- [ ] Subtitle under h1 in IBM Plex Mono with `// title · date` pattern
- [ ] `max-width: 1200px` on all top-level containers
- [ ] `border-radius: 16px` on `.table-wrap`

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/css-design-system.md` | Every document — copy the full CSS token block and component library |
| `references/html-skeleton.md` | Starting point for every document — choose column layout by doc type |
