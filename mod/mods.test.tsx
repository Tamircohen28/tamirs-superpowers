// Tests for mod/register.tsx, run by `claude plugin test .` (make test-mods).
//
// The kit loads this plugin from the folder through the engine's own host; the
// hooks `on` registers here sit BENEATH the mod and stand for the engine, so
// every `$` call the mod makes bottoms out in one of them. A test therefore
// stubs exactly the world the feature under test touches and records what the
// mod asked for. Every drawing test mounts on the three surfaces the mod draws
// on (`terminal`, `desktop`, `vscode`): one tree serves all three.
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { atLeast, hasTypography, strongText } from './compat'
import { agentsByTask, objectiveSummaryJson, openTaskCount } from './objective'
import { PUBLIC_SKILLS, SKILL_DESCRIPTIONS } from './skills'

const PLUGIN = 'tamirs-superpowers'
const SURFACES = ['terminal', 'desktop', 'vscode'] as const
const STATUS_TOOL = 'mcp__tamirs-superpowers__objective_status'

type Agent = { id: string; description: string; type: string; status: 'pending' | 'running' | 'waiting' | 'idle' | 'completed' | 'failed' | 'killed' }

type Calls = {
  fetch: { url: string; body: string }[]
  prompts: string[]
  toasts: string[]
  notifies: { text: string; title?: string }[]
  views: (string | undefined)[]
  commands: string[]
  tools: { name: string; isDeferred?: boolean }[]
  state: Map<string, unknown>
  store: Map<string, unknown>
  compactInstructions: string[]
}

type World = {
  env?: Record<string, string>
  sessionRoot?: string
  repoRoot?: string
  /** What $.session.version() answers; the current build when left out. */
  version?: string
  /** What $.agent.list() answers. */
  agents?: Agent[]
  /** What $.store holds at the start. */
  store?: Record<string, unknown>
}

// A fake repo under /repo: a CLAUDE.md with the trailer policy, and one active
// objective with two tasks, one of them handed off. Every fs call the mod makes
// is answered from here; nothing touches the real disk.
function fakeDisk(): Record<string, string> {
  const obj = { id: 'obj-1', title: 'Ship the thing', status: 'active', tasks: ['task-001', 'task-002'] }
  return {
    '/repo/CLAUDE.md': '# CLAUDE.md\n\n## Commit trailer\n\n```text\nCo-Authored-By: Claude <noreply@anthropic.com>\n```\n',
    '/repo/.git/HEAD': 'ref: refs/heads/feature/parser\n',
    '/repo/.dev-files/objectives/obj-1/objective.json': JSON.stringify(obj),
    '/repo/.dev-files/objectives/obj-1/tasks/task-001.json': JSON.stringify({ id: 'task-001', title: 'Add the parser', status: 'completed', role: 'implementer', branch: 'worker/obj-1/001' }),
    '/repo/.dev-files/objectives/obj-1/tasks/task-002.json': JSON.stringify({ id: 'task-002', title: 'Write the tests', status: 'running', role: 'test-engineer' }),
    '/repo/.dev-files/objectives/obj-1/handoffs/task-001.json': JSON.stringify({ task_id: 'task-001', status: 'completed' }),
  }
}

