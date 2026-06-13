---
name: dark-terminal-doc
description: >
  Use when the user wants a polished, shareable single-file HTML technical
  document with a dark developer aesthetic — comparison tables, reference sheets,
  changelogs, release notes, feature breakdowns, API docs, cheatsheets. Triggers
  on: "make a comparison table", "write a reference doc", "create a feature
  breakdown", "styled HTML doc", "dark terminal doc", "developer-facing HTML",
  "comparison cheatsheet", "technical reference page".
when_to_use: >
  User asks for a polished, shareable HTML technical document — comparison table,
  reference sheet, changelog, release notes, feature breakdown, API cheatsheet.
  Trigger phrases: "make a comparison table", "write a reference doc", "create a
  feature breakdown", "styled HTML doc", "dark terminal doc", "produce a technical
  document", "offline HTML doc", "single-file HTML page".
argument-hint: "[document type and topic — e.g. 'comparison table: Claude vs GPT-4', 'reference sheet: git commands', 'release notes: v2.0']"
model: claude-sonnet-4-6
allowed-tools:
  - Write
  - Read
  - Bash
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
  updated-date: "2026-06-13"
---

# Dark Terminal Document Design System

## Why this skill exists

Standard markdown renders poorly in meetings, portfolios, and async handoffs. Notion exports are generic, Confluence is ugly, and spinning up a React/Next.js site for a one-off comparison table is overkill. This skill produces a **single self-contained HTML file** — no dependencies, no build step, no framework — that looks like a polished internal developer tool: dark IDE aesthetic, dense tables, semantic status colors. The output opens directly in any browser, can be emailed as an attachment, or dropped into GitHub Pages.

Naive approaches fail because: ad-hoc inline styles drift from the design system, font loading order breaks the monospace/sans split, and brand accent colors used directly in body text create contrast issues (they need pastelizing).

---

## Workflow

1. **Confirm the document type** from the user's request:
   - Comparison doc (two subjects side by side)
   - Reference/cheatsheet (one subject, many rows)
   - Changelog/release notes (chronological, minimal columns)
   - Feature breakdown (one product, feature × status)

2. **Identify brand colors** for comparison docs. For single-subject docs, pick one `--brand-a` and omit `--brand-b`.

