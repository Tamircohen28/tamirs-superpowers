// Tests for plugins/guard/hooks/register.tsx, run by `claude plugin test plugins/guard`.
//
// The kit loads this plugin from the folder through the engine's own host; the
// hooks `on` registers here sit BENEATH the plugin and stand for the engine, so
// every `$` call the plugin makes bottoms out in one of them. A test therefore
// stubs exactly the world the feature under test touches and records what the
// plugin asked for: which tool calls reached the engine, what the dialog was
// asked, and what state the plugin wrote.
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

type Calls = { ran: string[]; asked: string[]; logs: string[]; state: Map<string, unknown> }

type World = {
  /** Paths that exist, each mapped to its text (a directory maps to ''). */
  disk?: Record<string, string>
  env?: Record<string, string>
  /** What $.session.root() answers: the session's own root. */
  sessionRoot?: string
  /** What $.session.repo() answers as the main working tree; '' for no repository. */
  repoRoot?: string
  /** What $.session.surfaces() answers; [] is a `claude -p` run. */
  surfaces?: readonly ('terminal' | 'desktop')[]
  /** The label the person picks in the dialog; 'dismiss' makes the dialog reject. */
  answer?: 'Proceed' | 'Cancel' | 'dismiss'
}

const REPO = '/repo'
const ACTIVE = JSON.stringify({ id: 'obj-1', title: 'Ship it', status: 'active', tasks: ['task-001'] })
const DONE = JSON.stringify({ id: 'obj-0', title: 'Shipped', status: 'completed', tasks: [] })

// A main checkout at /repo with one active objective and one source file.
function repoDisk(objective: string | null = ACTIVE): Record<string, string> {
  const disk: Record<string, string> = {
    '/repo': '',
    '/repo/src': '',
    '/repo/src/a.ts': 'export const a = 1\n',
    '/repo/.dev-files/objectives': '',
    '/repo/.agent-worktrees/obj-1/task-001/src': '',
    '/elsewhere': '',
    '/elsewhere/notes.md': '# notes\n',
  }
  if (objective !== null) {
    disk['/repo/.dev-files/objectives/obj-1'] = ''
    disk['/repo/.dev-files/objectives/obj-1/objective.json'] = objective
  }
  return disk
}

