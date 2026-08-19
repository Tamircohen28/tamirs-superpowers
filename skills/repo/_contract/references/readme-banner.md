# README hero banner — art direction and quality bar

The banner is the first thing anyone sees, and for most people it is the *only* thing they
see. Two of this fleet's repos have banners people like (`tamirs-superpowers/assets/banner.png`,
`st-claude/assets/banner.jpg`); several have a dark rectangle with the repo name typeset in
the middle. The difference was not talent — it was the brief. The old instruction said:

> SVG hero banner (600×200). Center the repo name in Space Grotesk bold on a dark
> background (#0F1117), subtitle line in gray (#8B949E), subtle accent stripe…
> Keep it minimal — name + one-line description, no clip-art.

That brief *is* "a plain image of text". It forbids the illustration and then asks for a
picture. This file replaces it.

## The contract

| Item | Value |
|---|---|
| Path | `assets/banner.<ext>`, `<ext>` one of `png`, `jpg`, `webp`, `svg` |
| Referenced from | first line of `README.md`, inside `<p align="center">` |
| Displayed width | `600`–`830` |
| Source aspect | between 1.5:1 and 5:1 (3:1 is a good default; the reference rasters are 2:1) |
| Preferred form | **raster** (`png`/`jpg`) when a render step is available; **SVG is fully acceptable** and stays dependency-free |
| Enforced by | `skills/repo/_contract/scripts/check-readme-branding.sh` → gap **S1-14** |

`repo-scaffold` used to say `assets/banner.svg` while the two repos people actually like ship
`banner.png` and `banner.jpg`. All four extensions are legal; the extension was never the
problem.

## Art direction

**Start from a motif, not from the name.** Ask what the project *does*, and find one object
or one relationship that shows it. The reference banners do exactly this:

- `tamirs-superpowers` — a code/terminal window floating in the centre, ringed by glowing
  rounded-square tool icons (branch, chat, search, checklist, bolt) over a faint circuit
  trace. The motif is "one toolkit, many capabilities", which is what the repo is.
- `scaffold-plugin-gold` — one lit core node fanning out along conduits to five adapter
  tiles. The motif is the canonical→adapters model the fixture exists to pin.
- `scaffold-gold` — three depth-stacked gates carrying a check mark, with a rising bar
  series beside them: the profile's P1/P2/P3 exit gate.

**Then build the picture:**

1. **Composition.** Wordmark left, motif right (or motif centre with the name inside it).
   Never a centred line of text on an empty field. Leave real negative space; do not fill
   the canvas edge to edge with content.
2. **Depth.** Layer at least three planes: background field, mid-ground motif, foreground
   accent. Get depth from overlap, slight rotation, opacity falloff and a soft radial glow —
   not from a drop-shadow filter alone.
3. **Palette.** Two brand hues plus one near-black ground (`#0B0E14`–`#111726` reads well in
   both GitHub themes) and one near-white for type. Use a gradient for the hero object so it
   is not a flat silhouette.
4. **Substrate.** A faint grid, circuit trace, or contour at ~6% contrast gives the field
   texture and stops the background reading as an empty rectangle.
5. **Type.** Repo name at 46–64px, one subtitle line at ~21px in `#8B949E`. Two text
   elements is the target, three the maximum. **No emoji, ever** — as glyph art they render
   as tofu wherever the font is missing, which is exactly where a banner gets screenshotted.
6. **Self-contained.** No external font, image or stylesheet reference. Web-safe stack with
   fallbacks (`'Segoe UI', Helvetica, Arial, sans-serif`); a raster has the type baked in.

## Quality bar — observable, not a matter of taste

`check-readme-branding.sh` decides these mechanically. Thresholds live in
`standards-contract.json` under `profiles.<profile>.readme.banner`.

**SVG** — all of the following:

| Criterion | Threshold | What it rules out |
|---|---|---|
| Non-text shapes (`path`/`rect`/`circle`/`ellipse`/`polygon`/`polyline`/`line`) | ≥ **16** | a background rect + an accent stripe |
| `<text>` elements | ≤ **3** | a paragraph typeset as a picture |
| Shapes per text element | ≥ **5** | text dominating the composition |
| Depth | at least one `linearGradient`, `radialGradient`, `filter`, `mask`, `clipPath`, or `opacity` | flat two-colour wordmarks |
| `<title>` + `<desc>` | present, and `<desc>` names the motif and its relation to the project | a picture nobody can justify |
| Emoji codepoints anywhere in the file | **zero** | emoji used as clip-art |

**Raster** (`png`/`jpg`/`webp`):

| Criterion | Threshold |
|---|---|
| File size | ≥ **20 000 bytes** |
| Width | ≥ **800 px** |
| Aspect ratio | 1.5:1 – 5:1 |

The `<desc>` requirement is the one a human still has to mean: *"the motif relates to the
project's purpose"* cannot be measured, but a banner whose author cannot write that sentence
in `<desc>` does not have a motif. Write the sentence first, then draw it.

## Producing one

**SVG (default — no toolchain, works everywhere).** Author it by hand against the criteria
above; `scaffold-gold` and `scaffold-plugin-gold` under
`skills/repo/_contract/fixtures/*/assets/banner.svg` are the worked examples to copy the
structure of (defs → ground → substrate → glow → motif → wordmark).

**Raster.** Produce a 1280×640 or 1200×400 image with an image model or a design tool, save
it as `assets/banner.png` (or `.jpg`), and keep it under ~2 MB. Prefer this when the project
has a visual identity worth rendering properly — it is what the two well-liked banners are.

**Verify before you commit, both forms:**

```bash
bash skills/repo/_contract/scripts/check-readme-branding.sh <repo-root>
```

For an SVG, also look at it — the checker proves the file is a graphic, not that the graphic
is any good:

```bash
qlmanage -t -s 1200 -o /tmp/preview assets/banner.svg   # macOS
rsvg-convert -w 1200 assets/banner.svg > /tmp/banner.png # linux
```

## Footer

The README footer is a **text** line, not a second image. One line, after a `---` rule:

```markdown
---

MIT © [Tamir Cohen](https://github.com/Tamircohen28)
```

Repos that also carry a social-preview image put it at `assets/social-preview.png` and wire
it through the GitHub repo settings, never as a second inline image in the README body.