// The engine beneath the mod: fs over `disk`, a session rooted at /repo, and
// recorders for the side effects the tests assert on.
// `sessionRoot` is what $.session.root()/cwd() answer; `repoRoot` what
// $.session.repo() answers as the repository's root — /repo for the main checkout
// AND for every linked worktree of it, which is how the mod finds the shared
// objective state. An empty `repoRoot` means no repository (repo() answers null).
function stubEngine(on: On, disk: Record<string, string>, world: World = {}): Calls {
  const { env = {}, sessionRoot = '/repo', repoRoot = '/repo', version = '2.1.302', agents = [], store = {} } = world
  const calls: Calls = { fetch: [], prompts: [], toasts: [], notifies: [], views: [], commands: [], tools: [], state: new Map(), store: new Map(), compactInstructions: [] }
  // The store recorder sits above the kit's in-memory store (registered first),
  // keyed on the mod's two keys, so a write-through shows up here.
  for (const key of ['rate-limit.dismissed', 'skill-suggest.seen']) {
    on('store.set', { key }, ($, e, next) => {
      calls.store.set(e.key, e.value)
      return next(e)
    })
    on('store.delete', { key }, ($, e, next) => {
      calls.store.delete(e.key)
      return next(e)
    })
  }
  mock.store(on, store)
  mock.env(on, env)
  const dirs = new Set<string>()
  for (const path of Object.keys(disk)) {
    const parts = path.split('/')
    for (let i = 1; i < parts.length; i += 1) dirs.add(parts.slice(0, i).join('/') || '/')
  }
  on('fs.exists', ($, e) => ({ value: e.path in disk || dirs.has(e.path.replace(/\/$/, '')) }))
  on('fs.read', ($, e) => {
    const text = disk[e.path]
    if (text === undefined) throw new Error(`ENOENT ${e.path}`)
    return { value: text }
  })
  on('fs.list', ($, e) => {
    const base = (e.path ?? '').replace(/\/$/, '')
    const names = new Map<string, 'file' | 'dir'>()
    for (const p of Object.keys(disk)) {
      if (!p.startsWith(`${base}/`)) continue
      const rest = p.slice(base.length + 1)
      const name = rest.split('/')[0]!
      names.set(name, rest.includes('/') ? 'dir' : 'file')
    }
    return { value: [...names].map(([name, kind]) => ({ name, kind, size: 0, mtimeMs: 0, isLink: false })) }
  })
  on('state.set', ($, e, next) => {
    calls.state.set(e.key, e.value)
    return next(e)
  })
  on('session.root', () => ({ value: sessionRoot }))
  on('session.cwd', () => ({ value: sessionRoot }))
  on('session.version', () => ({ value: { version, base: version } }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => {
    calls.commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('tool.register', ($, e) => {
    calls.tools.push({ name: e.name, isDeferred: e.isDeferred })
    return { value: { tool: `mcp__${PLUGIN}__${e.name}` } }
  })
  on('agent.list', () => ({ value: agents.map(a => ({ ...a })) }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.toast', ($, e) => {
    calls.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.notify', ($, e) => {
    calls.notifies.push({ text: e.text, title: e.title })
    return { value: { isSent: true, channel: 'kitty' } }
  })
  on('ui.view', ($, e) => {
    calls.views.push(e.agentId)
    return { value: {} }
  })
  on('prompt.submit', ($, e) => {
    calls.prompts.push(e.text)
    return { text: e.text, context: e.context }
  })
  // The mod makes no network call; a test that sees one has found a regression.
  on('http.fetch', ($, e) => {
    calls.fetch.push({ url: e.url, body: e.init?.body ?? '' })
    throw new Error('test engine: the mod must not call the network')
  })
  on('session.repo', () => ({ value: repoRoot ? { root: repoRoot, remote: null, internal: false, name: null } : null }))
  // The mod never runs a process; a test that sees one has found a regression.
  on('process.run', () => {
    throw new Error('test engine: the mod must not run a process')
  })
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', ($, e) => ({ text: e.answer }))
  on('tool.call', () => ({ deny: 'test engine: no tool runs' }))
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('attribution.text', ($, e) => ({ text: e.text }))
  on('session.compact', ($, e) => {
    if (e.instructions !== undefined) calls.compactInstructions.push(e.instructions)
    return { messages: e.messages }
  })
  on('model.classify', () => ({ value: 'pr-dev' }))
  on('skill.prompt', ($, e) => ({ text: e.text }))
  on('classic.SessionStart', () => ({}))
  // The engine's own drawing where the mod passes a site through.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine drew {e.component}</Text>
  })
  return calls
}

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const oneMessage = () => [{ role: 'user' as const, text: 'hello', toolUses: [] }]

const PANE = {
  component: 'Pane',
  requestId: 'objective',
  props: { title: 'Objective', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

const SPINNER = { component: 'Spinner', props: { word: 'Thinking', message: null, suffix: '', mode: 'thinking' } } as const

const WORKER: Agent = { id: 'agent-1', description: 'worker-dev task-002 of obj-1', type: 'general-purpose', status: 'running' }

async function start($: Engine, cwd = '/repo') {
  await $.session.start({ cwd, surface: 'terminal', isInteractive: true })
}

function measure($: Engine, percentUsed: number, kind = 'five_hour') {
  return $.session.measure({
    context: { window: 200000, percent: 12 },
    rateLimits: [{ kind, percentUsed, resetsAt: '2030-01-01T00:00:00Z' }],
    cost: { usd: 1.5 },
    changed: ['rateLimits'],
  })
}

function skillPrompt($: Engine, skill: string, text = `# ${skill}\n\nDo the thing.`) {
  return $.skill.prompt({ skill, text, pluginName: PLUGIN, path: `/plugins/${PLUGIN}/skills/x/${skill}/SKILL.md`, source: 'plugin', frontmatter: { name: skill } })
}

test('session.start registers /objective and reads the active objective into state', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  expect(calls.commands).toContain('objective')
  const value = calls.state.get('objective') as { id: string; tasks: { status: string; handoff?: string }[] } | undefined
  expect(value?.id).toBe('obj-1')
  expect(value?.tasks).toHaveLength(2)
  expect(value?.tasks[0]?.handoff).toBe('completed')
  expect(value?.tasks[1]?.status).toBe('running')
})

test('/objective answers at once with the task table and opens the pane', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const { text } = await $.command.run({ command: 'objective', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } })
  expect(text).toContain('obj-1')
  expect(text).toContain('task-002')
  expect(text).toMatch(/running/)
})

