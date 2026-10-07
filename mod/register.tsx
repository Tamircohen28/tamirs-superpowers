// tamirs-superpowers mod — Claude Code >= 2.1.287 function hooks.
//
// WHAT THIS IS, AND WHAT IT IS NOT
//   A mod runs IN-PROCESS on Claude Code and the Claude Desktop Code tab. It can
//   draw (a pane, the band above the prompt, the spinner), react to state the
//   host PUSHES (`session.measure`), and act before a turn dies. The bash hooks
//   in the hook manifest can do none of those three things.
//
//   It is ADDITIVE. Every guard, every worktree hook and every reminder in
//   the shell hook scripts stay canonical, because those run on Codex and (via
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
//      a reminder to type /switch-dev handoff; the mod submits no prompt itself.
//      rate-limit-handoff.sh fires AFTER the turn died; this fires BEFORE.
//   3. Usage line on Desktop — the figures scripts/statusline.sh draws on the
//      CLI, where Desktop has no status line to draw into.
//   4. (removed in 4.11.1) A Pushover post on long or failed turns lived here
//      as a network call. The Notification bash hook covers phone alerts, and a
//      mod that both reads the conversation and sends it out is held by the
//      directory for review, so the mod now makes no network call at all.
//   5. Semantic skill suggestion — opt-in (`semantic_skill_suggest`): a small
//      model classifies a long prompt against the bundled skill names and the
//      match is attached as context to the prompt. skill-suggest.sh's keyword
//      matching keeps running regardless.
//   6. Definition-of-done line under an answer that wrote files (turn.complete),
//      a working-state snapshot folded into compaction instructions
//      (session.compact), and the repo's Co-Authored-By trailer policy enforced
//      on the commit attribution text when the repo's CLAUDE.md declares one.
//
// HOW IT IS WRITTEN
//   Every call on `$` is written out in full inside the hook that makes it:
//   `$` is never handed to a helper. The directory's scanner reads a mod the
//   same way `claude plugin validate` does, and a capability it cannot see at
//   the call site is one it cannot vouch for. The helpers below are pure: they
//   take text or data and give back text or data. No subprocess runs and no
//   network call is made: the main working tree comes from `$.session.repo()`
//   and the branch from reading `.git/HEAD`, both plain `$.fs`/`$.session` calls.
//   What leaves the session is one thing, on one press: the handoff button
//   submits a fixed prompt naming the rate-limit window (see the band below).
//
// BUDGET
//   Every hook has 10 s of its own time per dispatch; `next` and `$` calls do
//   not count. Nothing here sleeps. The objective re-read is bounded by the
//   number of tasks (a handful of small JSON files).
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

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
const MAX_TASKS = 50

// ------------------------------------------------------------ pure helpers

function asNumber(v: unknown, fallback: number): number {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN
  return Number.isFinite(n) ? n : fallback
}

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)

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

// JSON text to an object, or null for anything that is not one.
function parseObject(text: string | null): Record<string, unknown> | null {
  if (text === null) return null
  try {
    const v: unknown = JSON.parse(text)
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null
  } catch {
    return null
  }
}

// Which objective under the state directory is the active one, as hooks/lib/
// objective-common.sh and skills/dev-workflow/_shared/scripts/objective-state.sh
// decide it: SUPERPOWERS_OBJECTIVE_ID wins; else the first `active`; else the
// first not completed/abandoned. `objectives` is id -> parsed objective.json.
function pickObjective(ids: string[], objectives: Map<string, Record<string, unknown> | null>, preferredId: string | undefined): { id: string; obj: Record<string, unknown> } | null {
  const ordered = preferredId && ids.includes(preferredId) ? [preferredId, ...ids.filter(i => i !== preferredId)] : ids
  let fallback: { id: string; obj: Record<string, unknown> } | null = null
  for (const id of ordered) {
    const obj = objectives.get(id) ?? null
    if (!obj) continue
    const status = str(obj.status) ?? ''
    if (id === preferredId || status === 'active') return { id, obj }
    if (!fallback && status !== 'completed' && status !== 'abandoned') fallback = { id, obj }
  }
  return fallback
}

function taskIdsOf(obj: Record<string, unknown>): string[] {
  const tasks = Array.isArray(obj.tasks) ? obj.tasks.filter((t): t is string => typeof t === 'string') : []
  return tasks.slice(0, MAX_TASKS)
}

