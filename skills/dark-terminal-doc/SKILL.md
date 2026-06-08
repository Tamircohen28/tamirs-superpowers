---
name: dark-terminal-doc
description: >
  Create rich technical HTML documents — comparison tables, reference sheets,
  feature breakdowns, changelogs, release notes — using a dark terminal-inspired
  design system. Use when the user asks to produce a polished HTML doc, reference
  page, or technical comparison that should look sharp and developer-facing.
  Triggers on: "make a comparison table", "write a reference doc", "create a
  feature breakdown", "produce a technical document", "styled HTML doc".
when_to_use: "User asks for a polished, shareable HTML technical document — comparison table, reference sheet, changelog, release notes, feature breakdown. Trigger phrases: 'make a comparison table', 'write a reference doc', 'create a feature breakdown', 'styled HTML doc', 'dark terminal doc'."
argument-hint: "[document type and topic — e.g. 'comparison table: Claude vs GPT-4', 'reference sheet: git commands']"
metadata:
  capability: document-generation
  tags:
    - html
    - documentation
    - design
    - content
    - dark-terminal
  updated-date: "2026-06-08"
---

# Dark Terminal Document Design System

This skill produces single-file HTML technical documents with a consistent dark,
developer-aesthetic design system. The output of `cursor-vs-claude-code.html`
is the canonical reference for this style.

---

## Design DNA

**Aesthetic:** Dark IDE / terminal. Dense but readable. Monospace accents on
a sans-serif body. Brand colors used as semantic signals, not decoration.
Think: a beautiful internal tool, not a marketing page.

**NOT:** Light background, Inter/Roboto, purple gradients, rounded hero cards,
shadcn-style component libraries, glassmorphism excess.

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

  /* Brand — override per document with the two subjects being compared/highlighted */
  --brand-a:  #D97757;   /* warm accent (e.g. Claude orange) */
  --brand-b:  #6E7FD9;   /* cool accent (e.g. Cursor blue) */
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

The workhorse of this design. Every comparison or reference doc uses this table pattern.

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

/* Header row */
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

/* Color thead columns by subject */
th.th-brand-a { color: var(--brand-a); }
th.th-brand-b { color: var(--brand-b); }
th.th-meta    { color: var(--muted); }

/* Section header rows — group related rows */
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

/* Data rows */
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