test('/objective with no objective on disk says so instead of failing', async ($, on) => {
  stubEngine(on, { '/repo/README.md': 'x' })
  mock.clock(on)
  await start($)
  const { text } = await $.command.run({ command: 'objective', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } })
  expect(text).toMatch(/No objective is active/)
})

test('/objective <id> reads that objective from disk, active or not, and names an unknown id', async ($, on) => {
  const disk = {
    ...fakeDisk(),
    '/repo/.dev-files/objectives/obj-0/objective.json': JSON.stringify({ id: 'obj-0', title: 'Shipped already', status: 'completed', tasks: [] }),
  }
  stubEngine(on, disk)
  mock.clock(on)
  await start($)
  const old = await $.command.run({ command: 'objective', args: 'obj-0', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } })
  expect(old.text).toMatch(/Objective obj-0 — Shipped already \[completed\]/)
  const missing = await $.command.run({ command: 'objective', args: 'obj-9', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } })
  expect(missing.text).toMatch(/No objective obj-9/)
})

test('from a linked worker worktree the objective is read from the main checkout', async ($, on) => {
  // The session sits in .agent-worktrees/obj-1/task-002; .dev-files/objectives exists only
  // under /repo. $.session.repo() answers the main working tree, and that is what is followed.
  const wt = '/repo/.agent-worktrees/obj-1/task-002'
  const calls = stubEngine(on, fakeDisk(), { sessionRoot: wt, repoRoot: '/repo' })
  mock.clock(on)
  await start($, wt)
  const value = calls.state.get('objective') as { id: string } | undefined
  expect(value?.id).toBe('obj-1')
  const { text } = await $.command.run({ command: 'objective', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } })
  expect(text).toContain('task-002')
})

test('OBJECTIVES_ROOT overrides where objective state is read from, as handoff.sh honours it', async ($, on) => {
  const disk = {
    '/elsewhere/objectives/obj-9/objective.json': JSON.stringify({ id: 'obj-9', title: 'Relocated', status: 'active', tasks: [] }),
  }
  const calls = stubEngine(on, disk, { env: { OBJECTIVES_ROOT: '/elsewhere/objectives/' } })
  mock.clock(on)
  await start($)
  const value = calls.state.get('objective') as { id: string } | undefined
  expect(value?.id).toBe('obj-9')
})

test('outside any git checkout the session root is used and nothing fails', async ($, on) => {
  const calls = stubEngine(on, fakeDisk(), { repoRoot: '' })
  mock.clock(on)
  await start($)
  const value = calls.state.get('objective') as { id: string } | undefined
  expect(value?.id).toBe('obj-1')
})

// On `part: { plugin }` (2.1.299): the engine stamps each hook's returned root with
// it. The kit's `find`/`findAll` descriptions carry an element's own props only
// (`{ flexDirection: 'column' }` for the pane's root Box); the stamp is on the
// tree `drawn()` hands back, beside `type`, `props` and `children`.
const stamped = (tree: unknown) => (tree as { part?: { plugin: string } }).part

