---
name: algorithmic-art
description: 'Use when the user wants to create generative art, algorithmic art, creative coding, or code-driven visuals — including flow fields, particle systems, noise-based art, Lissajous figures, recursive trees, Voronoi patterns, L-systems, fractals, or any interactive p5.js sketch. Trigger phrases: ''generative art'', ''algorithmic art'', ''flow field'', ''particle system'', ''make art with code'', ''creative coding'', ''p5.js sketch'', ''procedural art'', ''noise art'', ''make something visual with code'', ''code art''.'
when_to_use: 'User asks to create generative or algorithmic art using code. Trigger phrases: ''create algorithmic art'', ''generative art'', ''flow field'', ''particle system'', ''make art with p5.js'', ''create visual art with code'', ''procedural visuals'', ''noise art'', ''Lissajous figures'', ''recursive tree art'', ''fractal art''.'
argument-hint: '[art style or concept — e.g. ''flow field'', ''particle system'', ''Lissajous figures'', ''recursive tree'', ''Voronoi'']'
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
license: Apache-2.0
metadata:
  capability: creative-coding
  tags:
  - art
  - p5js
  - generative
  - creative
  - content
  updated-date: '2026-06-16'
---

# Algorithmic Art — Generative Art with p5.js

## Why this skill exists

Users asking for "generative art" or "algorithmic art" need more than a random blob of colored circles. Naive approaches produce visually uninteresting output: flat noise fields with no hierarchy, particle systems with no purpose, or static images dressed up as "generative." This skill enforces a two-phase creative process — philosophy first, code second — so the algorithm has intentional aesthetic direction. The output is a self-contained, interactive HTML artifact with seed navigation and tunable parameters, not a screenshot or a code snippet that requires external tooling to run.

---

## Workflow

### Phase 1: Algorithmic Philosophy (the soul)

Before writing any code, create a named generative aesthetic movement in 3–5 focused paragraphs. This is not a description of what will be drawn — it is the computational worldview that will drive every parameter decision.

**Name the movement** (1–2 words): e.g., "Organic Turbulence", "Quantum Harmonics", "Stochastic Crystallization"

**Articulate the philosophy around these computational axes:**
- What mathematical forces drive the system? (noise, harmonics, recursion, field dynamics)
- What is the relationship between order and randomness?
- What makes each seed unique yet recognizable as the same system?
- Where does beauty live — in single frames, in motion, or in accumulated traces?

**Philosophy examples (condensed — expand to 3–5 paragraphs):**

| Movement | Core idea | Algorithmic expression |
|---|---|---|
| Organic Turbulence | Chaos constrained by natural law | Layered Perlin noise flow fields; particle trails accumulate into density maps |
| Quantum Harmonics | Discrete entities exhibiting interference | Grid particles with evolving phase values; constructive/destructive interference creates nodes |
| Recursive Whispers | Self-similarity across scales | L-system branching with golden-ratio angles; noise perturbations break symmetry |
| Field Dynamics | Invisible forces made visible | Vector fields from mathematical functions; particles trace field lines and die at equilibrium |
| Stochastic Crystallization | Random processes crystallizing into order | Randomized Voronoi relaxation; cells push to equilibrium; color from cell topology |

Output the philosophy as a `.md` artifact before proceeding to code.

---

### Phase 2: P5.js Implementation (the expression)

The algorithm must emerge from the philosophy — not from a menu of pattern types.

**Step 1 — Seed for reproducibility (always):**
```javascript
let params = {
  seed: 42,
  // all other params here
};

function setup() {
  createCanvas(1200, 1200);
  randomSeed(params.seed);
  noiseSeed(params.seed);
  // ...
}
```

**Step 2 — Design parameters that emerge from the philosophy:**

Ask: "What qualities of this system should be tunable?" Not: "What sliders look good?"

```javascript
// Flow field example — params derived from the Organic Turbulence philosophy
let params = {
  seed: 42,
  particleCount: 2000,
  noiseScale: 0.003,       // zoom level of the noise field
  noiseOctaves: 4,         // complexity layers
  forceStrength: 2.5,      // how strongly field directs particles
  trailAlpha: 12,          // opacity of each trail step (accumulation rate)
  speedMin: 0.5,
  speedMax: 2.0,
  palette: ['#1a1a2e', '#16213e', '#0f3460', '#e94560'],
};
```

**Step 3 — Build the core algorithm from the philosophy's logic:**

```javascript
// Particle following a Perlin noise flow field
class Particle {
  constructor() { this.reset(); }

  reset() {
    this.x = random(width);
    this.y = random(height);
    this.life = random(100, 300);
  }

  update() {
    let angle = noise(this.x * params.noiseScale, this.y * params.noiseScale) * TWO_PI * params.noiseOctaves;
    let vx = cos(angle) * params.forceStrength;
    let vy = sin(angle) * params.forceStrength;
    this.x += vx;
    this.y += vy;
    this.life--;
    if (this.life <= 0 || this.x < 0 || this.x > width || this.y < 0 || this.y > height) {
      this.reset();
    }
  }

  draw() {
    let c = color(random(params.palette));
    stroke(red(c), green(c), blue(c), params.trailAlpha);
    point(this.x, this.y);
  }
}
```

**Step 4 — Build the interactive HTML artifact:**

The artifact is self-contained (p5.js from CDN, no external files). Structure:

```html
<!DOCTYPE html>
<html>
<head>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/p5.js/1.9.4/p5.min.js"></script>
  <style>
    /* Light theme, sidebar left, canvas right */
    body { display: flex; font-family: 'Segoe UI', sans-serif; background: #f8f8f8; margin: 0; }
    #sidebar { width: 240px; padding: 16px; background: #fff; border-right: 1px solid #e0e0e0; overflow-y: auto; }
    #canvas-container { flex: 1; display: flex; align-items: center; justify-content: center; }
    .control-group { margin-bottom: 12px; }
    label { display: block; font-size: 12px; color: #555; margin-bottom: 4px; }
    input[type=range] { width: 100%; }
    .value-display { font-size: 11px; color: #888; }
    button { width: 100%; margin-top: 4px; padding: 6px; cursor: pointer; }
  </style>
</head>
<body>
  <div id="sidebar">
    <!-- FIXED: Seed controls -->
    <div class="control-group">
      <label>Seed: <span id="seed-display">42</span></label>
      <button onclick="prevSeed()">◀ Prev</button>
      <button onclick="nextSeed()">Next ▶</button>
      <button onclick="randomSeedFn()">Random</button>
      <input type="number" id="seed-input" placeholder="Jump to seed">
      <button onclick="jumpSeed()">Go</button>
    </div>
    <!-- VARIABLE: Parameter controls (one per param) -->
    <div class="control-group">
      <label>Particle Count: <span class="value-display" id="particleCount-display">2000</span></label>
      <input type="range" id="particleCount" min="500" max="5000" step="100" value="2000"
             oninput="updateParam('particleCount', +this.value)">
    </div>
    <!-- FIXED: Action buttons -->
    <button onclick="regenerate()">Regenerate</button>
    <button onclick="resetDefaults()">Reset</button>
    <button onclick="saveCanvas('artwork', 'png')">Download PNG</button>
  </div>
  <div id="canvas-container"></div>
  <script>
    // All p5.js code inline here
    // params object, classes, setup(), draw(), UI handlers
  </script>
</body>
</html>
```

---

## Hard Rules

- **Always seed randomness** — `randomSeed(params.seed)` and `noiseSeed(params.seed)` in `setup()`. Same seed MUST produce identical output every time.
- **Never create separate .js files** — the artifact is one self-contained HTML file. All code inline. p5.js from CDN only.
- **Never copy another artist's specific algorithm** — create original generative systems. Drawing inspiration from aesthetic traditions is fine; copying a named artist's exact implementation is not.
- **Philosophy before code** — write the algorithmic philosophy first, output it as a `.md` artifact, then implement. Never skip this step.
- **Parameters must be meaningful** — every slider must correspond to a real, perceptible change in the artwork. No dead sliders.
- **Canvas size 1200×1200** — use this as the default unless the user specifies otherwise.
- **Never generate static images as the primary output** — the artifact must have seed navigation (prev/next/random) so users can explore the variation space.

---

## What NOT to Do

| Anti-pattern | Why it fails | Correct approach |
|---|---|---|
| `fill(random(255), random(255), random(255))` on every frame | Produces visual chaos, not art | Design a deliberate palette; derive color from system state (velocity, age, position) |
| Thousands of `if (random() < 0.5)` branches with no philosophy | Noise without structure | Let the philosophy dictate where randomness lives and where order holds |
| Separate `sketch.js` file alongside the HTML | Breaks self-containment; won't work as a standalone artifact | Embed all JS inline in the `<script>` tag |
| Skipping `randomSeed` and `noiseSeed` | Output changes every run; seeds become meaningless | Call both seed functions at the top of `setup()` |
| `createCanvas(400, 400)` | Too small for gallery-quality output | Default 1200×1200; allow user override |
| Describing what will be drawn instead of the philosophical system | Produces literal, uninspired results | Articulate the computational worldview and forces; let the code discover the visuals |

---

## Quick Reference

| Phase | Output | Key question |
|---|---|---|
| Philosophy | `.md` artifact | What is the computational worldview driving this system? |
| Implementation | `.html` artifact | What sliders emerge naturally from the philosophy's parameters? |
| Seed navigation | Built into HTML | Can the user explore 1000 variations without any new code? |
| Reproducibility | Seeded PRNG | Does seed 42 always produce the exact same image? |

**Checklist before delivering the artifact:**
- [ ] Philosophy written and output as `.md`
- [ ] `randomSeed` and `noiseSeed` called with `params.seed` in `setup()`
- [ ] Every parameter has a UI slider/input
- [ ] Prev/Next/Random/Jump seed controls present and functional
- [ ] Regenerate, Reset, Download PNG buttons present and functional
- [ ] No external files — everything inline, p5.js from CDN
- [ ] Canvas renders immediately with no user setup

---

## Supporting Files

### Color palettes (`references/palettes.md`)

Load this when the user asks for specific moods or when choosing a palette. It contains 8 named palettes (dark and light background), gradient helpers for depth/velocity/age mapping, and anti-patterns to avoid. Use it to select `params.palette` before writing code.

### Artifact validator (`scripts/validate_artifact.sh`)

After generating the HTML artifact, run this script to verify all required structural elements are present:

```bash
bash scripts/validate_artifact.sh <path-to-artifact.html>
```

Checks: `randomSeed`/`noiseSeed` calls, 1200×1200 canvas, p5.js CDN link, seed navigation UI, Regenerate/Reset/Download buttons, no local `.js` file references. Exit 0 = all pass.