/* Column roles */
td.col-label   { font-weight: 600; font-size: 13px; color: var(--text); white-space: nowrap; }
td.col-meta    { font-family: 'IBM Plex Mono', monospace; font-size: 12px; color: var(--muted); white-space: nowrap; }
td.col-brand-a { color: #EBA98C; }   /* lightened brand-a for body text */
td.col-brand-b { color: #A8B4F0; }   /* lightened brand-b for body text */
td.col-notes   { color: var(--muted); font-size: 13px; }
```

**Column lightening rule:** Brand accent colors (`--brand-a`, `--brand-b`) are
vivid for headers/labels. For body text in data cells, use lightened/pastelized
versions so they're readable without overwhelming. Typical shift: add ~40%
lightness. Example: `#D97757` → `#EBA98C`, `#6E7FD9` → `#A8B4F0`.

---

## Component Library

### Tags / Badges

Used inline in table cells to signal status at a glance.

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

/* Pattern: 12-15% opacity fill, 25-30% opacity border, full-opacity text */
.tag-yes     { background: rgba(76,175,125,0.15);  color: var(--yes);     border: 1px solid rgba(76,175,125,0.3); }
.tag-no      { background: rgba(224,90,90,0.12);   color: var(--no);      border: 1px solid rgba(224,90,90,0.25); }
.tag-partial { background: rgba(212,168,67,0.12);  color: var(--partial); border: 1px solid rgba(212,168,67,0.25); }
.tag-brand-a { background: rgba(217,119,87,0.15);  color: var(--brand-a); border: 1px solid rgba(217,119,87,0.3); }
.tag-brand-b { background: rgba(110,127,217,0.15); color: var(--brand-b); border: 1px solid rgba(110,127,217,0.3); }
```

HTML pattern:
```html
<span class="tag tag-yes">✓ yes</span>
<span class="tag tag-no">✗ no</span>
<span class="tag tag-partial">~ partial</span>
```

### Winner Badge

A tiny inline label to declare which side wins a comparison row.

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

HTML pattern:
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

Used in the header area to explain status colors.

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

### Summary Cards (footer row)

Three-column summary at the bottom of the document.

```css
/* Used inline via style attributes, or extract to a .summary-card class */
/* Pattern for each card: */
background: rgba(VAR_R, VAR_G, VAR_B, 0.08);
border: 1px solid rgba(VAR_R, VAR_G, VAR_B, 0.2);
border-radius: 12px;
padding: 20px 24px;
flex: 1;
min-width: 240px;

/* Card heading */
color: var(--brand-x);
font-weight: 700;
font-size: 13px;
margin-bottom: 10px;
font-family: 'IBM Plex Mono', monospace;

/* Card body */
font-size: 13px;
line-height: 1.8;
color: <lightened brand-x>;   /* e.g. #C0C8F0 for brand-b, #F0C8B0 for brand-a */
```

Container:
```html
<div style="max-width:1200px; margin:32px auto 0; display:flex; gap:20px; flex-wrap:wrap;">
  <div style="flex:1; min-width:240px; ...card styles...">
    <div style="...heading styles...">BRAND A WINS AT</div>
    <div style="...body styles...">Feature 1<br>Feature 2</div>
  </div>
  ...
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
<title>Your Title Here</title>
<style>
  /* Paste full CSS here */
</style>
</head>
<body>

<header>
  <div>
    <h1><span class="brand-a-name">Brand A</span> vs <span class="brand-b-name">Brand B</span></h1>
    <p class="subtitle">// subtitle in monospace · date or version</p>
  </div>
  <div class="legend">
    <div class="legend-item"><div class="dot dot-yes"></div> supported</div>
    <div class="legend-item"><div class="dot dot-no"></div> not supported</div>
    <div class="legend-item"><div class="dot dot-partial"></div> partial</div>
  </div>
</header>

<div class="table-wrap">
<table>
  <thead>
    <tr>
      <th class="th-meta">Feature</th>
      <th class="th-meta">Aspect</th>
      <th class="th-brand-a">Brand A</th>
      <th class="th-brand-b">Brand B</th>
      <th class="th-meta">Notes</th>
    </tr>
  </thead>
  <tbody>

    <!-- Section group -->
    <tr class="section-header">
      <td colspan="5">⚡ Section Name</td>
    </tr>

    <!-- Data row -->
    <tr>
      <td class="col-label">Feature name</td>
      <td class="col-meta">category</td>
      <td class="col-brand-a"><span class="tag tag-yes">✓ yes</span> — description</td>
      <td class="col-brand-b"><span class="tag tag-no">✗ no</span></td>
      <td class="col-notes"><span class="winner-badge winner-brand-a">brand-a wins</span> reason</td>
    </tr>

  </tbody>
</table>
</div>

<!-- Summary cards -->
<div style="max-width:1200px; margin:32px auto 0; display:flex; gap:20px; flex-wrap:wrap;">
  <!-- card per brand + tie -->
</div>

</body>
</html>
```

---

## Rules of Thumb

1. **Subtitle always monospace.** The `// subtitle · date` pattern in IBM Plex Mono
   signals "technical artifact". Always include it under the h1.

2. **Section headers break the table rhythm.** Use `letter-spacing: 2px` +
   `text-transform: uppercase` + `font-size: 11px`. They visually chunk the table
   into scannable groups. Add an emoji prefix for quick visual scanning.

3. **Accent colors have three roles:**
   - Full saturation → headers, labels, section titles
   - Lightened pastel → body text in data cells (readable without glare)
   - Low-opacity fill → card backgrounds, tag fills

4. **Never use solid backgrounds for tags.** Always `rgba` with ~12-15% opacity.
   The transparency lets the dark `--bg` bleed through, maintaining depth.

5. **Monospace is for metadata, not content.** Column role labels (`col-meta`),
   subtitles, legends, tag text, and inline code all use IBM Plex Mono.
   Prose content and feature descriptions stay in Syne.

6. **The hover state is subtle.** `rgba(255,255,255,0.025)` — barely perceptible.
   Just enough to confirm interactivity without breaking the dark aesthetic.

7. **Winner badges go in the notes column, after the reason.** Not before.
   The human explanation comes first, the badge is a visual summary.

8. **Summary cards at the bottom are mandatory for comparison docs.**
   They synthesize the table into a 3-box takeaway: brand-a wins / brand-b wins / tie.
   Use `min-width: 240px` and `flex: 1` so they collapse gracefully on mobile.

9. **`border-radius: 16px` on the table wrapper** gives the table a contained,
   card-like feel without adding drop shadows. Do not use `box-shadow` here.

10. **Max-width 1200px throughout.** Wider than typical (960px) because comparison
    tables need breathing room for multi-column content.