test('the objective pane draws every task on the terminal, the desktop and VS Code, its root stamped with the plugin', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...PANE })
    expect(stamped(await ui.drawn())).toEqual({ plugin: PLUGIN })
    expect(await ui.find({ type: 'Text', text: /Ship the thing/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'task-002' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /1\/2 tasks done/ })).toBeDefined()
    // The pane offers no button on any row.
    expect(await ui.find({ type: 'Button' })).toBeUndefined()
    await ui.unmount()
  }
})

// The directory's list of calls predates `$.ui.view` (2.1.300), so the pane shows a
// worker's status and opens nothing: no view button, no `$.ui.view` call.
test('a task its worker agent is on shows the agent status and offers no view button', async ($, on) => {
  const calls = stubEngine(on, fakeDisk(), { agents: [WORKER] })
  mock.clock(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: /agent running/ })).toBeDefined()
    expect(await ui.find({ key: 'view:task-002' })).toBeUndefined()
    expect(await ui.find({ type: 'Button' })).toBeUndefined()
    await ui.unmount()
  }
  expect(calls.views).toHaveLength(0)
})

test('workers map to tasks by the task id in their description, else by order of running agents', () => {
  const tasks = [
    { id: 'task-001', title: 'a', status: 'running' },
    { id: 'task-002', title: 'b', status: 'running' },
    { id: 'task-003', title: 'c', status: 'completed' },
  ]
  const named = agentsByTask(tasks, [
    { id: 'x', description: 'worker-dev task-002', status: 'running' },
    { id: 'y', description: 'worker', status: 'running' },
    { id: 'z', description: 'done worker', status: 'completed' },
  ])
  expect(named.get('task-002')?.id).toBe('x')
  expect(named.get('task-001')?.id).toBe('y')
  expect(named.get('task-003')).toBeUndefined()
})

test('the heading uses Text weight on a host that reads it and bold on an older one', async ($, on) => {
  stubEngine(on, fakeDisk(), { version: '2.1.302' })
  mock.clock(on)
  await start($)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...PANE })
    const heading = await ui.find({ type: 'Text', text: /Ship the thing/ })
    expect(heading?.props.weight).toBe('semibold')
    await ui.unmount()
  }
})

test('on a host before 2.1.299 the heading falls back to the 2.1.287 tree (bold, no weight)', async ($, on) => {
  stubEngine(on, fakeDisk(), { version: '2.1.292' })
  mock.clock(on)
  await start($)
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...PANE })
  const heading = await ui.find({ type: 'Text', text: /Ship the thing/ })
  expect(heading?.props.bold).toBe(true)
  expect(heading?.props.weight).toBeUndefined()
  await ui.unmount()
})

test('version gates read a release version and treat an unknown one as older', () => {
  expect(atLeast('2.1.302', '2.1.299')).toBe(true)
  expect(atLeast('2.1.299', '2.1.299')).toBe(true)
  expect(atLeast('2.1.292', '2.1.299')).toBe(false)
  expect(atLeast('2.2.0-dev.20261001', '2.1.299')).toBe(true)
  expect(atLeast('', '2.1.299')).toBe(false)
  expect(atLeast(undefined, '2.1.299')).toBe(false)
  expect(hasTypography('2.1.299')).toBe(true)
  expect(strongText('nonsense')).toEqual({ bold: true })
})

test('the band stays the engine\'s while every rate-limit window is under the threshold', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 40)
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /engine drew AbovePrompt/ })).toBeDefined()
  expect(await ui.find({ key: 'dismiss' })).toBeUndefined()
  await ui.unmount()
})

