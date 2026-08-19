---
name: field-notebook-ui
description: >
  Use when a UI, explainer, dashboard, or diagram should carry this repo's engineer's
  field-notebook look — warm stone-paper background, hand-annotated margins, monospace
  labels, graph-paper grid. Trigger on: "field-notebook style", "warm stone-paper
  aesthetic", "the usual notebook look", "make it look like the field notebook", or when
  the user is building a second artifact that must visually match one already produced in
  this style. For a generic UI or artifact with no stated aesthetic, use the harness
  design skills instead.
when_to_use: >
  User names the aesthetic — "make it look like the field-notebook style", "use the warm
  stone-paper aesthetic", "the usual notebook look" — or asks for an artifact that must
  share a design language with one already built in this style, without re-specifying the
  token system each time. Not for a generic "build me a UI" with no stated look.
argument-hint: '[what to build — e.g. "k8s glossary", "helm explainer", "auth flow diagram"]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Read
  - Write
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
  tamirs:
    visibility: public
    category: creative
    role: implementer
    validation-tier: 1
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
      optional:
        - artifacts
        - shell
    tags:
      - ui
      - react
      - design-system
      - artifact
      - creative
      - interactive
  capability: creative-ui
  updated-date: '2026-08-19'
---

# Field-Notebook UI Skill

Generates React artifacts in a warm "engineer's field-notebook" visual system.
Every artifact you produce using this skill must feel like a page from a physical technical
notebook — structured, readable, purposeful — translated to an interactive screen.

---

## Design token system

Copy these tokens verbatim into every artifact. Never invent replacements.

```js
const T = {
  // Backgrounds
  bg:        "#ECE9DF",   // stone-paper — the page itself
  surface:   "#E5E1D5",   // slightly darker for cards / panels
  surfaceB:  "#DDD9CC",   // code block background

  // Text
  ink:       "#172423",   // petrol-black — primary text
  inkMid:    "#3D4F4E",   // secondary text
  inkDim:    "#6E7D7C",   // captions, placeholders
  rule:      "#C8C3B4",   // dividers, borders
  ruleHair:  "#B8B2A2",   // hairline card borders

  // Primary
  green:     "#0F6E56",   // petrol-green — primary actions, success, structural
  greenFill: "#0F6E5612", // low-alpha fill
  greenBg:   "#0F6E5620",

  // Semantic accents (use 2–3 per view, never all at once)
  rust:      "#B94A2C",   // errors, rollback, danger
  rustFill:  "#B94A2C14",
  amber:     "#C17D11",   // warnings, overrides, caution
  amberFill: "#C17D1114",
  purple:    "#5B3F8C",   // model, template, AI concepts
  purpleFill:"#5B3F8C12",
  blue:      "#1B5FA8",   // agent, commands, informational
  blueFill:  "#1B5FA812",
};
```

---

## Typography

Three fonts, three distinct roles. Never swap them.

| Role | Font | Usage |
|---|---|---|
| Display | Space Grotesk | Headings, labels on cards, tab names |
| Body | Inter | Prose, descriptions, detail text |
| Mono | JetBrains Mono | Eyebrows, code, technical labels, metadata |

Always load via Google Fonts in a `useEffect`:

```js
useEffect(() => {
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500;700&display=swap";
  document.head.appendChild(link);
}, []);
```

### Eyebrow pattern

Every section opens with a spaced uppercase mono eyebrow, then a sentence-case Space Grotesk heading.

```jsx
// Eyebrow component
function Eyebrow({ children, color = T.green }) {
  return (
    <div style={{
      fontFamily: "'JetBrains Mono', monospace",
      fontSize: "9px",
      fontWeight: 700,
      letterSpacing: "2.5px",
      textTransform: "uppercase",
      color,
      marginBottom: "5px",
    }}>
      {children}
    </div>
  );
}

// Usage: always eyebrow THEN heading
<Eyebrow>Chart structure</Eyebrow>
<h2 style={{ fontFamily: "'Space Grotesk', sans-serif", fontWeight: 600, fontSize: "16px" }}>
  File anatomy
</h2>
```

---

## Core components

### Card with colored left border

The standard content container. Hairline border, soft radius (0 on left to meet the accent stripe).

```jsx
function Card({ accent = T.green, fill, children, style = {} }) {
  return (
    <div style={{
      background: fill || T.surface,
      border: `1px solid ${T.ruleHair}`,
      borderLeft: `3px solid ${accent}`,
      borderRadius: "0 6px 6px 0",
      padding: "12px 14px",
      ...style,
    }}>
      {children}
    </div>
  );
}
```

### AirGap — the signature element

A dashed enclosure with a small corner label. Use this for Paragon-specific context,
important notes, security warnings, or any annotation that must stand apart.
This is the single most distinctive element of the design — use it deliberately, not on every card.

