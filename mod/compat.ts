// Pure version helpers for the mod's host-version gates. Nothing here touches `$`:
// the caller reads `$.session.version()` at its own call site and hands the
// string in. The gates exist because the npm `stable` channel trails `latest`
// (2.1.292 against 2.1.302 at the time of writing): a tree that uses a prop the
// host does not know is not drawn at all ("the engine draws its own"), so every
// newer prop is used only where the host is known to read it, and the 2.1.287
// tree is the fallback everywhere else — including when the version is unknown.

/** `Text` `weight` (and `size`/`mono`/`tabular`) replaced `bold` here. */
export const TYPOGRAPHY_SINCE = '2.1.299'

/** The three numbers of a release version, or null for anything that is not one. */
export function parseVersion(version: string | undefined): [number, number, number] | null {
  if (!version) return null
  const m = version.match(/^(\d+)\.(\d+)\.(\d+)/)
  if (!m) return null
  return [Number(m[1]), Number(m[2]), Number(m[3])]
}

/** Whether `version` is `min` or later. Unknown or unparseable reads as older. */
export function atLeast(version: string | undefined, min: string): boolean {
  const a = parseVersion(version)
  const b = parseVersion(min)
  if (!a || !b) return false
  for (let i = 0; i < 3; i += 1) {
    const x = a[i] ?? 0
    const y = b[i] ?? 0
    if (x !== y) return x > y
  }
  return true
}

/** Whether the host reads `Text` `weight` rather than the deprecated `bold`. */
export function hasTypography(version: string | undefined): boolean {
  return atLeast(version, TYPOGRAPHY_SINCE)
}

/**
 * The props that draw a run of text heavy: `weight` on a host that reads it,
 * `bold` (read as `weight: 'semibold'` since 2.1.299, drawn bold before) elsewhere.
 */
export function strongText(version: string | undefined): { weight: 'semibold' } | { bold: true } {
  return hasTypography(version) ? { weight: 'semibold' } : { bold: true }
}