test('crossing the threshold toasts once, draws a band that names /switch-dev handoff on every surface, and submits no prompt', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 91)
  await measure($, 92)
  expect(calls.toasts).toHaveLength(1)
  expect(calls.toasts[0]).toMatch(/5h limit at 91%/)
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...BAND })
    expect(stamped(await ui.drawn())).toEqual({ plugin: PLUGIN })
    expect(await ui.find({ type: 'Text', text: /5h limit 92%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /type \/switch-dev handoff/ })).toBeDefined()
    const dismiss = await ui.find({ key: 'dismiss' })
    expect(dismiss?.type).toBe('Button')
    // The VS Code surface ignores these; the tree never sets them on any surface.
    expect(dismiss?.props.hotkey).toBeUndefined()
    expect(dismiss?.props.plain).toBeUndefined()
    expect(dismiss?.props.autoFocus).toBeUndefined()
    expect(dismiss?.props.action).toBeUndefined()
    await ui.unmount()
  }
  // The mod makes no prompt.submit call: the band only tells the user the command.
  expect(calls.prompts).toHaveLength(0)
})

// The plugin directory does not know `$.ui.notify` (2.1.295), and an unknown call in a
// mod that also reads files and the conversation is held as a way out: the band and
// its one toast per crossing carry the warning, and no native notification is rung.
test('a rate-limit crossing shows the band and one toast, and rings no native notification', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 91)
  await measure($, 93)
  expect(calls.toasts).toHaveLength(1)
  await measure($, 90, 'seven_day')
  await measure($, 30)
  await measure($, 95)
  expect(calls.notifies).toHaveLength(0)
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /5h limit 95%/ })).toBeDefined()
  await ui.unmount()
})

test('Dismiss hides the band until the window climbs further, and writes the dismissal through to the store per window', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 90)
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  await ui.press({ key: 'dismiss' })
  await ui.unmount()
  expect(calls.state.get('limitWarning')).toBeNull()
  expect(calls.state.get('dismissed')).toEqual({ five_hour: 90 })
  expect(calls.store.get('rate-limit.dismissed')).toEqual({ five_hour: 90 })
  await measure($, 90)
  expect(calls.state.get('limitWarning')).toBeNull()
  await measure($, 95)
  expect((calls.state.get('limitWarning') as { percentUsed: number }).percentUsed).toBe(95)
  // The window resets: the dismissal is cleared from the session and the store.
  await measure($, 20)
  expect(calls.state.get('dismissed')).toEqual({})
  expect(calls.store.has('rate-limit.dismissed')).toBe(false)
})

test('a dismissal another session stored keeps the band quiet at that percentage', async ($, on) => {
  const calls = stubEngine(on, fakeDisk(), { store: { 'rate-limit.dismissed': { five_hour: 90 } } })
  mock.clock(on)
  await start($)
  expect(calls.state.get('dismissed')).toEqual({ five_hour: 90 })
  await measure($, 90)
  expect(calls.state.get('limitWarning') ?? null).toBeNull()
  expect(calls.toasts).toHaveLength(0)
  // Another window is not covered by that dismissal.
  await measure($, 90, 'seven_day')
  expect((calls.state.get('limitWarning') as { kind: string }).kind).toBe('seven_day')
})

test('the usage line draws on the desktop and VS Code only — the CLI has scripts/statusline.sh', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 40)
  for (const surface of ['desktop', 'vscode'] as const) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...BAND })
    const line = await ui.find({ type: 'Text', text: /ctx 12% · 5h 40%/ })
    expect(line).toBeDefined()
    expect(line?.text.length).toBeLessThanOrEqual(200)
    expect(await ui.find({ type: 'Text', text: /\$1\.50/ })).toBeDefined()
    await ui.unmount()
  }
  const terminal = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  expect(await terminal.find({ type: 'Text', text: /ctx 12%/ })).toBeUndefined()
  await terminal.unmount()
})

test('a long or failed main-session turn sends nothing anywhere: phone alerts are the Notification hook\'s job', { options: { pushover_token: 'tok', pushover_user: 'usr' } }, async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  const session = mock.session(on)
  mock.clock(on)
  await start($)
  await $.turn.complete({ answer: 'All done.', durationMs: 900000, isAborted: false, turnId: 't1', reason: 'answer' })
  await $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId: 't2', reason: 'error' })
  expect(calls.fetch).toHaveLength(0)
  expect(calls.notifies).toHaveLength(0)
  expect(calls.prompts).toHaveLength(0)
  // Nor does it append a row to the conversation.
  expect(session.appended()).toHaveLength(0)
})