```jsx
function AirGap({ label = "note", children }) {
  return (
    <div style={{
      position: "relative",
      border: `1.5px dashed ${T.green}`,
      borderRadius: "6px",
      padding: "18px 16px 14px",
      marginTop: "20px",
    }}>
      <div style={{
        position: "absolute",
        top: "-9px",
        left: "12px",
        background: T.bg,
        padding: "0 6px",
        fontFamily: "'JetBrains Mono', monospace",
        fontSize: "8px",
        fontWeight: 700,
        letterSpacing: "2px",
        textTransform: "uppercase",
        color: T.green,
      }}>
        ╴{label}╶
      </div>
      <div style={{ fontFamily: "'Inter', sans-serif", fontSize: "12px", color: T.inkMid, lineHeight: "1.8" }}>
        {children}
      </div>
    </div>
  );
}
```

### Code block

Left accent border in the relevant semantic color. Mono font, surfaceB background.

```jsx
function CodeBlock({ children, accent = T.blue }) {
  return (
    <div style={{
      background: T.surfaceB,
      border: `1px solid ${T.rule}`,
      borderLeft: `3px solid ${accent}`,
      borderRadius: "0 5px 5px 0",
      padding: "12px 14px",
      overflowX: "auto",
    }}>
      <pre style={{
        fontFamily: "'JetBrains Mono', monospace",
        fontSize: "11px",
        lineHeight: "1.8",
        color: T.inkMid,
        whiteSpace: "pre",
        margin: 0,
      }}>
        {children}
      </pre>
    </div>
  );
}
```

### Tab button

Active state: green background, white text. Inactive: transparent, dimmed mono label.

```jsx
function TabBtn({ active, onClick, children }) {
  return (
    <button onClick={onClick} style={{
      fontFamily: "'JetBrains Mono', monospace",
      fontSize: "10px",
      fontWeight: active ? 700 : 500,
      letterSpacing: "1px",
      textTransform: "uppercase",
      padding: "7px 16px",
      background: active ? T.green : "transparent",
      color: active ? "#fff" : T.inkDim,
      border: `1px solid ${active ? T.green : T.rule}`,
      borderRadius: "4px",
      cursor: "pointer",
      transition: "background 0.15s, color 0.15s, border-color 0.15s",
    }}>
      {children}
    </button>
  );
}
```

---

## Interaction patterns

### Click-to-expand

Use for timeline steps, glossary terms, layered diagrams. Always show a ▼/▲ indicator.
Manage state with `useState({})` keyed by item id.

```jsx
const [expanded, setExpanded] = useState({});
const toggle = (id) => setExpanded(p => ({ ...p, [id]: !p[id] }));

// In render:
<button onClick={() => toggle(item.id)} style={{ /* card styles */ }}>
  <span>{item.title}</span>
  {item.hasDetail && <span>{expanded[item.id] ? "▲" : "▼"}</span>}
</button>
{expanded[item.id] && <div>{item.detail}</div>}
```

### Hover transitions

All interactive elements: `transition: "background 0.15s, color 0.15s, border-color 0.15s"`.
Nothing else. No transforms, no shadows on hover.

### Keyboard focus

Every interactive element must have visible focus. Inject once via a style tag:

```jsx
useEffect(() => {
  const style = document.createElement("style");
  style.textContent = `
    .nb-focus:focus-visible {
      outline: 2px solid ${T.green};
      outline-offset: 2px;
      border-radius: 3px;
    }
    @media (prefers-reduced-motion: reduce) {
      * { transition: none !important; }
    }
  `;
  document.head.appendChild(style);
  return () => style.remove();
}, []);
```

Add `className="nb-focus"` to every `<button>`.

---

## Layout rules

**Header** — always present. Contains:
1. Eyebrow: `CONTEXT · DOMAIN` (e.g., `PARAGON INTERVIEW PREP · INFRASTRUCTURE`)
2. H1 in Space Grotesk 700, sentence case
3. Subtitle in Inter 13px, T.inkDim

**Tabs** — horizontal pill row below header when content has multiple views.
Use JetBrains Mono uppercase. Gap: 8px. Wrap on narrow viewports.

**Two-column layout** — nav/list on left (fixed ~200–260px), detail on right (flex: 1).
Both panels scroll independently. Left panel: background `T.bg`, right: `T.bg`.
Divider: `1px solid T.rule`.

**Single-column** — max-width 760px for prose-heavy content. Padding 28px.

**Footer / status bar** — optional single-line summary at bottom. T.surface background,
mono text, T.inkDim color.

---

## Semantic accent assignment

Pick 2–3 accents per artifact based on what they encode. Be consistent within one artifact.

| Concept type | Accent |
|---|---|
| Success, primary action, structural | green |
| Error, danger, rollback, removal | rust |
| Warning, override, caution, change | amber |
| AI model, template, generative | purple |
| Command, agent, informational, link | blue |
| Neutral, disabled, secondary | inkDim |

Never use an accent purely decoratively. It must encode meaning.

---

## What to avoid

- No drop shadows (not in the field-notebook aesthetic)
- No gradients on surfaces (the paper is flat)
- No emoji in content
- No bold text inside prose (use Space Grotesk headings instead)
- No dark backgrounds, dark cards, or inverted panels
- No generic sans-serif fallback without Space Grotesk / Inter loaded
- Do not use more than 3 accent colors in a single view
- Do not put the AirGap on more than 1–2 places per tab — it is a signature, not a pattern