// The engine beneath the plugin: fs over `disk` (realPath is the path itself —
// nothing here is a symlink), a session rooted at sessionRoot in a repository
// whose main working tree is repoRoot, the dialog answered as `answer` says,
// and recorders for what the tests assert on.
function stubEngine(on: On, world: World = {}): Calls {
  const calls: Calls = { ran: [], asked: [], logs: [], state: new Map() }
  const disk = world.disk ?? repoDisk()
  const sessionRoot = world.sessionRoot ?? REPO
  const repoRoot = world.repoRoot ?? REPO
  const surfaces = world.surfaces ?? ['terminal']
  const answer = world.answer ?? 'Proceed'
  mock.store(on)
  mock.env(on, world.env ?? {})
  const norm = (p: string): string => (p.length > 1 ? p.replace(/\/+$/, '') : p)
  const dirs = new Set<string>()
  for (const path of Object.keys(disk)) {
    const parts = path.split('/')
    for (let i = 1; i < parts.length; i += 1) dirs.add(parts.slice(0, i).join('/') || '/')
    if (disk[path] === '') dirs.add(path)
  }
  const exists = (p: string): boolean => p in disk || dirs.has(norm(p))
  on('fs.exists', ($, e) => ({ value: exists(e.path) }))
  on('fs.read', ($, e) => {
    const text = disk[e.path]
    if (text === undefined || dirs.has(e.path)) throw new Error(`ENOENT ${e.path}`)
    return { value: text }
  })
  on('fs.stat', ($, e) => {
    const p = norm(e.path)
    if (!exists(p)) throw new Error(`ENOENT ${p}`)
    const kind = dirs.has(p) ? 'dir' : 'file'
    return { value: { kind, size: 0, mtimeMs: 0, isLink: false, ...(e.resolve ? { realPath: p } : {}) } }
  })
  on('fs.list', ($, e) => {
    const base = norm(e.path ?? '')
    const names = new Map<string, 'file' | 'dir'>()
    for (const p of [...Object.keys(disk), ...dirs]) {
      if (!p.startsWith(`${base}/`)) continue
      const rest = p.slice(base.length + 1)
      const name = rest.split('/')[0]!
      names.set(name, rest.includes('/') || dirs.has(`${base}/${name}`) ? 'dir' : 'file')
    }
    return { value: [...names].map(([name, kind]) => ({ name, kind, size: 0, mtimeMs: 0, isLink: false })) }
  })
  on('state.set', ($, e, next) => {
    calls.state.set(e.key, e.value)
    return next(e)
  })
  on('session.root', () => ({ value: sessionRoot }))
  on('session.cwd', () => ({ value: sessionRoot }))
  on('session.repo', () => ({ value: repoRoot ? { root: repoRoot, remote: null, internal: false, name: null } : null }))
  on('session.surfaces', () => ({ value: surfaces }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('ui.log', ($, e) => {
    calls.logs.push(e.text)
    return { value: undefined }
  })
  // The plugin never runs a process or calls the network; a test that sees one
  // has found a regression.
  on('process.run', () => {
    throw new Error('test engine: the guard must not run a process')
  })
  on('http.fetch', () => {
    throw new Error('test engine: the guard must not call the network')
  })
  on('prompt.submit', () => {
    throw new Error('test engine: the guard must not submit a prompt')
  })
  // The engine's own tool run: $.ui.ask is a tool.call of AskUserQuestion that
  // lands here too, answered as `answer` says; every other call is recorded as
  // having reached the engine and answered with an empty result.
  on('tool.call', ($, e) => {
    if (e.tool === 'AskUserQuestion') {
      const question = e.questions[0]?.question ?? ''
      calls.asked.push(question)
      if (answer === 'dismiss') throw new Error('dismissed')
      return { result: { questions: e.questions, answers: { [question]: answer } } }
    }
    calls.ran.push(e.tool === 'Bash' ? e.command : String(e.tool))
    return { result: {} }
  })
  return calls
}

async function start($: Engine) {
  await $.session.start({ cwd: REPO, surface: 'terminal', isInteractive: true })
}

const bash = ($: Engine, command: string) => $.tool.call({ tool: 'Bash', command })
const write = ($: Engine, file_path: string) => $.tool.call({ tool: 'Write', file_path, content: 'x' })
const edit = ($: Engine, file_path: string) => $.tool.call({ tool: 'Edit', file_path, old_string: 'a', new_string: 'b' })

const isDenied = (r: { deny?: string }): boolean => typeof r.deny === 'string'

// --------------------------------------------------- 1. destructive-command hold

test('a force push is held, and Cancel refuses it with the guard named', async ($, on) => {
  const calls = stubEngine(on, { answer: 'Cancel' })
  mock.clock(on)
  await start($)
  const r = await bash($, 'git push --force origin main')
  expect(calls.asked).toHaveLength(1)
  expect(calls.asked[0]).toMatch(/force push/)
  expect(calls.asked[0]).toContain('git push --force origin main')
  expect(r.deny).toMatch(/^tamirs-superpowers-guard: force push cancelled at the hold/)
  expect(calls.ran).toHaveLength(0)
  expect(calls.state.get('holds')).toBe(1)
  expect(calls.state.get('cancelled')).toBe(1)
})

test('a force push is held, and Proceed runs it', async ($, on) => {
  const calls = stubEngine(on, { answer: 'Proceed' })
  mock.clock(on)
  await start($)
  const r = await bash($, 'git push -f')
  expect(calls.asked).toHaveLength(1)
  expect(isDenied(r)).toBe(false)
  expect(calls.ran).toEqual(['git push -f'])
  expect(calls.state.get('holds')).toBe(1)
  // Nothing was cancelled, so the count was never written.
  expect(calls.state.get('cancelled') ?? 0).toBe(0)
})

test('dismissing the dialog on a surface that drew it refuses the call, never runs it', async ($, on) => {
  const calls = stubEngine(on, { answer: 'dismiss' })
  mock.clock(on)
  await start($)
  const r = await bash($, 'git reset --hard HEAD~3')
  expect(calls.asked).toHaveLength(1)
  expect(r.deny).toMatch(/git reset --hard dismissed at the hold/)
  expect(calls.ran).toHaveLength(0)
})

test('a plain git status never asks', async ($, on) => {
  const calls = stubEngine(on, { answer: 'Cancel' })
  mock.clock(on)
  await start($)
  for (const c of ['git status', 'git push origin main', 'git branch -d merged', 'git clean -n', 'git restore --staged .', 'ls -la', 'rm file.txt', 'rm -r build']) {
    const r = await bash($, c)
    expect(isDenied(r)).toBe(false)
  }
  expect(calls.asked).toHaveLength(0)
  expect(calls.ran).toHaveLength(8)
})

test('rm -rf under a temp directory is let through; rm -rf ./src is held', async ($, on) => {
  const calls = stubEngine(on, { answer: 'Cancel' })
  mock.clock(on)
  await start($)
  for (const c of ['rm -rf /tmp/x', 'rm -rf /private/tmp/build "$TMPDIR/cache"', 'rm -fr "${TMPROOT}/out"', 'rm -rf /var/folders/zz/abc/T/x']) {
    const r = await bash($, c)
    expect(isDenied(r)).toBe(false)
  }
  expect(calls.asked).toHaveLength(0)
  const held = await bash($, 'rm -rf ./src')
  expect(held.deny).toMatch(/rm -rf outside a temp directory/)
  expect(calls.asked).toHaveLength(1)
  const mixed = await bash($, 'rm -rf /tmp/x ./dist')
  expect(mixed.deny).toMatch(/rm -rf outside a temp directory/)
  const sudo = await bash($, 'cd /repo && sudo rm -r -f node_modules')
  expect(sudo.deny).toMatch(/rm -rf outside a temp directory/)
})

test('the rest of the vocabulary is held, each under its own name', async ($, on) => {
  const calls = stubEngine(on, { answer: 'Cancel' })
  mock.clock(on)
  await start($)
  const cases: [string, string][] = [
    ['git push --force-with-lease origin feature', 'force push'],
    ['git -C /repo push origin main --force', 'force push'],
    ['git branch -D feature/x', 'git branch -D'],
    ['git branch --delete --force feature/x', 'git branch -D'],
    ['git worktree remove --force .agent-worktrees/obj-1/task-001', 'git worktree remove --force'],
    ['git worktree remove -f ../wt', 'git worktree remove --force'],
    ['git reset --hard origin/main', 'git reset --hard'],
    ['git clean -fdx', 'git clean -f'],
    ['git clean --force -d', 'git clean -f'],
    ['git checkout -- .', 'git checkout -- .'],
    ['git checkout .', 'git checkout -- .'],
    ['git restore .', 'git restore .'],
    ['git restore --worktree --staged .', 'git restore .'],
    ['npm test; git push --force', 'force push'],
  ]
  for (const [command, rule] of cases) {
    const r = await bash($, command)
    expect(r.deny).toContain(`tamirs-superpowers-guard: ${rule} cancelled at the hold`)
  }
  expect(calls.asked).toHaveLength(cases.length)
  expect(calls.ran).toHaveLength(0)
})

test('with no surface to ask on (claude -p) the hold is let through, not silently denied', async ($, on) => {
  const calls = stubEngine(on, { surfaces: [], answer: 'Cancel' })
  mock.clock(on)
  await start($)
  const r = await bash($, 'git push --force')
  expect(isDenied(r)).toBe(false)
  expect(calls.asked).toHaveLength(0)
  expect(calls.ran).toEqual(['git push --force'])
  expect(calls.logs.some(l => /let through unheld/.test(l))).toBe(true)
  expect((calls.state.get('lastHold') as { answer: string }).answer).toBe('unasked')
})

test('with hold_destructive_commands off everything passes without a dialog', { options: { hold_destructive_commands: false } }, async ($, on) => {
  const calls = stubEngine(on, { answer: 'Cancel' })
  mock.clock(on)
  await start($)
  for (const c of ['git push --force', 'rm -rf ./src', 'git reset --hard']) {
    const r = await bash($, c)
    expect(isDenied(r)).toBe(false)
  }
  expect(calls.asked).toHaveLength(0)
  expect(calls.ran).toHaveLength(3)
})

// --------------------------------------------------- 2. main-checkout write deny

test('a write in the main checkout with an objective active is refused, and the reason names the worktrees', async ($, on) => {
  const calls = stubEngine(on)
  mock.clock(on)
  await start($)
  const r = await write($, '/repo/src/new.ts')
  expect(r.deny).toMatch(/^tamirs-superpowers-guard: Repo edits must happen in an objective worktree, not the main checkout \(\/repo\)/)
  expect(r.deny).toContain("Objective 'obj-1' is active")
  expect(r.deny).toContain('/repo/.agent-worktrees/obj-1/task-NNN (worker)')
  expect(r.deny).toContain('.../integration (integrator)')
  expect(calls.ran).toHaveLength(0)
  expect(calls.state.get('deniedWrites')).toBe(1)
  const e = await edit($, '/repo/src/a.ts')
  expect(isDenied(e)).toBe(true)
  const nb = await $.tool.call({ tool: 'NotebookEdit', notebook_path: '/repo/nb.ipynb', new_source: 'x' })
  expect(isDenied(nb)).toBe(true)
  expect(calls.state.get('deniedWrites')).toBe(3)
})

test('the same write with no objective active passes', async ($, on) => {
  const calls = stubEngine(on, { disk: repoDisk(null) })
  mock.clock(on)
  await start($)
  const r = await write($, '/repo/src/new.ts')
  expect(isDenied(r)).toBe(false)
  expect(calls.ran).toEqual(['Write'])
})

test('a completed objective is not an active one', async ($, on) => {
  const calls = stubEngine(on, { disk: repoDisk(DONE) })
  mock.clock(on)
  await start($)
  const r = await write($, '/repo/src/new.ts')
  expect(isDenied(r)).toBe(false)
  expect(calls.ran).toEqual(['Write'])
})

test('SUPERPOWERS_OBJECTIVE_ID marks an objective active with nothing on disk', async ($, on) => {
  stubEngine(on, { disk: repoDisk(null), env: { SUPERPOWERS_OBJECTIVE_ID: 'obj-env' } })
  mock.clock(on)
  await start($)
  const r = await write($, '/repo/src/new.ts')
  expect(r.deny).toContain("Objective 'obj-env' is active")
})

test('writes outside the repository pass', async ($, on) => {
  const calls = stubEngine(on)
  mock.clock(on)
  await start($)
  expect(isDenied(await write($, '/elsewhere/notes.md'))).toBe(false)
  expect(isDenied(await write($, '/elsewhere/new/deep/file.md'))).toBe(false)
  expect(isDenied(await write($, '/nowhere/at/all.md'))).toBe(false)
  expect(calls.ran).toHaveLength(3)
})

test('writes under .dev-files/ and inside an agent worktree pass even in the main checkout', async ($, on) => {
  const calls = stubEngine(on)
  mock.clock(on)
  await start($)
  expect(isDenied(await write($, '/repo/.dev-files/objectives/obj-1/handoffs/task-001.json'))).toBe(false)
  expect(isDenied(await write($, '/repo/.agent-worktrees/obj-1/task-001/src/b.ts'))).toBe(false)
  expect(isDenied(await write($, '/repo/.claude/worktrees/feature/src/b.ts'))).toBe(false)
  expect(calls.ran).toHaveLength(3)
})

test('from a linked worktree the session root differs from the main working tree, and nothing is refused', async ($, on) => {
  const wt = '/repo/.agent-worktrees/obj-1/task-001'
  const calls = stubEngine(on, { sessionRoot: wt })
  mock.clock(on)
  await $.session.start({ cwd: wt, surface: 'terminal', isInteractive: true })
  expect(isDenied(await write($, `${wt}/src/b.ts`))).toBe(false)
  // Even a write back into the main checkout is the bash hook's to judge, not this mirror's.
  expect(isDenied(await write($, '/repo/src/a.ts'))).toBe(false)
  expect(calls.ran).toHaveLength(2)
})

test('outside any repository nothing is refused', async ($, on) => {
  const calls = stubEngine(on, { repoRoot: '' })
  mock.clock(on)
  await start($)
  expect(isDenied(await write($, '/repo/src/a.ts'))).toBe(false)
  expect(calls.ran).toHaveLength(1)
})

test('with deny_main_checkout_writes off everything passes', { options: { deny_main_checkout_writes: false } }, async ($, on) => {
  const calls = stubEngine(on)
  mock.clock(on)
  await start($)
  expect(isDenied(await write($, '/repo/src/new.ts'))).toBe(false)
  expect(isDenied(await edit($, '/repo/src/a.ts'))).toBe(false)
  expect(calls.ran).toHaveLength(2)
})

// ---------------------------------------------------------------- 3. /guard

test('/guard answers with both options, what each does, and what the guard did this session', async ($, on) => {
  stubEngine(on, { answer: 'Cancel' })
  mock.clock(on)
  await start($)
  await bash($, 'git push --force')
  await write($, '/repo/src/new.ts')
  const { text } = await $.command.run({ command: 'guard', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 100 } })
  expect(text).toMatch(/hold_destructive_commands: on/)
  expect(text).toMatch(/deny_main_checkout_writes: on/)
  expect(text).toMatch(/Proceed\/Cancel dialog/)
  expect(text).toMatch(/1 hold, 1 cancelled; last: force push → cancel \(git push --force\)/)
  expect(text).toMatch(/1 write refused; last: \/repo\/src\/new.ts \(objective obj-1\)/)
  expect(text).toMatch(/claude plugin configure tamirs-superpowers-guard/)
})

test('/guard reports both options off when they are', { options: { hold_destructive_commands: false, deny_main_checkout_writes: false } }, async ($, on) => {
  stubEngine(on)
  mock.clock(on)
  await start($)
  const { text } = await $.command.run({ command: 'guard', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 100 } })
  expect(text).toMatch(/hold_destructive_commands: off/)
  expect(text).toMatch(/deny_main_checkout_writes: off/)
  expect(text).toMatch(/0 holds, 0 cancelled\./)
  expect(text).toMatch(/0 writes refused\./)
})