function taskRow(tid: string, task: Record<string, unknown> | null, handoff: Record<string, unknown> | null): ModsObjectiveTask {
  return {
    id: tid,
    title: str(task?.title) ?? tid,
    status: str(task?.status) ?? 'pending',
    role: str(task?.role),
    branch: str(task?.branch),
    handoff: str(handoff?.status),
  }
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

// The branch a .git/HEAD names, or the short commit when detached.
function branchOf(head: string | null): string {
  if (!head) return ''
  const ref = head.match(/^ref:\s*refs\/heads\/(\S+)/m)?.[1]
  if (ref) return ref
  const sha = head.trim()
  return /^[0-9a-f]{40}$/.test(sha) ? sha.slice(0, 12) : ''
}

// The gitdir a linked worktree's `.git` FILE points at, or null when the text
// is not that (a main checkout has a `.git` directory, which reads as nothing).
function linkedGitDir(dotGit: string | null): string | null {
  const m = dotGit?.match(/^gitdir:\s*(.+)$/m)
  return m?.[1]?.trim() || null
}

const STATUS_COLOR: Record<string, string> = {
  running: 'yellow', completed: 'green', failed: 'red', blocked: 'red', cancelled: 'gray', ready: 'cyan', pending: 'gray',
}

export const register: Register = (on, options) => {
  const warnAt = Math.min(100, Math.max(50, asNumber(options.rate_limit_warn_percent, 85)))
  const semanticSuggest = options.semantic_skill_suggest === true

  // Module variables: reset on a hot reload, which is fine for all of them.
  let root = ''
  let cwd = ''
  let mainRoot = ''
  let objectivesDir = ''
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

    // Where objective state lives. `.dev-files/objectives` is gitignored and exists
    // in the MAIN checkout only, while a worker session runs inside a linked
    // worktree (`.agent-worktrees/<objective>/task-NNN`), so the session's own root
    // is the wrong place to look from there. Resolution order mirrors the shell
    // scripts: OBJECTIVES_ROOT (the override handoff.sh/objective-state.sh honour),
    // else the main working tree ($.session.repo() answers it for a worktree too)
    // plus SUPERPOWERS_OBJECTIVE_STATE_DIRNAME, else the session's root.
    mainRoot = root || cwd
    try {
      const repo = await $.session.repo()
      if (repo?.root) mainRoot = repo.root
    } catch {
      // Not a git checkout: the session's root stands.
    }
    const override = await $.env.get('OBJECTIVES_ROOT')
    const dirname = (await $.env.get('SUPERPOWERS_OBJECTIVE_STATE_DIRNAME')) || '.dev-files/objectives'
    objectivesDir = override ? override.replace(/\/$/, '') : `${mainRoot}/${dirname}`

    // The repo's commit-trailer policy, when it declares one (CLAUDE.md
    // "Commit trailer"). Enforced in attribution.text below; a repo without the
    // line gets no trailer added by this mod.
    trailerPolicy = null
    try {
      const claudeMd = (await $.fs.exists(`${root}/CLAUDE.md`)) ? await $.fs.read(`${root}/CLAUDE.md`) : ''
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

    // Re-read the objective from disk into $.state. The pane, /objective and the
    // compaction snapshot draw from the state, never from disk directly. Runs
    // once now and every 5 s after (a cheap exists() while there is nothing).
    const refresh = async (): Promise<void> => {
      const preferred = await $.env.get('SUPERPOWERS_OBJECTIVE_ID')
      const now = await $.clock.now()
      let found: ModsObjective | null = null
      if (await $.fs.exists(objectivesDir)) {
        const ids = (await $.fs.list(objectivesDir)).filter(d => d.kind === 'dir').map(d => d.name).sort()
        const objectives = new Map<string, Record<string, unknown> | null>()
        for (const id of ids) {
          const path = `${objectivesDir}/${id}/objective.json`
          objectives.set(id, parseObject((await $.fs.exists(path)) ? await $.fs.read(path) : null))
        }
        const pick = pickObjective(ids, objectives, preferred)
        if (pick) {
          const tasks: ModsObjectiveTask[] = []
          for (const tid of taskIdsOf(pick.obj)) {
            const taskPath = `${objectivesDir}/${pick.id}/tasks/${tid}.json`
            const handoffPath = `${objectivesDir}/${pick.id}/handoffs/${tid}.json`
            const task = parseObject((await $.fs.exists(taskPath)) ? await $.fs.read(taskPath) : null)
            const handoff = parseObject((await $.fs.exists(handoffPath)) ? await $.fs.read(handoffPath) : null)
            tasks.push(taskRow(tid, task, handoff))
          }
          found = { id: pick.id, title: str(pick.obj.title) ?? pick.id, status: str(pick.obj.status) ?? 'unknown', tasks, readAt: now }
        }
      }
      await update($, objective, () => found)
    }
    await refresh()
    $.clock.every(5000, () => {
      void refresh()
    })
    return next(e)
  })

  // ------------------------------------------------------- 1. objective pane
  // Answers from $.state, which the 5 s re-read above keeps current.
  on('command.run', { command: 'objective' }, async $ => {
    const o = await read($, objective)
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

  // Counts a worker in flight for the spinner suffix. Nothing is decided here:
  // the spawn always goes through unchanged. `.catch` makes that explicit for
  // `claude plugin validate`'s gating-hooks report (2.1.290): a failed state
  // write here must never hold up a spawn, so the handler just replays `next`.
  on('agent.spawn', async ($, e, next) => {
    await update($, workers, n => (n ?? 0) + 1)
    $.ui.invalidate('ui.render')
    return next(e)
  }).catch(($, e, next) => next(e))

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
            <Text dimColor>{resetsIn(warning.resetsAt, now) ? `resets in ${resetsIn(warning.resetsAt, now)} ·` : ''} hand off before the window closes: type /switch-dev handoff</Text>
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

  // ----------------------------------------- 5. semantic skill suggestion
  // `.catch` makes the engine's own default explicit for the 2.1.290
  // gating-hooks report: a broken suggestion never drops the person's prompt.
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
  }).catch(($, e, next) => next(e))

  // ------------------------------------------ 6. DoD, compaction, trailer
  on('turn.start', ($, e, next) => {
    writesThisTurn = 0
    return next(e)
  })

  // `.catch`: explicit per the 2.1.290 gating-hooks report. A broken counter
  // must never deny a tool call — this hook never denies even on the happy
  // path, so the fallback simply runs the chain beneath unchanged.
  on('tool.call', ($, e, next) => {
    if (!e.agentId && WRITE_TOOLS.has(String(e.tool))) writesThisTurn += 1
    return next(e)
  }).catch(($, e, next) => next(e))

  // The module's one turn.complete hook (the engine refuses a second unmatched
  // registration of an event): a worker's turn frees its spinner slot; a main
  // turn gets a DoD line when it wrote files.
  on('turn.complete', async ($, e, next) => {
    const ran = await next(e)
    if (e.agentId) {
      await update($, workers, n => Math.max(0, (n ?? 0) - 1))
      $.ui.invalidate('ui.render')
      return ran
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
    const lines: string[] = []
    // The branch, from .git/HEAD: a linked worktree's `.git` is a file naming
    // its gitdir, a main checkout's is a directory (reading it throws).
    try {
      const dotGit = `${root || cwd}/.git`
      let gitDir = `${mainRoot || root || cwd}/.git`
      if (await $.fs.exists(dotGit)) {
        try {
          gitDir = linkedGitDir(await $.fs.read(dotGit)) ?? gitDir
        } catch {
          // a directory: the main checkout's own .git
        }
      }
      const headPath = `${gitDir}/HEAD`
      const branch = branchOf((await $.fs.exists(headPath)) ? await $.fs.read(headPath) : null)
      if (branch) lines.push(`branch: ${branch}`)
    } catch {
      // Not a git checkout: the snapshot is just smaller.
    }
    const o = await read($, objective)
    if (o) lines.push(objectiveText(o))
    if (lines.length === 0) return next(e)
    const snapshot = `Working state to preserve verbatim in the summary (tamirs-superpowers):\n${lines.join('\n')}`
    return next({ ...e, instructions: [e.instructions, snapshot].filter(Boolean).join('\n\n') })
  }).catch(($, e, next) => next(e)) // 2.1.290 gating-hooks report: a broken snapshot must never block compaction.

  on('attribution.text', { kind: 'commit' }, async ($, e, next) => {
    const ran = await next(e)
    if (!trailerPolicy || /Co-Authored-By:\s*Claude/i.test(ran.text)) return ran
    return { text: `${ran.text.trimEnd()}\n${trailerPolicy}`.trim() }
  })
}
