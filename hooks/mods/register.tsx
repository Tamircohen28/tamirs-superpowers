// tamirs-superpowers mod — Claude Code >= 2.1.287 function hooks.
//
// WHAT THIS IS, AND WHAT IT IS NOT
//   A mod runs IN-PROCESS on Claude Code and the Claude Desktop Code tab. It can
//   draw (a pane, the band above the prompt, the spinner), react to state the
//   host PUSHES (`session.measure`), and act before a turn dies. The bash hooks
//   in hooks/hooks.json can do none of those three things.
//
//   It is ADDITIVE. Every guard, every worktree hook and every reminder in
//   hooks/*.sh stays canonical, because those run on Codex and (via
//   platforms/cursor/hooks.json) Cursor too, and a mod never will. Nothing here
//   denies a tool call, creates a worktree, or replaces a bash hook. Where a
//   feature below overlaps one (rate-limit-handoff.sh, check-done.sh,
//   precompact-snapshot.sh, skill-suggest.sh, notify-pushover.sh), the bash hook
//   is the fallback that still fires when this module cannot load — an org with
//   `allowManagedModsOnly`, `--safe-mode`, a VS Code chat panel.
//
// WHAT IT DOES
//   1. Objective pane + /objective — the orchestration state orchestrate-dev
//      and worker-dev keep in .dev-files/objectives/<id>/ (objective.json,
//      tasks/*.json, handoffs/*.json) drawn live; `/objective` answers at once,
//      with no model turn, even mid-turn (`immediate`). Spinner suffix counts
//      workers in flight; a task-notification row is drawn compact.
//   2. Rate-limit band — `session.measure` pushes rate-limit windows after every
//      turn. At `rate_limit_warn_percent` the band above the prompt shows a
//      one-press "Write handoff" that submits a switch-dev handoff prompt.
//      rate-limit-handoff.sh fires AFTER the turn died; this fires BEFORE.
//   3. Usage line on Desktop — the figures scripts/statusline.sh draws on the
//      CLI, where Desktop has no status line to draw into.
//   4. Pushover on long or failed main-session turns — with the manifest's
//      pushover_token/pushover_user (or the same env/file sources
//      scripts/notify-pushover.sh reads), via $.http.fetch; no curl, no subprocess.
//   5. Semantic skill suggestion — opt-in (`semantic_skill_suggest`): a small
//      model classifies a long prompt against the bundled skill names and the
//      match is attached as context to the prompt. skill-suggest.sh's keyword
//      matching keeps running regardless.
//   6. Definition-of-done line under an answer that wrote files (turn.complete),
//      a working-state snapshot folded into compaction instructions
//      (session.compact), and the repo's Co-Authored-By trailer policy enforced
//      on the commit attribution text when the repo's CLAUDE.md declares one.
//
// BUDGET
//   Every hook has 10 s of its own time per dispatch; `next` and `$` calls do
//   not count. Nothing here sleeps. The objective re-read is bounded by the
//   number of tasks (a handful of small JSON files).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, PluginOptions, Register } from 'claude-code'

import type {
  ModsLimitWarning,
  ModsObjective,
  ModsObjectiveTask,
  ModsUsage,
} from './types'

const PLUGIN = 'tamirs-superpowers'
const PANE = 'objective'

// $.state references: literal plugin/key pairs, declared in types/index.d.ts.
const objective = atom({ plugin: 'tamirs-superpowers', key: 'objective' } as const, null)
const usage = atom({ plugin: 'tamirs-superpowers', key: 'usage' } as const, null)
const limitWarning = atom({ plugin: 'tamirs-superpowers', key: 'limitWarning' } as const, null)
const dismissedAtPercent = atom({ plugin: 'tamirs-superpowers', key: 'dismissedAtPercent' } as const, 0)
const workers = atom({ plugin: 'tamirs-superpowers', key: 'workers' } as const, 0)