test('semantic skill suggestion is off by default and attaches context when on', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const long = 'please open a pull request for this branch and drive it through review and ci until it merges cleanly'
  const off = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(off.context ?? []).toHaveLength(0)
})

test('semantic skill suggestion names the classified skill once, never for slash commands or short prompts, and records it in the store', { options: { semantic_skill_suggest: true } }, async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const long = 'please open a pull request for this branch and drive it through review and ci until it merges cleanly'
  const first = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(first.context?.[0]).toMatch(/`pr-dev` covers/)
  expect(calls.store.get('skill-suggest.seen')).toEqual(['pr-dev'])
  const again = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(again.context ?? []).toHaveLength(0)
  const slash = await $.prompt.submit({ text: '/pr-dev ' + long, wait: false, origin: { kind: 'composer' } })
  expect(slash.context ?? []).toHaveLength(0)
  const short = await $.prompt.submit({ text: 'fix the typo', wait: false, origin: { kind: 'composer' } })
  expect(short.context ?? []).toHaveLength(0)
})

test('a skill suggested in an earlier session (store) is not suggested again', { options: { semantic_skill_suggest: true } }, async ($, on) => {
  const calls = stubEngine(on, fakeDisk(), { store: { 'skill-suggest.seen': ['pr-dev'] } })
  mock.clock(on)
  await start($)
  const long = 'please open a pull request for this branch and drive it through review and ci until it merges cleanly'
  const first = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(first.context ?? []).toHaveLength(0)
  expect(calls.store.has('skill-suggest.seen')).toBe(false)
})

test('a turn that wrote files gets a DoD line beneath its answer; a read-only turn does not', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await $.turn.start({ text: 'edit it', turnId: 't1' })
  await $.tool.call({ tool: 'Edit', file_path: '/repo/a.ts', old_string: 'a', new_string: 'b' })
  await $.tool.call({ tool: 'Read', file_path: '/repo/a.ts' })
  const wrote = await $.turn.complete({ answer: 'Edited.', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(wrote.text).toMatch(/^DoD: 1 file write this turn/)
  await $.turn.start({ text: 'look', turnId: 't2' })
  await $.tool.call({ tool: 'Read', file_path: '/repo/a.ts' })
  const read = await $.turn.complete({ answer: 'Looked.', durationMs: 1000, isAborted: false, turnId: 't2', reason: 'answer' })
  expect(read.text).toBe('Looked.')
})

test('a worker turn starting mid-main-turn (2.1.299: turn.start also fires for subagents) does not zero the main turn\'s write count', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  on('agent.spawn', () => ({ model: 'sonnet', agentId: 'agent-1' }))
  await start($)
  await $.turn.start({ text: 'edit it, then delegate', turnId: 't1' })
  await $.tool.call({ tool: 'Edit', file_path: '/repo/a.ts', old_string: 'a', new_string: 'b' })
  await $.agent.spawn({ tool_use_id: 'tu1', prompt: 'do it', description: 'worker', subagentType: 'general-purpose', provider: { plugin: 'engine', tier: 'core' }, parentModel: 'sonnet', background: false, fork: false })
  // The worker's own turn starts while the main turn is still open — this must not
  // reset the main turn's counter just because it shares the same hook.
  await $.turn.start({ text: 'worker task', turnId: 'w1', agentId: 'agent-1' })
  await $.turn.complete({ answer: 'done', durationMs: 10, isAborted: false, turnId: 'w1', reason: 'answer', agentId: 'agent-1' })
  const wrote = await $.turn.complete({ answer: 'Edited and delegated.', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(wrote.text).toMatch(/^DoD: 1 file write this turn/)
})

test('the commit trailer the repo\'s CLAUDE.md declares is appended when the attribution text lacks it', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const bare = await $.attribution.text({ kind: 'commit', text: '' })
  expect(bare.text).toBe('Co-Authored-By: Claude <noreply@anthropic.com>')
  const present = await $.attribution.text({ kind: 'commit', text: 'Co-Authored-By: Claude Code <noreply@anthropic.com>' })
  expect(present.text).toBe('Co-Authored-By: Claude Code <noreply@anthropic.com>')
  const pr = await $.attribution.text({ kind: 'pr', text: '' })
  expect(pr.text).toBe('')
})

test('a repo whose CLAUDE.md declares no trailer gets none added', async ($, on) => {
  stubEngine(on, { '/repo/CLAUDE.md': '# nothing about trailers\n' })
  mock.clock(on)
  await start($)
  const bare = await $.attribution.text({ kind: 'commit', text: '' })
  expect(bare.text).toBe('')
})

test('compaction instructions carry the objective when one is active', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await $.session.compact({ trigger: 'manual', messages: oneMessage() })
  const seen = calls.compactInstructions[0]
  expect(seen).toMatch(/Working state to preserve/)
  expect(seen).toMatch(/branch: feature\/parser/)
  expect(seen).toMatch(/obj-1/)
  expect(seen).toMatch(/task-002/)
})

