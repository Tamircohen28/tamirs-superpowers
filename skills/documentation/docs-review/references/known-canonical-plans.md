# Known Canonical Plan-Shaped Filenames

Files whose names match the plan-detector's filename pattern but ARE canonical
reference material. The detector should NOT untrack these. If the detector
flags one of these, treat it as a false positive.

Add entries here when a new plan-shaped doc becomes canonical.

| Path | Why it's canonical |
|---|---|
| `docs/engineering/build-and-release/release-plan.md` | Hypothetical example — replace with actual canonical entries as they appear |

## How to update this list

Add a row per canonical plan-shaped file. Keep the "why" column short and
specific — e.g. "Required by the release workflow", "Linked from
`docs/user/README.md`", "Referenced in CLAUDE.md Fast Lane".

## Anti-pattern

If a file is NOT in this list and `detect-plan-files.sh` reports a score >= 2,
default to untracking it. Don't add entries here just to silence the detector
— that defeats the audit. Only add entries when the file genuinely has a
canonical home and a downstream consumer.
