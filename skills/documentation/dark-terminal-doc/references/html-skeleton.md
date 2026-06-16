# Dark Terminal Doc — HTML Skeleton

Paste this skeleton and fill in the blanks. Never add external JS, CDN scripts, or separate CSS files.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tool A vs Tool B — Technical Comparison</title>
<style>
  /* === PASTE FULL CSS FROM css-design-system.md HERE === */
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
      <td class="col-notes">Larger projects fit without chunking <span class="winner-badge winner-brand-a">tool-a wins</span></td>
    </tr>

    <!-- Add more rows here -->

  </tbody>
</table>
</div>

<!-- Summary cards (comparison docs only — omit for cheatsheets/changelogs) -->
<div style="max-width:1200px; margin:32px auto 0; display:flex; gap:20px; flex-wrap:wrap;">
  <!-- one card per brand + one tie card — see css-design-system.md -->
</div>

</body>
</html>
```

## Document type variants

| Type | Columns | Summary cards? | Legend? |
|------|---------|---------------|---------|
| Comparison | Feature / Category / Brand-A / Brand-B / Notes | Yes | Yes |
| Reference / cheatsheet | Command / Syntax / Description / Example | No | No |
| Changelog / release notes | Version / Date / Change / Impact | No | No |
| Feature breakdown | Feature / Status / Notes | No | Optional |
| API doc | Endpoint / Method / Auth / Description | No | No |