test('compaction from a linked worktree reads the branch from the gitdir its .git file names', async ($, on) => {
  const wt = '/repo/.agent-worktrees/obj-1/task-002'
  const disk = {
    ...fakeDisk(),
    [`${wt}/.git`]: 'gitdir: /repo/.git/worktrees/task-002\n',
    '/repo/.git/worktrees/task-002/HEAD': 'ref: refs/heads/worker/obj-1/002\n',
  }
  const calls = stubEngine(on, disk, { sessionRoot: wt, repoRoot: '/repo' })
  mock.clock(on)
  await start($, wt)
  await $.session.compact({ trigger: 'manual', messages: oneMessage() })
  expect(calls.compactInstructions[0]).toMatch(/branch: worker\/obj-1\/002/)
})

test('compaction with nothing in flight leaves the instructions alone', async ($, on) => {
  const calls = stubEngine(on, { '/repo/README.md': 'x' })
  mock.clock(on)
  await start($)
  await $.session.compact({ trigger: 'auto', messages: oneMessage(), instructions: 'keep it short' })
  expect(calls.compactInstructions).toEqual(['keep it short'])
})

test('spawning a worker adds it to the spinner on every surface until its turn completes', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  on('agent.spawn', () => ({ model: 'sonnet', agentId: 'agent-1' }))
  await start($)
  await $.agent.spawn({ tool_use_id: 'tu1', prompt: 'do it', description: 'worker', subagentType: 'general-purpose', provider: { plugin: 'engine', tier: 'core' }, parentModel: 'sonnet', background: false, fork: false })
  expect(calls.state.get('workers')).toBe(1)
  for (const surface of SURFACES) {
    const spinner = await $.ui.mount({ plugin: PLUGIN, surface, ...SPINNER })
    expect(await spinner.find({ type: 'Text', text: /engine drew Spinner/ })).toBeDefined()
    await spinner.unmount()
  }
  await $.turn.complete({ answer: 'done', durationMs: 10, isAborted: false, turnId: 'w1', reason: 'answer', agentId: 'agent-1' })
  expect(calls.state.get('workers')).toBe(0)
})

// ------------------------------------------------------------ 2.1.292+ API

test('the skill table covers the 27 public skills, each with a short description', () => {
  expect(PUBLIC_SKILLS).toHaveLength(27)
  for (const internal of ['changelog-review', 'docs-review', 'mcp-pagination']) expect(PUBLIC_SKILLS).not.toContain(internal)
  for (const name of PUBLIC_SKILLS) {
    const description = SKILL_DESCRIPTIONS[name] ?? ''
    expect(description.length).toBeGreaterThan(0)
    expect(description.length).toBeLessThan(80)
  }
  expect(Object.keys(SKILL_DESCRIPTIONS)).toContain('switch-dev')
})

test('a dev-workflow skill of this plugin expanding while an objective is active gets the live objective appended', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const worker = await skillPrompt($, 'worker-dev')
  expect(worker.text).toMatch(/^# worker-dev\n\nDo the thing\.\n\n\[tamirs-superpowers\] Active objective obj-1 — Ship the thing \[active\] · worktree \/repo · 1 open task of 2\./)
  // Not a dev-workflow skill: untouched.
  const creator = await skillPrompt($, 'skill-creator')
  expect(creator.text).toBe('# skill-creator\n\nDo the thing.')
  // Another plugin's skill of the same name: untouched (the matcher keys on pluginName).
  const foreign = await $.skill.prompt({ skill: 'worker-dev', text: 'theirs', pluginName: 'someone-else', source: 'plugin', frontmatter: {} })
  expect(foreign.text).toBe('theirs')
})

