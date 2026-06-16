# Dark Terminal Doc — CSS Design System Reference

Copy these blocks verbatim into every document. Override only `--brand-a` and `--brand-b`.

---

## Google Fonts Import

```css
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=Syne:wght@400;600;700;800&display=swap');
```

---

## CSS Token Block

```css
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
  --brand-a:  #D97757;   /* warm accent (default) */
  --brand-b:  #6E7FD9;   /* cool accent (default) */
}
```

---

## Typography

```css
body {
  background: var(--bg);
  color: var(--text);
  font-family: 'Syne', sans-serif;
  font-size: 14px;
  padding: 48px 24px 80px;
}
```

Rules:
- Body / UI: `'Syne', sans-serif` — geometric, slightly wide, strong at large weights
- Monospace / labels / code: `'IBM Plex Mono', monospace` — readable at small sizes, technical feel
- Base font size: `14px` on body, `13px` for table content, `11–12px` for meta/labels
- Headings: `font-weight: 800`, `letter-spacing: -1px`, `line-height: 1.1`
- Responsive heading: `font-size: clamp(28px, 4vw, 48px)`

---

## Layout

```css
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

Spacing rhythm: `4 / 8 / 12 / 16 / 20 / 24 / 32 / 48 / 56 / 80px` — use multiples of 4 only.

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

### Summary Cards (footer — comparison docs only)

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