// The skills a prompt is classified against (feature 5). Names only: the
// classifier reads them as labels, and `none` is the label for "no skill".
// Internal companions (changelog-review, docs-review, mcp-pagination) are left
// out — they are not for the person to invoke.
const SKILL_LABELS = [
  'plan-dev', 'start-dev', 'orchestrate-dev', 'worker-dev', 'deliver-dev', 'pr-dev', 'switch-dev', 'decision',
  'targeted-debug', 'diagnose-refusal',
  'repo-scaffold', 'repo-standards', 'multi-agent-repo', 'github-policy', 'cleanup',
  'skill-creator', 'find-skill', 'retro', 'session-report', 'notify-setup', 'capture-config', 'usage-capture',
  'mcp-builder', 'platform-sync', 'field-notebook-ui', 'dark-terminal-doc',
  'none',
] as const

const WRITE_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])
const RATE_WINDOWS: Record<string, string> = { five_hour: '5h', seven_day: '7d', spend_limit: 'spend' }

function asNumber(v: unknown, fallback: number): number {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN
  return Number.isFinite(n) ? n : fallback
}

function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length
}

function resetsIn(resetsAt: string | undefined, now: number): string {
  if (!resetsAt) return ''
  const ms = Date.parse(resetsAt) - now
  if (!Number.isFinite(ms) || ms <= 0) return ''
  const m = Math.round(ms / 60000)
  return m >= 60 ? `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}m` : `${m}m`
}

function usageLine(u: ModsUsage, now: number): string {
  const parts: string[] = []
  if (u.contextPercent !== undefined) parts.push(`ctx ${u.contextPercent}%`)
  for (const w of u.rateLimits) {
    const label = RATE_WINDOWS[w.kind] ?? w.kind
    const reset = resetsIn(w.resetsAt, now)
    parts.push(`${label} ${Math.round(w.percentUsed)}%${reset ? ` (resets ${reset})` : ''}`)
  }
  if (u.costUsd !== undefined) parts.push(`$${u.costUsd.toFixed(2)}`)
  return parts.join(' · ')
}

async function readJson($: EngineInterface, path: string): Promise<Record<string, unknown> | null> {
  if (!(await $.fs.exists(path))) return null
  try {
    const v: unknown = JSON.parse(await $.fs.read(path))
    return v && typeof v === 'object' ? (v as Record<string, unknown>) : null
  } catch {
    return null
  }
}

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)

// The active objective under <root>/.dev-files/objectives, as hooks/lib/
// objective-common.sh and skills/dev-workflow/_shared/scripts/objective-state.sh
// lay it out. SUPERPOWERS_OBJECTIVE_ID wins; else the first `active` one; else
// the first not completed/abandoned.
async function loadObjective($: EngineInterface, root: string, preferredId: string | undefined, now: number): Promise<ModsObjective | null> {
  const dir = `${root}/.dev-files/objectives`
  if (!(await $.fs.exists(dir))) return null
  const ids = (await $.fs.list(dir)).filter(e => e.kind === 'dir').map(e => e.name).sort()
  const ordered = preferredId && ids.includes(preferredId) ? [preferredId, ...ids.filter(i => i !== preferredId)] : ids
  let fallback: { id: string; obj: Record<string, unknown> } | null = null
  let chosen: { id: string; obj: Record<string, unknown> } | null = null
  for (const id of ordered) {
    const obj = await readJson($, `${dir}/${id}/objective.json`)
    if (!obj) continue
    const status = str(obj.status) ?? ''
    if (id === preferredId || status === 'active') { chosen = { id, obj }; break }
    if (!fallback && status !== 'completed' && status !== 'abandoned') fallback = { id, obj }
  }
  const pick = chosen ?? fallback
  if (!pick) return null
  const taskIds = Array.isArray(pick.obj.tasks) ? pick.obj.tasks.filter((t): t is string => typeof t === 'string') : []
  const tasks: ModsObjectiveTask[] = []
  for (const tid of taskIds.slice(0, 50)) {
    const t = await readJson($, `${dir}/${pick.id}/tasks/${tid}.json`)
    const h = await readJson($, `${dir}/${pick.id}/handoffs/${tid}.json`)
    tasks.push({
      id: tid,
      title: str(t?.title) ?? tid,
      status: str(t?.status) ?? 'pending',
      role: str(t?.role),
      branch: str(t?.branch),
      handoff: str(h?.status),
    })
  }
  return { id: pick.id, title: str(pick.obj.title) ?? pick.id, status: str(pick.obj.status) ?? 'unknown', tasks, readAt: now }
}