test('a dev-workflow skill expanding with no objective active is left exactly as computed', async ($, on) => {
  stubEngine(on, { '/repo/README.md': 'x' })
  mock.clock(on)
  await start($)
  const worker = await skillPrompt($, 'orchestrate-dev')
  expect(worker.text).toBe('# orchestrate-dev\n\nDo the thing.')
})

test('objective_status is registered in the prompt\'s tool list at session.start and answers the objective as JSON', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  expect(calls.tools).toEqual([{ name: 'objective_status', isDeferred: false }])
  const active = await $.tool.call({ tool: STATUS_TOOL })
  expect(active.deny).toBeUndefined()
  const summary = JSON.parse(String(active.result)) as { objective: { id: string; status: string; open_tasks: number; tasks: { id: string; status: string; role: string | null; branch: string | null; handoff: string | null }[] } }
  expect(summary.objective.id).toBe('obj-1')
  expect(summary.objective.status).toBe('active')
  expect(summary.objective.open_tasks).toBe(1)
  expect(summary.objective.tasks).toEqual([
    { id: 'task-001', title: 'Add the parser', status: 'completed', role: 'implementer', branch: 'worker/obj-1/001', handoff: 'completed' },
    { id: 'task-002', title: 'Write the tests', status: 'running', role: 'test-engineer', branch: null, handoff: null },
  ])
  // An unknown id answers a null objective, never an error the model cannot read.
  const missing = await $.tool.call({ tool: STATUS_TOOL, objective: 'obj-9' })
  expect(JSON.parse(String(missing.result))).toEqual({ objective: null, message: 'No objective obj-9 under .dev-files/objectives.' })
})

test('objective_status with no objective on disk answers a null objective', async ($, on) => {
  stubEngine(on, { '/repo/README.md': 'x' })
  mock.clock(on)
  await start($)
  const none = await $.tool.call({ tool: STATUS_TOOL })
  const summary = JSON.parse(String(none.result)) as { objective: null; message: string }
  expect(summary.objective).toBeNull()
  expect(summary.message).toMatch(/No objective is active/)
  expect(objectiveSummaryJson(null, undefined)).toMatch(/plan-dev/)
})

test('classic SessionStart after /clear, /resume or /branch reloads the objective and the stored dismissals', async ($, on) => {
  const disk = fakeDisk()
  const calls = stubEngine(on, disk, { store: { 'rate-limit.dismissed': { five_hour: 90 } } })
  mock.clock(on)
  await start($)
  expect((calls.state.get('objective') as { tasks: unknown[] }).tasks).toHaveLength(2)
  // A third task lands on disk, and the session is cleared: the state the host
  // reset comes back from disk and the store on the classic event.
  disk['/repo/.dev-files/objectives/obj-1/objective.json'] = JSON.stringify({ id: 'obj-1', title: 'Ship the thing', status: 'active', tasks: ['task-001', 'task-002', 'task-003'] })
  disk['/repo/.dev-files/objectives/obj-1/tasks/task-003.json'] = JSON.stringify({ id: 'task-003', title: 'Document it', status: 'pending' })
  calls.state.clear()
  for (const source of ['clear', 'resume', 'fork'] as const) {
    await $.classic.SessionStart({ source })
    expect((calls.state.get('objective') as { tasks: { id: string }[] }).tasks.map(t => t.id)).toEqual(['task-001', 'task-002', 'task-003'])
    expect(calls.state.get('dismissed')).toEqual({ five_hour: 90 })
    expect(calls.state.get('limitWarning')).toBeNull()
    calls.state.clear()
  }
  // A startup or compact SessionStart is not the mod's to act on.
  await $.classic.SessionStart({ source: 'startup' })
  await $.classic.SessionStart({ source: 'compact' })
  expect(calls.state.size).toBe(0)
  expect(openTaskCount({ id: 'x', title: 'x', status: 'active', readAt: 0, tasks: [{ id: 'a', title: 'a', status: 'pending' }, { id: 'b', title: 'b', status: 'cancelled' }] })).toBe(1)
})
