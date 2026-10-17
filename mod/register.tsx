// tamirs-superpowers mod — Claude Code >= 2.1.287 function hooks.
//
// WHAT THIS IS, AND WHAT IT IS NOT
//   A mod runs IN-PROCESS on Claude Code, the Claude Desktop Code tab and (since
//   2.1.299) the VS Code extension's chat panel. It can draw (a pane, the band
//   above the prompt, the spinner), react to state the host PUSHES
//   (`session.measure`), answer the model's tool call, and act before a turn
//   dies. The bash hooks in the hook manifest
//   can do none of those things.
//
//   It is ADDITIVE. Every guard, every worktree hook and every reminder in
//   the shell hook scripts stay canonical, because those run on Codex and (via
//   platforms/cursor/hooks.json) Cursor too, and a mod never will. Nothing here
//   denies a tool call, creates a worktree, or replaces a bash hook. Where a
//   feature below overlaps one (rate-limit-handoff.sh, check-done.sh,
//   precompact-snapshot.sh, skill-suggest.sh, notify-pushover.sh), the bash hook
//   is the fallback that still fires when this module cannot load — an org with
//   `allowManagedModsOnly`, `--safe-mode`, a host older than 2.1.287.
//
// WHAT IT DOES
//   1. Objective pane + /objective [id] — the orchestration state orchestrate-dev
//      and worker-dev keep in .dev-files/objectives/<id>/ (objective.json,
//      tasks/*.json, handoffs/*.json) drawn live, one row per task; a task a
//      worker agent is on shows that agent's status. `/objective` answers at once,
//      with no model turn, even mid-turn (`immediate`). Spinner suffix counts
//      workers in flight; a task-notification row is drawn compact. After
//      /clear, /resume or /branch (which reset $.state while `session.start`
//      does not fire) `classic.SessionStart` reloads it.
//   2. Rate-limit band — `session.measure` pushes rate-limit windows after every
//      turn. At `rate_limit_warn_percent` the band above the prompt shows a
//      reminder to type /switch-dev handoff, with a Dismiss button; the mod
//      submits no prompt itself. The first time the band appears for a window
//      the person's own notification channel is rung too ($.ui.notify, 2.1.295).
//      rate-limit-handoff.sh fires AFTER the turn died; this fires BEFORE. The
//      dismissal is kept per window kind in $.store (`rate-limit.dismissed`).
//   3. Usage line on Desktop and VS Code — the figures scripts/statusline.sh
//      draws on the CLI, where those surfaces have no status line to draw into.
//   4. (removed in 4.11.1) A Pushover post on long or failed turns lived here
//      as a network call. The Notification bash hook covers phone alerts, and a
//      mod that both reads the conversation and sends it out is held by the
//      directory for review, so the mod now makes no network call at all.
//   5. Semantic skill suggestion — opt-in (`semantic_skill_suggest`): a small
//      model classifies a long prompt against the bundled skill names and the
//      match is attached as context to the prompt, once per skill across
//      sessions ($.store `skill-suggest.seen`). skill-suggest.sh's keyword
//      matching keeps running regardless.
//   6. Definition-of-done line under an answer that wrote files (turn.complete),
//      a working-state snapshot folded into compaction instructions
//      (session.compact), and the repo's Co-Authored-By trailer policy enforced
//      on the commit attribution text when the repo's CLAUDE.md declares one.
//   7. (withdrawn in 5.0.0) Typeahead rows on `prompt.autocomplete` (2.1.292)
//      and a [ view ] button on `$.ui.view` (2.1.300) shipped briefly. The
//      plugin directory's list of events and calls predates both and blocks a
//      mod that hooks an event it does not know, so both are left out until
//      that list holds them.
//   8. Skill context (skill.prompt, 2.1.299 fields) — when a dev-workflow skill
//      of this plugin expands while an objective is active, the live objective
//      id, title, worktree and open-task count are appended to its text.
//   9. objective_status tool — registered at session.start (`isDeferred: false`,
//      so its schema is in the prompt's tool list from turn one) and answered
//      by a tool.call hook from the same files: the model reads orchestration
//      state without a shell.
//
// HOW IT IS WRITTEN
//   Every call on `$` is written out in full inside the hook that makes it:
//   `$` is never handed to a helper. The directory's scanner reads a mod the
//   same way `claude plugin validate` does, and a capability it cannot see at
//   the call site is one it cannot vouch for. The helpers in objective.ts,
//   usage.ts, skills.ts and compat.ts are pure: they take text or data and
//   give back text or data, and none of them receives `$`. No subprocess runs
//   and no network call is made: the main working tree comes from
//   `$.session.repo()` and the branch from reading `.git/HEAD`, both plain
//   `$.fs`/`$.session` calls. Nothing leaves the session: the mod submits no
//   prompt (the band tells the person what to type) and makes no network call.
//   Newer drawing props are used only behind a version gate (compat.ts) against
//   `$.session.version()`, the 2.1.287 tree being the fallback: a tree with a
//   prop the host does not read is not drawn at all.
//
// BUDGET
//   Every hook has 10 s of its own time per dispatch; `next` and `$` calls do
//   not count. Nothing here sleeps. The objective re-read is bounded by the
//   number of tasks (a handful of small JSON files).
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { hasNotify, strongText } from './compat'
import {
  STATUS_COLOR,
  agentsByTask,
  asNumber,
  branchOf,
  linkedGitDir,
  objectiveOf,
  objectiveSummaryJson,
  objectiveText,
  parseObject,
  pickObjective,
  skillContext,
  str,
  taskIdsOf,
  taskRow,
} from './objective'
import type { AgentRow } from './objective'
import { SKILL_LABELS, isDevWorkflowSkill, seenLabels, wordCount } from './skills'
import {
  STATUS_MAX,
  clip,
  crossingKey,
  dismissedMap,
  limitAlert,
  limitHeadline,
  limitInstruction,
  usageLine,
  worstWindow,
} from './usage'
import type { ModsLimitWarning, ModsObjective, ModsObjectiveTask, ModsUsage } from './types'

