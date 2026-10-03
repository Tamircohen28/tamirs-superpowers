// Tests for mod/register.tsx, run by `claude plugin test .` (make test-mods).
//
// The kit loads this plugin from the folder through the engine's own host; the
// hooks `on` registers here sit BENEATH the mod and stand for the engine, so
// every `$` call the mod makes bottoms out in one of them. A test therefore
// stubs exactly the world the feature under test touches and records what the
// mod asked for.
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const PLUGIN = 'tamirs-superpowers'

type Calls = { fetch: { url: string; body: string }[]; prompts: string[]; toasts: string[]; commands: string[]; state: Map<string, unknown>; compactInstructions: string[] }

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
function stubEngine(on: On, disk: Record<string, string>, env: Record<string, string> = {}, sessionRoot = '/repo', repoRoot = '/repo'): Calls {
  const calls: Calls = { fetch: [], prompts: [], toasts: [], commands: [], state: new Map(), compactInstructions: [] }
  mock.store(on)
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
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => {
    calls.commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.toast', ($, e) => {
    calls.toasts.push(e.text)
    return { value: undefined }
  })
  on('prompt.submit', ($, e) => {
    calls.prompts.push(e.text)
    return { text: e.text, context: e.context }
  })
  on('http.fetch', ($, e) => {
    calls.fetch.push({ url: e.url, body: e.init?.body ?? '' })
    return { value: { status: 200, ok: true, headers: {}, text: '{"status":1}' } }
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

test('from a linked worker worktree the objective is read from the main checkout', async ($, on) => {
  // The session sits in .agent-worktrees/obj-1/task-002; .dev-files/objectives exists only
  // under /repo. $.session.repo() answers the main working tree, and that is what is followed.
  const wt = '/repo/.agent-worktrees/obj-1/task-002'
  const calls = stubEngine(on, fakeDisk(), {}, wt, '/repo')
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
  const calls = stubEngine(on, disk, { OBJECTIVES_ROOT: '/elsewhere/objectives/' })
  mock.clock(on)
  await start($)
  const value = calls.state.get('objective') as { id: string } | undefined
  expect(value?.id).toBe('obj-9')
})

test('outside any git checkout the session root is used and nothing fails', async ($, on) => {
  const calls = stubEngine(on, fakeDisk(), {}, '/repo', '')
  mock.clock(on)
  await start($)
  const value = calls.state.get('objective') as { id: string } | undefined
  expect(value?.id).toBe('obj-1')
})

test('the objective pane draws every task on the terminal and the desktop', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: /Ship the thing/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'task-002' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /1\/2 tasks done/ })).toBeDefined()
    await ui.unmount()
  }
})

test('the band stays the engine\'s while every rate-limit window is under the threshold', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 40)
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /engine drew AbovePrompt/ })).toBeDefined()
  expect(await ui.find({ key: 'handoff' })).toBeUndefined()
  await ui.unmount()
})

test('crossing the threshold toasts once, draws the band, and the button submits a handoff prompt', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 91)
  await measure($, 92)
  expect(calls.toasts).toHaveLength(1)
  expect(calls.toasts[0]).toMatch(/5h limit at 91%/)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: PLUGIN, surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /5h limit 92%/ })).toBeDefined()
    await ui.press({ key: 'handoff' })
    await ui.unmount()
  }
  expect(calls.prompts).toHaveLength(2)
  expect(calls.prompts[0]).toMatch(/switch-dev handoff/)
  expect(calls.prompts[0]).toMatch(/92%/)
})

test('Dismiss hides the band until the window climbs further', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 90)
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  await ui.press({ key: 'dismiss' })
  await ui.unmount()
  expect(calls.state.get('limitWarning')).toBeNull()
  await measure($, 90)
  expect(calls.state.get('limitWarning')).toBeNull()
  await measure($, 95)
  expect((calls.state.get('limitWarning') as { percentUsed: number }).percentUsed).toBe(95)
})

test('the usage line draws on the desktop only — the CLI has scripts/statusline.sh', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await measure($, 40)
  const desktop = await $.ui.mount({ plugin: PLUGIN, surface: 'desktop', ...BAND })
  expect(await desktop.find({ type: 'Text', text: /ctx 12% · 5h 40%/ })).toBeDefined()
  expect(await desktop.find({ type: 'Text', text: /\$1\.50/ })).toBeDefined()
  await desktop.unmount()
  const terminal = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })
  expect(await terminal.find({ type: 'Text', text: /ctx 12%/ })).toBeUndefined()
  await terminal.unmount()
})