function objectiveText(o: ModsObjective | null): string {
  if (!o) return 'No objective is active (nothing under .dev-files/objectives). /plan-dev writes one.'
  const lines = [`Objective ${o.id} — ${o.title} [${o.status}]`]
  for (const t of o.tasks) {
    const tail = [t.role, t.branch, t.handoff ? `handoff: ${t.handoff}` : ''].filter(Boolean).join('  ')
    lines.push(`  ${t.id}  ${t.status.padEnd(9)}  ${t.title}${tail ? `  (${tail})` : ''}`)
  }
  if (o.tasks.length === 0) lines.push('  (no tasks yet)')
  return lines.join('\n')
}

// Re-reads the objective from disk into $.state; the pane and /objective draw
// from the state, never from disk directly.
async function refreshObjective($: EngineInterface, dir: string): Promise<ModsObjective | null> {
  const preferred = await $.env.get('SUPERPOWERS_OBJECTIVE_ID')
  const now = await $.clock.now()
  const next = await loadObjective($, dir, preferred, now)
  await update($, objective, () => next)
  return next
}

// Pushover credentials in the precedence scripts/notify-pushover.sh uses: the
// environment, then the manifest's userConfig (`options`, or the
// CLAUDE_PLUGIN_OPTION_* form the host exports to hooks), then
// ~/.claude/pushover.env (written by scripts/install.sh).
async function pushoverCredentials($: EngineInterface, options: PluginOptions): Promise<{ token: string; user: string } | null> {
  let token = (await $.env.get('PUSHOVER_TOKEN')) || str(options.pushover_token) || (await $.env.get('CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN')) || ''
  let user = (await $.env.get('PUSHOVER_USER')) || str(options.pushover_user) || (await $.env.get('CLAUDE_PLUGIN_OPTION_PUSHOVER_USER')) || ''
  if (!token || !user) {
    const home = await $.env.get('HOME')
    const file = home ? `${home}/.claude/pushover.env` : ''
    if (file && (await $.fs.exists(file))) {
      const text = await $.fs.read(file)
      const pick = (name: string) => text.match(new RegExp(`^\\s*(?:export\\s+)?${name}=["']?([^"'\\n]+)`, 'm'))?.[1]?.trim()
      token ||= pick('PUSHOVER_TOKEN') ?? ''
      user ||= pick('PUSHOVER_USER') ?? ''
    }
  }
  return token && user ? { token, user } : null
}

type TurnSummary = { answer: string; durationMs: number; reason: string }

// One Pushover message for a finished or failed main-session turn. A network
// failure is swallowed: it is not the turn's problem, and notify-pushover.sh
// swallows the same failure for the same reason.
async function notifyPushover($: EngineInterface, e: TurnSummary, options: PluginOptions, minMs: number, project: string): Promise<void> {
  if (e.reason === 'answer' && e.durationMs < minMs) return
  const creds = await pushoverCredentials($, options)
  if (!creds) return
  const secs = Math.round(e.durationMs / 1000)
  const head = e.reason === 'error' ? 'Turn ended on an API error' : `Turn finished (${secs}s)`
  const snippet = e.answer.replace(/\s+/g, ' ').trim().slice(0, 300)
  const body = new URLSearchParams({
    token: creds.token,
    user: creds.user,
    title: `Claude Code — ${project}`.slice(0, 250),
    message: `${head}${snippet ? `: ${snippet}` : ''}`.slice(0, 1024),
    priority: e.reason === 'error' ? '1' : '0',
  }).toString()
  try {
    await $.http.fetch('https://api.pushover.net/1/messages.json', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
    })
  } catch {
    // see above
  }
}

