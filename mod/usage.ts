// Pure formatters for the rate-limit band, the toast and native notification it
// raises, and the usage line drawn where no status line exists. Data in, text
// out; `$` never comes here.
import type { ModsLimitWarning, ModsUsage } from './types'

/** `session.measure` window kinds as the band abbreviates them. */
export const RATE_WINDOWS: Record<string, string> = { five_hour: '5h', seven_day: '7d', spend_limit: 'spend' }

/** The VS Code surface cuts a status line at 200 characters and a toast at 500. */
export const STATUS_MAX = 200
export const TOAST_MAX = 500

export function windowLabel(kind: string): string {
  return RATE_WINDOWS[kind] ?? kind
}

/** `text` cut to `max` characters, an ellipsis marking the cut. */
export function clip(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, Math.max(0, max - 1))}…`
}

/** `2h10m` or `35m` until `resetsAt`, or '' when unknown or already past. */
export function resetsIn(resetsAt: string | undefined, now: number): string {
  if (!resetsAt) return ''
  const ms = Date.parse(resetsAt) - now
  if (!Number.isFinite(ms) || ms <= 0) return ''
  const m = Math.round(ms / 60000)
  return m >= 60 ? `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}m` : `${m}m`
}

/** `ctx 12% · 5h 40% (resets 2h10m) · 7d 31% · $1.50` — the statusline figures. */
export function usageLine(u: ModsUsage, now: number): string {
  const parts: string[] = []
  if (u.contextPercent !== undefined) parts.push(`ctx ${u.contextPercent}%`)
  for (const w of u.rateLimits) {
    const reset = resetsIn(w.resetsAt, now)
    parts.push(`${windowLabel(w.kind)} ${Math.round(w.percentUsed)}%${reset ? ` (resets ${reset})` : ''}`)
  }
  if (u.costUsd !== undefined) parts.push(`$${u.costUsd.toFixed(2)}`)
  return parts.join(' · ')
}

/** The band's headline: `5h limit 92%`. */
export function limitHeadline(w: ModsLimitWarning): string {
  return `${windowLabel(w.kind)} limit ${Math.round(w.percentUsed)}%`
}

/** The band's instruction, with the reset when known. */
export function limitInstruction(w: ModsLimitWarning, now: number): string {
  const reset = resetsIn(w.resetsAt, now)
  return `${reset ? `resets in ${reset} · ` : ''}hand off before the window closes: type /switch-dev handoff`
}

/** The toast and the native notification's body, one line. */
export function limitAlert(w: ModsLimitWarning, now: number): string {
  const reset = resetsIn(w.resetsAt, now)
  return clip(`${windowLabel(w.kind)} limit at ${Math.round(w.percentUsed)}%${reset ? `, resets in ${reset}` : ''} — write a handoff now`, TOAST_MAX)
}

/** One toast per 5-point step of a window: the key that tells two apart. */
export function crossingKey(w: ModsLimitWarning): string {
  return `${w.kind}:${Math.floor(w.percentUsed / 5)}`
}

/** The window nearest its limit, or undefined with none reported. */
export function worstWindow(u: ModsUsage): ModsUsage['rateLimits'][number] | undefined {
  return [...u.rateLimits].sort((a, b) => b.percentUsed - a.percentUsed)[0]
}

/** The `rate-limit.dismissed` store value: dismissal percentage per window kind. */
export function dismissedMap(v: unknown): Record<string, number> {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return {}
  const out: Record<string, number> = {}
  for (const [k, n] of Object.entries(v as Record<string, unknown>)) {
    if (typeof n === 'number' && Number.isFinite(n)) out[k] = n
  }
  return out
}