test('a long main-session turn posts to Pushover with the manifest credentials; a short one does not', { options: { pushover_token: 'tok-123', pushover_user: 'usr-456', pushover_min_turn_seconds: 60 } }, async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await $.turn.complete({ answer: 'Quick.', durationMs: 5000, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(calls.fetch).toHaveLength(0)
  await $.turn.complete({ answer: 'All done, the parser is in.', durationMs: 180000, isAborted: false, turnId: 't2', reason: 'answer' })
  expect(calls.fetch).toHaveLength(1)
  expect(calls.fetch[0]?.url).toBe('https://api.pushover.net/1/messages.json')
  const body = new URLSearchParams(calls.fetch[0]?.body ?? '')
  expect(body.get('token')).toBe('tok-123')
  expect(body.get('user')).toBe('usr-456')
  expect(body.get('title')).toBe('Claude Code — repo')
  expect(body.get('message')).toMatch(/Turn finished \(180s\): All done/)
  expect(body.get('priority')).toBe('0')
})

test('an API-error turn posts at high priority even when short; a subagent turn never posts', { options: { pushover_token: 'tok', pushover_user: 'usr' } }, async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'error' })
  expect(calls.fetch).toHaveLength(1)
  expect(new URLSearchParams(calls.fetch[0]?.body ?? '').get('priority')).toBe('1')
  await $.turn.complete({ answer: 'worker', durationMs: 900000, isAborted: false, turnId: 't2', reason: 'answer', agentId: 'agent-1' })
  expect(calls.fetch).toHaveLength(1)
})

test('without credentials anywhere nothing is sent', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  await $.turn.complete({ answer: 'x', durationMs: 999999, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(calls.fetch).toHaveLength(0)
})

test('a credential in the environment or in ~/.claude/pushover.env is never used: only the manifest options send', async ($, on) => {
  // The directory policy forbids a plugin sending a credential it found on the
  // machine, so neither source may reach Pushover even when both are present.
  const disk = { ...fakeDisk(), '/Users/you/.claude/pushover.env': 'PUSHOVER_TOKEN=file-tok\nPUSHOVER_USER="file-usr"\n' }
  const calls = stubEngine(on, disk, { HOME: '/Users/you', PUSHOVER_TOKEN: 'env-tok', PUSHOVER_USER: 'env-usr', CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN: 'opt-tok', CLAUDE_PLUGIN_OPTION_PUSHOVER_USER: 'opt-usr' })
  mock.clock(on)
  await start($)
  await $.turn.complete({ answer: 'x', durationMs: 999999, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(calls.fetch).toHaveLength(0)
})

test('semantic skill suggestion is off by default and attaches context when on', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const long = 'please open a pull request for this branch and drive it through review and ci until it merges cleanly'
  const off = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(off.context ?? []).toHaveLength(0)
})

test('semantic skill suggestion names the classified skill once, never for slash commands or short prompts', { options: { semantic_skill_suggest: true } }, async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const long = 'please open a pull request for this branch and drive it through review and ci until it merges cleanly'
  const first = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(first.context?.[0]).toMatch(/`pr-dev` covers/)
  const again = await $.prompt.submit({ text: long, wait: false, origin: { kind: 'composer' } })
  expect(again.context ?? []).toHaveLength(0)
  const slash = await $.prompt.submit({ text: '/pr-dev ' + long, wait: false, origin: { kind: 'composer' } })
  expect(slash.context ?? []).toHaveLength(0)
  const short = await $.prompt.submit({ text: 'fix the typo', wait: false, origin: { kind: 'composer' } })
  expect(short.context ?? []).toHaveLength(0)
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

test('the commit trailer the repo\'s CLAUDE.md declares is appended when the attribution text lacks it', async ($, on) => {
  stubEngine(on, fakeDisk())
  mock.clock(on)
  await start($)
  const bare = await $.attribution.text({ kind: 'commit', text: '' })
  expect(bare.text).toBe('Co-Authored-By: Claude <noreply@anthropic.com>')
  const present = await $.attribution.text({ kind: 'commit', text: 'Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>' })
  expect(present.text).toBe('Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>')
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
  const calls = stubEngine(on, disk, {}, wt, '/repo')
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

test('spawning a worker adds it to the spinner until its turn completes', async ($, on) => {
  const calls = stubEngine(on, fakeDisk())
  mock.clock(on)
  on('agent.spawn', () => ({ model: 'sonnet', agentId: 'agent-1' }))
  await start($)
  await $.agent.spawn({ tool_use_id: 'tu1', prompt: 'do it', description: 'worker', subagentType: 'general-purpose', provider: { plugin: 'engine', tier: 'core' }, parentModel: 'sonnet', background: false, fork: false })
  expect(calls.state.get('workers')).toBe(1)
  const spinner = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', component: 'Spinner', props: { word: 'Thinking', message: null, suffix: '', mode: 'thinking' } })
  expect(await spinner.find({ type: 'Text', text: /engine drew Spinner/ })).toBeDefined()
  await spinner.unmount()
  await $.turn.complete({ answer: 'done', durationMs: 10, isAborted: false, turnId: 'w1', reason: 'answer', agentId: 'agent-1' })
  expect(calls.state.get('workers')).toBe(0)
})
