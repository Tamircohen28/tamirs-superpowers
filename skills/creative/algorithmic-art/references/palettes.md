# Generative Art Color Palettes

Curated palettes for use in algorithmic art. Each palette is designed with generative systems in mind:
- Sufficient contrast between the darkest and lightest colors
- Hues that blend naturally when drawn at low opacity (trail accumulation)
- Named to help articulate the algorithmic philosophy

## How to use

In the `params` object, specify a palette by name and map it to the hex array:

```javascript
let palettes = {
  'nocturnal-tide': ['#0d0d1a', '#1a2744', '#0f3d6b', '#1a7abf', '#5fbcd3', '#b8e4f5'],
  'ember-drift':    ['#1a0a00', '#5c1a00', '#b34700', '#e87722', '#f5c842', '#fff8e7'],
  // ...
};
let params = {
  seed: 42,
  palette: 'nocturnal-tide',
  // ...
};
// Usage: color(random(palettes[params.palette]))
```

---

## Dark-background palettes (most common for generative art)

### Nocturnal Tide
Deep ocean blues bleeding into pale aqua. Trail accumulation creates depth gradients.
```
['#0d0d1a', '#1a2744', '#0f3d6b', '#1a7abf', '#5fbcd3', '#b8e4f5']
```

### Ember Drift
Burnt orange and amber on near-black. Conveys heat, rust, organic decay.
```
['#1a0a00', '#5c1a00', '#b34700', '#e87722', '#f5c842', '#fff8e7']
```

### Twilight Interference
Purple-pink interference bands. Good for Lissajous / wave systems.
```
['#0d0014', '#2d0045', '#6600aa', '#cc00cc', '#ff66cc', '#ffccee']
```

### Chlorophyll Noise
Deep forest greens to pale yellow-green. Natural, biological.
```
['#050f00', '#0d2b00', '#1a5200', '#3d8c00', '#7ec850', '#d4f0a0']
```

### Bone Structure
Near-white on black. Stark, architectural. Good for recursive / fractal systems.
```
['#000000', '#1a1a1a', '#3d3d3d', '#8a8a8a', '#d4d4d4', '#f5f5f5']
```

### Thermograph
Scientific palette — cold blue to hot red through teal/yellow. Good for field visualizations.
```
['#0a0033', '#003399', '#00aacc', '#00cc66', '#ffcc00', '#ff3300']
```

---

## Light-background palettes

### Ink on Vellum
Warm cream background with sepia and charcoal marks. Printmaking aesthetic.
```
['#f5f0e8', '#d4c9b0', '#8c7355', '#4a3728', '#1a0f05', '#8b4513']
```

### Botanical Survey
Pale sage and moss greens on off-white. Naturalist illustration feel.
```
['#f0f5e8', '#c8d9b0', '#7a9e5c', '#3d6b2a', '#1a3d0f', '#8b6914']
```

---

## Multi-stop gradients for depth mapping

Use these when color should encode recursion depth, velocity, age, or field magnitude.

### Root to Blossom (for recursive trees)
```javascript
// Interpolate by normalized depth (0.0 = root, 1.0 = tip)
function depthColor(t) {
  // t: 0 → 1
  let r = lerp(80,  255, t);
  let g = lerp(40,  200, t);
  let b = lerp(10,  180, t);
  return color(r, g, b);
}
```

### Velocity Heat (for particle systems)
```javascript
// speed: 0 → maxSpeed
function speedColor(speed, maxSpeed) {
  let t = constrain(speed / maxSpeed, 0, 1);
  let r = lerp(20,  255, t);
  let g = lerp(20,   80, t);
  let b = lerp(80,   20, t);
  return color(r, g, b);
}
```

### Age Fade (for trail systems)
```javascript
// age: 0 (birth) → maxLife (death)
function ageAlpha(age, maxLife, baseAlpha) {
  return baseAlpha * (1 - age / maxLife);
}
```

---

## Anti-patterns to avoid

| Pattern | Problem | Fix |
|---|---|---|
| `fill(random(255), random(255), random(255))` | No palette coherence; visual chaos | Pick from a curated palette array |
| All colors at full opacity | Accumulation produces muddy grey | Use `trailAlpha: 10-30` so trails build gradually |
| Only 2 palette colors | Not enough variation for particle systems | 4-6 hues give natural variation |
| Palette with colors too close in value | Low contrast — art looks flat | Ensure dark-to-light range spans at least 3 stops |