const PLUGIN = 'tamirs-superpowers'
const PANE = 'objective'
const STATUS_TOOL = 'objective_status'
const STATUS_TOOL_FULL = 'mcp__tamirs-superpowers__objective_status'

// $.store keys: values that outlive the session. Re-read before every write.
const STORE_DISMISSED = 'rate-limit.dismissed'
const STORE_SEEN = 'skill-suggest.seen'

// $.state references: literal plugin/key pairs, declared in types/index.d.ts.
const objective = atom({ plugin: 'tamirs-superpowers', key: 'objective' } as const, null)
const usage = atom({ plugin: 'tamirs-superpowers', key: 'usage' } as const, null)
const limitWarning = atom({ plugin: 'tamirs-superpowers', key: 'limitWarning' } as const, null)
const dismissed = atom({ plugin: 'tamirs-superpowers', key: 'dismissed' } as const, {})
const workers = atom({ plugin: 'tamirs-superpowers', key: 'workers' } as const, 0)

const WRITE_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])

export const register: Register = (on, options) => {
  const warnAt = Math.min(100, Math.max(50, asNumber(options.rate_limit_warn_percent, 85)))
  const semanticSuggest = options.semantic_skill_suggest === true

  // Module variables: reset on a hot reload, which is fine for all of them.
  // `session.start` sets the first group; the closures it builds keep its `$`.
  let root = ''
  let cwd = ''
  let mainRoot = ''
  let objectivesDir = ''
  let hostVersion = ''
  let trailerPolicy: string | null = null
  let writesThisTurn = 0
  let lastToastedKey = ''
  let notifiedKind = ''
  let suggested = new Set<string>()
  // The objective loader session.start builds over its own `$` (its `$.fs`
  // calls spelled out there), reused by the 5 s timer, the SessionStart
  // reload, `/objective <id>` and the objective_status tool.
  let loadObjective: ((preferredId?: string) => Promise<ModsObjective | null>) | null = null
  let refreshObjective: (() => Promise<void>) | null = null

  // ---------------------------------------------------------------- startup
  on('session.start', async ($, e, next) => {
    cwd = e.cwd
    try {
      root = await $.session.root()
    } catch {
      root = e.cwd
    }
    try {
      hostVersion = (await $.session.version()).version
    } catch {
      hostVersion = ''
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

    // What outlives the session: the skills already suggested and the band
    // dismissals, both from $.store into their session caches.
    try {
      suggested = new Set(seenLabels(await $.store.get(STORE_SEEN)))
      const held = dismissedMap(await $.store.get(STORE_DISMISSED))
      await update($, dismissed, () => held)
    } catch {
      // A store the host cannot read starts the session empty: nothing is lost
      // but a repeated suggestion.
    }

    await $.command.register({
      name: 'objective',
      description: 'Show the active orchestration objective and its tasks (tamirs-superpowers)',
      argumentHint: '[objective-id]',
      immediate: true,
    })
    // Listed in the prompt's tool list from turn one (`isDeferred: false`), not
    // behind ToolSearch: the model should reach for it before a shell command.
    // A host that refuses the registration loses the tool, never the rest of
    // this hook (the objective loader below is what the pane and /objective need).
    try {
      await $.tool.register({
        name: STATUS_TOOL,
        description: 'The active tamirs-superpowers orchestration objective and its tasks (status, role, branch, handoff) as JSON, read from .dev-files/objectives/. Pass `objective` to read a specific objective id instead of the active one.',
        inputSchema: {
          type: 'object',
          properties: { objective: { type: 'string', description: 'An objective id under .dev-files/objectives/ (optional; the active one when left out).' } },
        },
        isDeferred: false,
      })
    } catch {
      // objective-state.sh show and /objective still answer.
    }

    // Read an objective from disk: the active one, or `preferredId`. The pane,
    // /objective, the skill context, the tool and the compaction snapshot draw
    // from $.state, which the 5 s re-read keeps current (a cheap exists() while
    // there is nothing).
    loadObjective = async (preferredId?: string): Promise<ModsObjective | null> => {
      const preferred = preferredId || (await $.env.get('SUPERPOWERS_OBJECTIVE_ID')) || undefined
      const now = await $.clock.now()
      if (!(await $.fs.exists(objectivesDir))) return null
      const ids = (await $.fs.list(objectivesDir)).filter(d => d.kind === 'dir').map(d => d.name).sort()
      const objectives = new Map<string, Record<string, unknown> | null>()
      for (const id of ids) {
        const path = `${objectivesDir}/${id}/objective.json`
        objectives.set(id, parseObject((await $.fs.exists(path)) ? await $.fs.read(path) : null))
      }
      const pick = pickObjective(ids, objectives, preferred)
      if (!pick) return null
      if (preferredId && pick.id !== preferredId) return null
      const tasks: ModsObjectiveTask[] = []
      for (const tid of taskIdsOf(pick.obj)) {
        const taskPath = `${objectivesDir}/${pick.id}/tasks/${tid}.json`
        const handoffPath = `${objectivesDir}/${pick.id}/handoffs/${tid}.json`
        const task = parseObject((await $.fs.exists(taskPath)) ? await $.fs.read(taskPath) : null)
        const handoff = parseObject((await $.fs.exists(handoffPath)) ? await $.fs.read(handoffPath) : null)
        tasks.push(taskRow(tid, task, handoff))
      }
      return objectiveOf(pick.id, pick.obj, tasks, now)
    }
    const load = loadObjective
    refreshObjective = async (): Promise<void> => {
      const found = await load()
      await update($, objective, () => found)
    }
    await refreshObjective()
    $.clock.every(5000, () => {
      void refreshObjective?.()
    })
    return next(e)
  })

  // /clear, /resume and /branch reset $.state while `session.start` does not
  // fire again: the classic SessionStart hook event does, with the source. The
  // objective is re-read and the dismissals come back from the store; the
  // usage figures return with the next `session.measure`, which re-derives the
  // band from them. Informational only: the event goes on as it came.
  on('classic.SessionStart', { source: ['clear', 'resume', 'fork'] }, async ($, e, next) => {
    if (refreshObjective) await refreshObjective()
    try {
      const held = dismissedMap(await $.store.get(STORE_DISMISSED))
      await update($, dismissed, () => held)
    } catch {
      // Unreadable store: the band starts over, as a fresh session would.
    }
    await update($, limitWarning, () => null)
    notifiedKind = ''
    lastToastedKey = ''
    $.ui.invalidate('ui.render')
    return next(e)
  }).catch(($, e, next) => next(e)) // a classic hook may `block`; a failed reload must never block a session start.

  // ------------------------------------------------------- 1. objective pane
  // Answers from $.state, which the 5 s re-read above keeps current; with an
  // id, that objective is read from disk instead.
  on('command.run', { command: 'objective' }, async ($, e) => {
    const asked = e.args.trim().split(/\s+/)[0] ?? ''
    const o = asked && loadObjective ? await loadObjective(asked) : await read($, objective)
    if (asked && !o) return { text: `No objective ${asked} under ${objectivesDir || '.dev-files/objectives'}.` }
    if (o && !asked) void $.ui.open({ id: PANE, title: `Objective ${o.id}` })
    return { text: objectiveText(o) }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const o = await read($, objective)
    const n = await read($, workers)
    const width = Math.max(20, e.props.bodyColumns)
    const strong = strongText(hostVersion)
    if (!o) {
      return (
        <Box flexDirection="column">
          <Text dimColor>No objective is active.</Text>
          <Text dimColor>/plan-dev writes one under .dev-files/objectives/.</Text>
        </Box>
      )
    }
    // Which worker is on which task, from the session's own agent list.
    let agents: AgentRow[] = []
    try {
      agents = (await $.agent.list()).map(a => ({ id: a.id, description: a.description, status: a.status }))
    } catch {
      agents = []
    }
    const byTask = agentsByTask(o.tasks, agents)
    const done = o.tasks.filter(t => t.status === 'completed').length
    return (
      <Box flexDirection="column">
        <Text {...strong} wrap="truncate-end">{o.id} · {o.title}</Text>
        <Text dimColor>
          {o.status} · {done}/{o.tasks.length} tasks done{n > 0 ? ` · ${n} worker${n === 1 ? '' : 's'} running` : ''}
        </Text>
        {o.tasks.map(t => {
          const agent = byTask.get(t.id)
          return (
            <Box key={t.id} flexDirection="row" gap={1}>
              <Text dimColor>{t.id}</Text>
              <Text color={STATUS_COLOR[t.status] ?? 'white'}>{t.status.padEnd(9)}</Text>
              <Text wrap="truncate-end">{t.title.slice(0, Math.max(8, width - 40))}</Text>
              {t.handoff ? <Text dimColor>handoff:{t.handoff}</Text> : null}
              {agent ? <Text color={agent.status === 'failed' || agent.status === 'killed' ? 'red' : 'cyan'}>agent {agent.status}</Text> : null}
            </Box>
          )
        })}
        {o.tasks.length === 0 ? <Text dimColor>(no tasks yet)</Text> : null}
      </Box>
    )
  })

  // Counts a worker in flight for the spinner suffix. Nothing is decided here:
  // the spawn always goes through unchanged. `.catch` makes that explicit for
  // `claude plugin validate`'s gating-hooks report (2.1.290): a failed state
  // write here must never hold up a spawn. As of 2.1.299 the engine's own
  // default on a gating hook's failure flipped from letting the action through
  // to refusing it, so this `.catch` is no longer a no-op replay of that
  // default — it is the thing that deliberately keeps a broken state write
  // from blocking a spawn that was never meant to be deniable.
  on('agent.spawn', async ($, e, next) => {
    await update($, workers, n => (n ?? 0) + 1)
    $.ui.invalidate('ui.render')
    return next(e)
  }).catch(($, e, next) => next(e))

  // The spinner rewrite is a prop, not a tree: the same suffix on the terminal,
  // the desktop and VS Code, so there is no surface branch to take here.
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

    const worst = worstWindow(u)
    const dismissedAt = worst ? ((await read($, dismissed))[worst.kind] ?? 0) : 0
    if (worst && worst.percentUsed >= warnAt && worst.percentUsed > dismissedAt) {
      const w: ModsLimitWarning = { kind: worst.kind, percentUsed: worst.percentUsed, resetsAt: worst.resetsAt }
      await update($, limitWarning, () => w)
      const key = crossingKey(w)
      if (key !== lastToastedKey) {
        lastToastedKey = key
        $.ui.toast(limitAlert(w, now), { timeoutMs: 8000 })
      }
      // The band's first appearance for a window also rings the person's own
      // notification channel (their preferredNotifChannel; 2.1.295), once per
      // crossing: it reaches a Desktop with no terminal bell. Host-local, no
      // network; a host before 2.1.295 has no such method and is left alone.
      if (notifiedKind !== w.kind && hasNotify(hostVersion)) {
        notifiedKind = w.kind
        try {
          await $.ui.notify(limitAlert(w, now), { title: 'Rate limit — hand off' })
        } catch {
          // A hook above refused it, or the write failed: the band still shows.
        }
      }
    } else if (!worst || worst.percentUsed < warnAt - 10) {
      await update($, limitWarning, () => null)
      await update($, dismissed, () => ({}))
      try {
        await $.store.delete(STORE_DISMISSED)
      } catch {
        // The stale dismissal stays in the store until the next write.
      }
      lastToastedKey = ''
      notifiedKind = ''
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const warning = await read($, limitWarning)
    const u = await read($, usage)
    // The terminal has scripts/statusline.sh; the desktop and VS Code have no
    // status line, so the figures draw here on those two.
    const isRemote = e.surface === 'desktop' || e.surface === 'vscode'
    const showUsage = isRemote && u !== null && (u.rateLimits.length > 0 || u.contextPercent !== undefined)
    if (!warning && !showUsage) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const now = await $.clock.now()
    const strong = strongText(hostVersion)
    // One tree for all three surfaces: no hotkey/plain/autoFocus/action on the
    // Button, no size/mono/tabular on a Text, no position/hover on a Box, so
    // the VS Code surface draws it as the others do.
    return (
      <Box flexDirection="column">
        {warning ? (
          <Box flexDirection="row" gap={1}>
            <Text color="red" {...strong}>{limitHeadline(warning)}</Text>
            <Text dimColor>{limitInstruction(warning, now)}</Text>
            <Button
              key="dismiss"
              label="Dismiss"
              role="dismiss"
              onPress={async () => {
                await update($, dismissed, map => ({ ...(map ?? {}), [warning.kind]: warning.percentUsed }))
                await update($, limitWarning, () => null)
                // Write-through to the store, re-read first: another session
                // may have dismissed a different window meanwhile.
                try {
                  const held = dismissedMap(await $.store.get(STORE_DISMISSED))
                  await $.store.set(STORE_DISMISSED, { ...held, [warning.kind]: warning.percentUsed })
                } catch {
                  // The session cache still holds the dismissal.
                }
              }}
            />
          </Box>
        ) : null}
        {showUsage && u ? <Text dimColor>{clip(usageLine(u, now), STATUS_MAX)}</Text> : null}
      </Box>
    )
  })

  // ---------------------------------------- 8. skill context on expansion
  // A dev-workflow skill of this plugin, expanding while an objective is
  // active, gets the live objective appended to its text (2.1.299 fields:
  // pluginName names the plugin). `.catch`: a failed read never swallows the
  // skill's own text.
  on('skill.prompt', { pluginName: PLUGIN }, async ($, e, next) => {
    const ran = await next(e)
    if (!isDevWorkflowSkill(e.skill)) return ran
    const o = await read($, objective)
    if (!o) return ran
    let worktree = root
    try {
      worktree = await $.session.root()
    } catch {
      worktree = root
    }
    return { text: `${ran.text.trimEnd()}\n\n${skillContext(o, worktree)}` }
  }).catch(($, e, next) => next(e))

  // ---------------------------------------- 9. objective_status tool
  // The model's Bash-free read of orchestration state: the same files, as JSON.
  // Answered here, never passed down (a call no hook answers fails); the
  // `.catch` answers the model with the failure rather than leaving the call
  // unanswered.
  on('tool.call', { tool: STATUS_TOOL_FULL }, async ($, e) => {
    const asked = str(e.objective)?.trim() || undefined
    const o = asked ? (loadObjective ? await loadObjective(asked) : null) : await read($, objective)
    return { result: objectiveSummaryJson(o, asked) }
  }).catch(() => ({ result: JSON.stringify({ objective: null, error: 'objective_status could not read .dev-files/objectives; run objective-state.sh show from a shell.' }) }))

  // ----------------------------------------- 5. semantic skill suggestion
  // `.catch` makes the engine's own default explicit for the 2.1.290
  // gating-hooks report: a broken suggestion never drops the person's prompt.
  // Since 2.1.299 that default is to refuse on a gating hook's failure, not
  // let it through, so this `.catch` now actively overrides the default
  // rather than restating it — deliberately, since a broken classifier call
  // is never a reason to swallow what the person typed.
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
    // Once per skill across sessions: write-through to the store, re-read first.
    try {
      const seen = new Set(seenLabels(await $.store.get(STORE_SEEN)))
      seen.add(label)
      await $.store.set(STORE_SEEN, [...seen])
    } catch {
      // The session set still holds it: at worst the same skill is named again next session.
    }
    const note = `[tamirs-superpowers] The bundled skill \`${label}\` covers what this prompt asks for. Invoke it with the Skill tool (or /${label}) before doing the work by hand.`
    return next({ ...e, context: [...(e.context ?? []), note] })
  }).catch(($, e, next) => next(e))

  // ------------------------------------------ 6. DoD, compaction, trailer
  // `turn.start` also fires for a subagent's or teammate's turn, not only the
  // main loop's, as of 2.1.299 (tell them apart by `e.agentId`, absent on the
  // main loop). A worker's turn can start while the main turn is still running
  // (feature 1's spinner counts exactly this), so an unguarded reset here would
  // zero the main turn's write count out from under it. Only a main-loop start
  // resets the counter; a worker's own writes were never counted into it
  // anyway (`tool.call` below filters the same way).
  on('turn.start', ($, e, next) => {
    if (!e.agentId) writesThisTurn = 0
    return next(e)
  })

  // `.catch`: explicit per the 2.1.290 gating-hooks report. A broken counter
  // must never deny a tool call — this hook never denies even on the happy
  // path. Since 2.1.299 a gating hook that cannot run is refused by default,
  // not let through, so the fallback below is what keeps a broken counter
  // from denying a tool call it was never meant to gate.
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
  }).catch(($, e, next) => next(e)) // 2.1.290 gating-hooks report: a broken snapshot must never block compaction — and since 2.1.299 the engine's own default would otherwise refuse, not let it through.

  on('attribution.text', { kind: 'commit' }, async ($, e, next) => {
    const ran = await next(e)
    if (!trailerPolicy || /Co-Authored-By:\s*Claude/i.test(ran.text)) return ran
    return { text: `${ran.text.trimEnd()}\n${trailerPolicy}`.trim() }
  })
}