3. **Copy the CSS token block verbatim** (see [Exact Token Reference](#exact-token-reference)). Override only `--brand-a` and `--brand-b`.

4. **Structure the HTML** using the skeleton below. Fill section headers with emoji prefixes. Every row that has a clear winner gets a `winner-badge` in the notes column.

5. **Write the file** as a single `.html` file using the `Write` tool. No external CSS files, no JS frameworks, no CDN scripts (Google Fonts import is the only external call and it degrades gracefully offline).

6. **Verify** by describing the output structure to the user — number of sections, rows, and which brand wins the summary.

---

## Exact Token Reference

Copy these CSS variables verbatim as the foundation of every document:

```css
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=Syne:wght@400;600;700;800&display=swap');

:root {
  /* Backgrounds — three levels of depth */
  --bg:       #0D0D10;   /* page background */
  --surface:  #141418;   /* card / thead */
  --surface2: #1C1C22;   /* section headers, elevated elements */

  /* Borders */
  --border:   #2A2A32;   /* all dividers and outlines */

  /* Text */
  --text:     #E8E8EE;   /* primary body text */
  --muted:    #6B6B7A;   /* labels, secondary text, metadata */

  /* Semantic status */
  --yes:      #4CAF7D;   /* supported / green */
  --no:       #E05A5A;   /* not supported / red */
  --partial:  #D4A843;   /* partial / yellow */

  /* Brand — override per document */
  --brand-a:  #D97757;   /* warm accent */
  --brand-b:  #6E7FD9;   /* cool accent */
}
```

**Typography:**
- Body / UI: `'Syne', sans-serif` — geometric, slightly wide, strong at large weights
- Monospace / labels / code: `'IBM Plex Mono', monospace` — readable at small sizes, technical feel
- Base font size: `14px` on `body`, `13px` for table content, `11–12px` for meta/labels
- Headings: `font-weight: 800`, `letter-spacing: -1px`, `line-height: 1.1`
- Responsive heading: `font-size: clamp(28px, 4vw, 48px)`

---

## Layout Rules

```css
body {
  background: var(--bg);
  color: var(--text);
  font-family: 'Syne', sans-serif;
  padding: 48px 24px 80px;
}

/* All content constrained to 1200px, centered */
header, .table-wrap, .summary-row {
  max-width: 1200px;
  margin: 0 auto;
}

/* Header: title left, legend/meta right */
header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 32px;
  flex-wrap: wrap;
  margin-bottom: 56px;
}
```

**Spacing rhythm:** `4 / 8 / 12 / 16 / 20 / 24 / 32 / 48 / 56 / 80px`
Use multiples of 4. Generous vertical padding (48–80px) at page edges.

---

## Table System

```css
.table-wrap {
  overflow-x: auto;
  border-radius: 16px;
  border: 1px solid var(--border);
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 14px;
}

thead tr {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
}

th {
  padding: 18px 20px;
  text-align: left;
  font-weight: 700;
  font-size: 13px;
  letter-spacing: 0.5px;
  white-space: nowrap;
}

th.th-brand-a { color: var(--brand-a); }
th.th-brand-b { color: var(--brand-b); }
th.th-meta    { color: var(--muted); }

.section-header td {
  background: var(--surface2);
  border-top: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
  padding: 10px 20px;
  font-weight: 700;
  font-size: 11px;
  letter-spacing: 2px;
  text-transform: uppercase;
  color: var(--muted);
}

tbody tr:not(.section-header) {
  border-bottom: 1px solid var(--border);
  transition: background 0.15s;
}
tbody tr:not(.section-header):hover {
  background: rgba(255,255,255,0.025);
}

td {
  padding: 14px 20px;
  vertical-align: top;
  line-height: 1.6;
}

td.col-label   { font-weight: 600; font-size: 13px; color: var(--text); white-space: nowrap; }
td.col-meta    { font-family: 'IBM Plex Mono', monospace; font-size: 12px; color: var(--muted); white-space: nowrap; }
td.col-brand-a { color: #EBA98C; }   /* lightened brand-a for body text */
td.col-brand-b { color: #A8B4F0; }   /* lightened brand-b for body text */
td.col-notes   { color: var(--muted); font-size: 13px; }
```

**Column lightening rule:** `--brand-a` / `--brand-b` are vivid for headers. For body text in data cells, use pastelized versions (~40% lighter). Example: `#D97757` → `#EBA98C`, `#6E7FD9` → `#A8B4F0`.

---

## Component Library

### Tags / Badges

```css
.tag {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-family: 'IBM Plex Mono', monospace;
  font-weight: 600;
  margin-right: 4px;
  margin-bottom: 2px;
}

/* 12-15% opacity fill, 25-30% opacity border */
.tag-yes     { background: rgba(76,175,125,0.15);  color: var(--yes);     border: 1px solid rgba(76,175,125,0.3); }
.tag-no      { background: rgba(224,90,90,0.12);   color: var(--no);      border: 1px solid rgba(224,90,90,0.25); }
.tag-partial { background: rgba(212,168,67,0.12);  color: var(--partial); border: 1px solid rgba(212,168,67,0.25); }
.tag-brand-a { background: rgba(217,119,87,0.15);  color: var(--brand-a); border: 1px solid rgba(217,119,87,0.3); }
.tag-brand-b { background: rgba(110,127,217,0.15); color: var(--brand-b); border: 1px solid rgba(110,127,217,0.3); }
```

```html
<span class="tag tag-yes">✓ yes</span>
<span class="tag tag-no">✗ no</span>
<span class="tag tag-partial">~ partial</span>
```

### Winner Badge

```css
.winner-badge {
  display: inline-block;
  font-size: 10px;
  font-family: 'IBM Plex Mono', monospace;
  padding: 1px 6px;
  border-radius: 3px;
  vertical-align: middle;
  margin-left: 4px;
}
.winner-brand-a { background: rgba(217,119,87,0.2);  color: var(--brand-a); }
.winner-brand-b { background: rgba(110,127,217,0.2); color: var(--brand-b); }
.winner-tie     { background: rgba(255,255,255,0.08); color: var(--muted); }
```

```html
<span class="winner-badge winner-brand-a">brand-a wins</span>
<span class="winner-badge winner-tie">tie</span>
```

### Inline Code

```css
code {
  font-family: 'IBM Plex Mono', monospace;
  font-size: 11.5px;
  background: rgba(255,255,255,0.07);
  padding: 1px 5px;
  border-radius: 3px;
  color: #C8C8D8;
}
```

### Legend Dots

```css
.legend { display: flex; gap: 20px; align-items: center; flex-wrap: wrap; }
.legend-item {
  display: flex; align-items: center; gap: 8px;
  font-size: 13px; font-family: 'IBM Plex Mono', monospace; color: var(--muted);
}
.dot { width: 10px; height: 10px; border-radius: 50%; }
.dot-yes     { background: var(--yes); }
.dot-no      { background: var(--no); }
.dot-partial { background: var(--partial); }
```

### Summary Cards (footer)

Three-column summary at the bottom of comparison documents.

```html
<div style="max-width:1200px; margin:32px auto 0; display:flex; gap:20px; flex-wrap:wrap;">
  <div style="flex:1; min-width:240px; background:rgba(217,119,87,0.08); border:1px solid rgba(217,119,87,0.2); border-radius:12px; padding:20px 24px;">
    <div style="color:var(--brand-a); font-weight:700; font-size:13px; margin-bottom:10px; font-family:'IBM Plex Mono',monospace;">TOOL A WINS AT</div>
    <div style="font-size:13px; line-height:1.8; color:#EBA98C;">Context awareness<br>Offline capability</div>
  </div>
  <div style="flex:1; min-width:240px; background:rgba(110,127,217,0.08); border:1px solid rgba(110,127,217,0.2); border-radius:12px; padding:20px 24px;">
    <div style="color:var(--brand-b); font-weight:700; font-size:13px; margin-bottom:10px; font-family:'IBM Plex Mono',monospace;">TOOL B WINS AT</div>
    <div style="font-size:13px; line-height:1.8; color:#A8B4F0;">IDE integration<br>Speed</div>
  </div>
  <div style="flex:1; min-width:240px; background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.1); border-radius:12px; padding:20px 24px;">
    <div style="color:var(--muted); font-weight:700; font-size:13px; margin-bottom:10px; font-family:'IBM Plex Mono',monospace;">TIE</div>
    <div style="font-size:13px; line-height:1.8; color:var(--muted);">Pricing<br>Basic completions</div>
  </div>
</div>
```

---

## Document HTML Skeleton

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tool A vs Tool B — Technical Comparison</title>
<style>
  /* === PASTE FULL CSS HERE === */
</style>
</head>
<body>

<header>
  <div>
    <h1><span style="color:var(--brand-a)">Tool A</span> vs <span style="color:var(--brand-b)">Tool B</span></h1>
    <p style="font-family:'IBM Plex Mono',monospace; color:var(--muted); font-size:13px; margin-top:8px;">// technical comparison · June 2026</p>
  </div>
  <div class="legend">
    <div class="legend-item"><div class="dot dot-yes"></div> supported</div>
    <div class="legend-item"><div class="dot dot-no"></div> not supported</div>
    <div class="legend-item"><div class="dot dot-partial"></div> partial / limited</div>
  </div>
</header>

<div class="table-wrap">
<table>
  <thead>
    <tr>
      <th class="th-meta">Feature</th>
      <th class="th-meta">Category</th>
      <th class="th-brand-a">Tool A</th>
      <th class="th-brand-b">Tool B</th>
      <th class="th-meta">Notes</th>
    </tr>
  </thead>
  <tbody>

    <tr class="section-header">
      <td colspan="5">⚡ Core Capabilities</td>
    </tr>

    <tr>
      <td class="col-label">Context window</td>
      <td class="col-meta">capacity</td>
      <td class="col-brand-a"><span class="tag tag-yes">✓ 200k</span></td>
      <td class="col-brand-b"><span class="tag tag-partial">~ 128k</span></td>
      <td class="col-notes"><span class="winner-badge winner-brand-a">tool-a wins</span> Larger projects fit without chunking</td>
    </tr>

  </tbody>
</table>
</div>

<!-- Summary cards -->
<div style="max-width:1200px; margin:32px auto 0; display:flex; gap:20px; flex-wrap:wrap;">
  <!-- one card per brand + one tie card -->
</div>

</body>
</html>
```

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
- [ ] Summary cards present (for comparison docs)
- [ ] Subtitle under h1 in IBM Plex Mono with `// title · date` pattern
- [ ] `max-width: 1200px` on all top-level containers
- [ ] `border-radius: 16px` on `.table-wrap`