const STATUS_COLOR: Record<string, string> = {
  running: 'yellow', completed: 'green', failed: 'red', blocked: 'red', cancelled: 'gray', ready: 'cyan', pending: 'gray',
}

export const register: Register = (on, options) => {
  const warnAt = Math.min(100, Math.max(50, asNumber(options.rate_limit_warn_percent, 85)))
  const pushoverMinMs = Math.max(0, asNumber(options.pushover_min_turn_seconds, 120)) * 1000
  const semanticSuggest = options.semantic_skill_suggest === true

  // Module variables: reset on a hot reload, which is fine for all of them.
  let root = ''
  let cwd = ''
  let trailerPolicy: string | null = null
  let writesThisTurn = 0
  let lastToastedKind = ''
  const suggested = new Set<string>()

  // ---------------------------------------------------------------- startup
  on('session.start', async ($, e, next) => {
    cwd = e.cwd
    try {
      root = await $.session.root()
    } catch {
      root = e.cwd
    }
    // The repo's commit-trailer policy, when it declares one (CLAUDE.md
    // "Commit trailer"). Enforced in attribution.text below; a repo without the
    // line gets no trailer added by this mod.
    trailerPolicy = null
    try {
      const claudeMd = await $.fs.exists(`${root}/CLAUDE.md`) ? await $.fs.read(`${root}/CLAUDE.md`) : ''
      const m = claudeMd.match(/^\s*(Co-Authored-By:\s*Claude\s*<[^>\n]+>)\s*$/im)
      if (m?.[1]) trailerPolicy = m[1].trim()
    } catch {
      trailerPolicy = null
    }
    await $.command.register({
      name: 'objective',
      description: 'Show the active orchestration objective and its tasks (tamirs-superpowers)',
      immediate: true,
    })
    await refreshObjective($, root || cwd)
    // Re-read every 5 s while an objective exists; a cheap exists() otherwise.
    $.clock.every(5000, () => {
      void refreshObjective($, root || cwd)
    })
    return next(e)
  })

  // ------------------------------------------------------- 1. objective pane
  on('command.run', { command: 'objective' }, async $ => {
    const o = await refreshObjective($, root || cwd)
    if (o) void $.ui.open({ id: PANE, title: `Objective ${o.id}` })
    return { text: objectiveText(o) }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const o = await read($, objective)
    const n = await read($, workers)
    const width = Math.max(20, e.props.bodyColumns)
    if (!o) {
      return (
        <Box flexDirection="column">
          <Text dimColor>No objective is active.</Text>
          <Text dimColor>/plan-dev writes one under .dev-files/objectives/.</Text>
        </Box>
      )
    }
    const done = o.tasks.filter(t => t.status === 'completed').length
    return (
      <Box flexDirection="column">
        <Text bold wrap="truncate-end">{o.id} · {o.title}</Text>
        <Text dimColor>
          {o.status} · {done}/{o.tasks.length} tasks done{n > 0 ? ` · ${n} worker${n === 1 ? '' : 's'} running` : ''}
        </Text>
        {o.tasks.map(t => (
          <Box key={t.id} flexDirection="row" gap={1}>
            <Text dimColor>{t.id}</Text>
            <Text color={STATUS_COLOR[t.status] ?? 'white'}>{t.status.padEnd(9)}</Text>
            <Text wrap="truncate-end">{t.title.slice(0, Math.max(8, width - 30))}</Text>
            {t.handoff ? <Text dimColor>handoff:{t.handoff}</Text> : null}
          </Box>
        ))}
        {o.tasks.length === 0 ? <Text dimColor>(no tasks yet)</Text> : null}
      </Box>
    )
  })

  on('agent.spawn', async ($, e, next) => {
    await update($, workers, n => (n ?? 0) + 1)
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    const n = await read($, workers)
    if (n <= 0) return next(e)
    return next({ ...e, props: { ...e.props, suffix: `${e.props.suffix ?? ''} · ${n} worker${n === 1 ? '' : 's'}` } })
  })

  // A background task's notification row, compact: the id, how it ended and
  // how long it took. ctrl+o (isExpanded) still shows the engine's full row.
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'task-notification' } } }, async ($, e, next) => {
    const task = e.props.task
    if (e.props.isExpanded || !task || (!task.id && !task.status)) return next(e)
    const { Text } = $.ui.resolve(e)
    const secs = task.durationMs !== undefined ? ` · ${Math.round(task.durationMs / 1000)}s` : ''
    const status = task.status ?? 'done'
    const color = status === 'failed' || status === 'killed' ? 'red' : 'green'
    return (
      <Text dimColor>
        ⚙ task {task.id ?? ''} <Text color={color}>{status}</Text>{secs}
      </Text>
    )
  })

  // ------------------------------------------- 2+3. rate-limit band, usage
  on('session.measure', async ($, e, next) => {
    const now = await $.clock.now()
    const u: ModsUsage = {
      contextPercent: e.context.percent,
      rateLimits: e.rateLimits.map(w => ({ kind: w.kind, percentUsed: w.percentUsed, resetsAt: w.resetsAt })),
      costUsd: e.cost?.usd,
    }
    await update($, usage, () => u)

    const worst = [...u.rateLimits].sort((a, b) => b.percentUsed - a.percentUsed)[0]
    const dismissedAt = await read($, dismissedAtPercent)
    if (worst && worst.percentUsed >= warnAt && worst.percentUsed > dismissedAt) {
      const w: ModsLimitWarning = { kind: worst.kind, percentUsed: worst.percentUsed, resetsAt: worst.resetsAt }
      await update($, limitWarning, () => w)
      const key = `${worst.kind}:${Math.floor(worst.percentUsed / 5)}`
      if (key !== lastToastedKind) {
        lastToastedKind = key
        const reset = resetsIn(worst.resetsAt, now)
        $.ui.toast(`${RATE_WINDOWS[worst.kind] ?? worst.kind} limit at ${Math.round(worst.percentUsed)}%${reset ? `, resets in ${reset}` : ''} — write a handoff now`, { timeoutMs: 8000 })
      }
    } else if (!worst || worst.percentUsed < warnAt - 10) {
      await update($, limitWarning, () => null)
      await update($, dismissedAtPercent, () => 0)
      lastToastedKind = ''
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const warning = await read($, limitWarning)
    const u = await read($, usage)
    const showUsage = e.surface === 'desktop' && u !== null && (u.rateLimits.length > 0 || u.contextPercent !== undefined)
    if (!warning && !showUsage) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const now = await $.clock.now()
    return (
      <Box flexDirection="column">
        {warning ? (
          <Box flexDirection="row" gap={1}>
            <Text color="red" bold>
              {RATE_WINDOWS[warning.kind] ?? warning.kind} limit {Math.round(warning.percentUsed)}%
            </Text>
            <Text dimColor>{resetsIn(warning.resetsAt, now) ? `resets in ${resetsIn(warning.resetsAt, now)} ·` : ''} hand off before the window closes</Text>
            <Button
              key="handoff"
              label="Write handoff"
              hotkey="h"
              variant="primary"
              onPress={() =>
                $.prompt.submit({
                  text: `Run the switch-dev skill now: /switch-dev handoff. The ${RATE_WINDOWS[warning.kind] ?? warning.kind} rate-limit window is at ${Math.round(warning.percentUsed)}%; write the objective, task and handoff state to disk so this work resumes on another platform.`,
                })
              }
            />
            <Button
              key="dismiss"
              label="Dismiss"
              role="dismiss"
              onPress={async () => {
                await update($, dismissedAtPercent, () => warning.percentUsed)
                await update($, limitWarning, () => null)
              }}
            />
          </Box>
        ) : null}
        {showUsage && u ? <Text dimColor>{usageLine(u, now)}</Text> : null}
      </Box>
    )
  })

  // ------------------------------------------------------------ 4. pushover
  // See notifyPushover above; called from the one turn.complete hook below.

  // ----------------------------------------- 5. semantic skill suggestion
  on('prompt.submit', async ($, e, next) => {
    if (!semanticSuggest || e.origin.kind !== 'composer') return next(e)
    const text = e.text.trim()
    if (text.startsWith('/') || wordCount(text) < 12) return next(e)
    let label: string | undefined
    try {
      label = await $.model.classify(text.slice(0, 2000), SKILL_LABELS)
    } catch {
      return next(e)
    }
    if (!label || label === 'none' || !SKILL_LABELS.includes(label as (typeof SKILL_LABELS)[number]) || suggested.has(label)) return next(e)
    suggested.add(label)
    const note = `[tamirs-superpowers] The bundled skill \`${label}\` covers what this prompt asks for. Invoke it with the Skill tool (or /${label}) before doing the work by hand.`
    return next({ ...e, context: [...(e.context ?? []), note] })
  })

  // ---------------------------------------------- 6. DoD, compaction, trailer
  on('turn.start', ($, e, next) => {
    writesThisTurn = 0
    return next(e)
  })

  on('tool.call', ($, e, next) => {
    if (!e.agentId && WRITE_TOOLS.has(String(e.tool))) writesThisTurn += 1
    return next(e)
  })

  // The module's one turn.complete hook (the engine refuses a second unmatched
  // registration of an event): a worker's turn frees its spinner slot; a main
  // turn may notify Pushover and gets a DoD line when it wrote files.
  on('turn.complete', async ($, e, next) => {
    const ran = await next(e)
    if (e.agentId) {
      await update($, workers, n => Math.max(0, (n ?? 0) - 1))
      $.ui.invalidate('ui.render')
      return ran
    }
    if (e.reason === 'answer' || e.reason === 'error') {
      const project = (root || cwd).split('/').filter(Boolean).pop() ?? 'claude'
      await notifyPushover($, e, options, pushoverMinMs, project)
    }
    if (e.reason !== 'answer' || writesThisTurn === 0) return ran
    const n = writesThisTurn
    writesThisTurn = 0
    return {
      ...ran,
      text: `DoD: ${n} file write${n === 1 ? '' : 's'} this turn — before claiming done, confirm the relevant lint/typecheck/tests ran and cite the output (hooks/check-done.sh has the tier wording).`,
    }
  })

  on('session.compact', async ($, e, next) => {
    if (e.agentId) return next(e)
    const dir = root || cwd
    const lines: string[] = []
    try {
      const branch = await $.process.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], { cwd: dir, timeoutMs: 5000 })
      if (branch.exitCode === 0 && branch.stdout.trim()) lines.push(`branch: ${branch.stdout.trim()}`)
      const status = await $.process.run(['git', 'status', '--porcelain'], { cwd: dir, timeoutMs: 5000 })
      const dirty = status.stdout.split('\n').filter(Boolean)
      if (status.exitCode === 0 && dirty.length > 0) lines.push(`uncommitted (${dirty.length}): ${dirty.slice(0, 15).join('; ')}`)
    } catch {
      // Not a git checkout, or git is missing: the snapshot is just smaller.
    }
    const o = await read($, objective)
    if (o) lines.push(objectiveText(o))
    if (lines.length === 0) return next(e)
    const snapshot = `Working state to preserve verbatim in the summary (tamirs-superpowers):\n${lines.join('\n')}`
    return next({ ...e, instructions: [e.instructions, snapshot].filter(Boolean).join('\n\n') })
  })

  on('attribution.text', { kind: 'commit' }, async ($, e, next) => {
    const ran = await next(e)
    if (!trailerPolicy || /Co-Authored-By:\s*Claude/i.test(ran.text)) return ran
    return { text: `${ran.text.trimEnd()}\n${trailerPolicy}`.trim() }
  })
}