---

## Process for generating an artifact

1. Read the user's prompt and identify: content domain, data shape, interaction model needed
2. Choose which tabs / sections the artifact needs
3. Assign semantic accents to content types (2–3 max per view)
4. Decide where the AirGap annotation belongs (one key insight per tab)
5. Build the artifact following the token system, components, and layout rules above
6. Inject fonts and global CSS at mount (`useEffect` in Mode A, a `<style>` block in Mode B) — always with a system-font fallback stack
7. Every interactive element gets `className="nb-focus"` and `transition: "... 0.15s"`

The output is self-contained: all tokens, components and styles defined inline, no external
imports beyond the UI runtime itself.

---

## Output delivery — pick the target before you write a line

The **design system above is fully portable** — tokens, spacing, type scale, components and
layout rules are plain CSS values and carry to any target unchanged. What is *not* portable
is the container the design ships in. Choose it deliberately.

### Mode A — React component (`.jsx`)

A bare `.jsx` file with `import { useState } from "react"` and a default export is **not a
runnable program**. It runs only where a host supplies the React runtime and renders the
component for you — Claude Artifacts and Claude Desktop do this; a plain browser, a terminal
agent, and a repo with no bundler do not.

Use Mode A when **all** of these hold:
- the `artifacts` capability is available on the current platform
  (`core/capabilities/platforms.json`), **or** the user has an existing React project to drop
  the component into; and
- the user asked for a React component, or the destination is a React codebase.

### Mode B — single-file HTML (`.html`) — **the portable default**

One `.html` file with inline `<style>` and inline `<script>`, opened directly from
`file://`. No build step, no bundler, no runtime supplied by a host. This is what you produce
whenever Mode A's conditions are not met — which includes every platform whose `artifacts`
capability is `unsupported` or `unknown`.

Mode B carries the identical design system. Translate the components the obvious way: the
token object becomes CSS custom properties on `:root`, `useState` becomes a small amount of
vanilla JS, tab switching becomes class toggling. Nothing in the aesthetic is lost.

### Never do this

- **Never emit a bare `.jsx` on a platform with no React runtime** and describe it as
  finished. That hands the user a file they cannot open. If you are unsure whether the host
  renders React, produce Mode B — it works everywhere, including inside a React host.
- **Never claim the output "will render as an artifact"** unless the `artifacts` capability
  is actually present. State which mode you produced and what is needed to view it.
- **Never require a build step, package install, or dev server** in either mode.

### Fonts and network

The template injects Google Fonts. That is a **view-time network dependency**, and it fails
offline and under a strict Content-Security-Policy. Always declare a real fallback stack —
`'Space Grotesk', system-ui, sans-serif` and `'Inter', system-ui, sans-serif` — so the page
degrades to system faces rather than to a broken layout. Fonts are the only permitted remote
asset; everything else is inline.

### Steps (both modes)

1. Derive a short snake_case filename from the user's request (e.g. `helm_explainer`,
   `k8s_glossary`) and append `.jsx` (Mode A) or `.html` (Mode B).
2. Write the complete file with the Write tool.
3. Report the file path, **the mode you chose, and why** — plus how to view it.

**Never paste the source into the conversation as the deliverable.** The file is the
deliverable, in both modes.

---

## Quick-reference template

**Mode A (React).** For Mode B, the same structure with CSS custom properties on `:root`
and vanilla JS for the tab state — the tokens, components and layout rules are unchanged.

```jsx
import { useState, useEffect } from "react";

const T = { /* paste token block here */ };

export default function App() {
  const [tab, setTab] = useState("overview");

  useEffect(() => {
    // Inject fonts + global CSS (focus ring, reduced-motion)
  }, []);

  return (
    <div style={{ background: T.bg, minHeight: "100vh", color: T.ink,
                  fontFamily: "'Inter', system-ui, sans-serif" }}>
      {/* Header */}
      <header style={{ padding: "20px 28px 16px", borderBottom: `1px solid ${T.rule}` }}>
        <Eyebrow>context · domain</Eyebrow>
        <h1 style={{ fontFamily: "'Space Grotesk', system-ui, sans-serif", fontSize: "22px",
                     fontWeight: 700, color: T.ink }}>
          Artifact title
        </h1>
      </header>

      {/* Tabs */}
      <div style={{ display: "flex", gap: "8px", padding: "14px 28px",
                    borderBottom: `1px solid ${T.rule}`, flexWrap: "wrap" }}>
        {["Overview", "Detail", "Reference"].map(t => (
          <TabBtn key={t} active={tab === t.toLowerCase()} onClick={() => setTab(t.toLowerCase())}>
            {t}
          </TabBtn>
        ))}
      </div>

      {/* Content */}
      <main style={{ padding: "24px 28px", maxWidth: "760px" }}>
        {/* Cards, AirGap, CodeBlocks here */}
      </main>
    </div>
  );
}
```
