// tamirs-superpowers-guard — Claude Code >= 2.1.287 function hooks.
//
// WHAT THIS IS, AND WHY IT IS A PLUGIN OF ITS OWN
//   The core plugin's mod (mod/register.tsx) keeps a footprint Anthropic's plugin
//   directory lists without review: it holds no tool call and denies nothing. A
//   hook that can refuse a tool call reads to the directory as
//   MOD_HOOKS_POLICY_EVENT, and one that answers for the person as
//   MOD_ANSWERS_PERMISSION — both are holds on the listing. The guard below does
//   exactly those two things, so it ships as a SEPARATE plugin from the in-repo
//   marketplace, where the directory's holds do not apply, and the core plugin's
//   `calls:` line stays clean. Install it only if you want the in-process holds.
//
// WHAT IT DOES
//   1. Destructive-command hold (`hold_destructive_commands`, on by default) —
//      a Bash call whose command matches a conservative vocabulary (a force
//      push, `git branch -D`, `git worktree remove --force`, `git reset --hard`,
//      `git clean -f`, `rm -rf` outside a temp directory, `git checkout -- .`,
//      `git restore .`) pauses in the engine's own question dialog, showing the
//      command with Proceed and Cancel. Proceed runs it; Cancel refuses it with
//      this guard's reason. A bash PreToolUse hook can deny, but it cannot hold:
//      the pause is what only an in-process hook can do.
//   2. Main-checkout write deny (`deny_main_checkout_writes`, on by default) —
//      while an orchestration objective is active and the session sits in the
//      MAIN checkout (not a worktree), an Edit/Write/MultiEdit/NotebookEdit of a
//      file inside the repository is refused, naming the objective's worktrees.
//      The same rule as hooks/enforce-worktree-edits.sh, which stays canonical
//      (it runs on Codex and Cursor too); this is the in-process mirror.
//   3. `/guard` — answers with both options' current values, what each does and
//      what the guard has held or refused this session.
//
// WHAT IT NEVER DOES
//   A hold nobody can answer must not become a silent deny. Where nothing draws
//   the dialog (`claude -p`, the SDK, a session with no surface) the destructive
//   command goes through unheld, and the debug log says so. Every gating hook
//   carries `.catch(($, e, next) => next(e))`: a hook that throws or outruns its
//   budget lets the call through rather than refusing it, because the bash
//   guards are the binding layer and this one is the convenience on top.
//
// HOW IT IS WRITTEN
//   Every call on `$` is written out in full inside the hook that makes it; `$`
//   is handed to no helper. The helpers below are pure: a command in, a rule
//   name out; a path in, a path out. No process runs, no network call is made,
//   no prompt is submitted. The main working tree comes from `$.session.repo()`,
//   the objective from reading `.dev-files/objectives/*/objective.json` with
//   `$.fs`, and where a path lands from `$.fs.stat(path, { resolve: true })`.
//
// BUDGET
//   Every hook has 10 s of its own time per dispatch; `next` and `$` calls do
//   not count, so a person may take as long as they like over the dialog.
//   Nothing here sleeps. The objective scan reads a handful of small JSON files.
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { GuardDeniedWrite, GuardHold } from '../types'

const PLUGIN = 'tamirs-superpowers-guard'
const COMMAND_PREVIEW = 160
const MAX_CLIMB = 64

// $.state references: literal plugin/key pairs, declared in types/index.d.ts.
const holds = atom({ plugin: 'tamirs-superpowers-guard', key: 'holds' } as const, 0)
const cancelled = atom({ plugin: 'tamirs-superpowers-guard', key: 'cancelled' } as const, 0)
const lastHold = atom({ plugin: 'tamirs-superpowers-guard', key: 'lastHold' } as const, null)
const deniedWrites = atom({ plugin: 'tamirs-superpowers-guard', key: 'deniedWrites' } as const, 0)
const lastDeniedWrite = atom({ plugin: 'tamirs-superpowers-guard', key: 'lastDeniedWrite' } as const, null)

// ------------------------------------------------------------ pure helpers

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)

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

// One line of the command for a dialog or a reason, cut to COMMAND_PREVIEW.
function preview(command: string): string {
  const one = command.replace(/\s+/g, ' ').trim()
  return one.length > COMMAND_PREVIEW ? `${one.slice(0, COMMAND_PREVIEW - 1)}…` : one
}

// A shell command split at its list and pipe operators: each piece is judged on
// its own, so `cd x && git push --force` is held for the push. Quoting is not
// modelled: a command text inside quotes (`bash -c '...'`, a `trap` string) is
// read as one word and is not held — the same gap guard-sensitive-files.sh
// records for interpreters, stated rather than papered over.
function segments(command: string): string[] {
  return command
    .split(/\s*(?:&&|\|\||;|\||\n)\s*/)
    .map(s => s.trim())
    .filter(Boolean)
}

// The words of one segment: whitespace-split, surrounding quotes stripped, with
// redirections, `&`, grouping braces and leading `sudo`/`command`/`exec`/`env`/
// `nohup`/`time` and VAR=value assignments dropped, so `sudo rm -rf x` reads as
// `rm -rf x`.
function words(segment: string): string[] {
  const out: string[] = []
  for (const raw of segment.split(/\s+/)) {
    let w = raw
    if (w === '' || w === '&' || w === '(' || w === ')' || w === '{' || w === '}') continue
    if (/^\d*[<>]/.test(w)) continue
    w = w.replace(/^\(+/, '')
    if ((w.startsWith('"') && w.endsWith('"') && w.length > 1) || (w.startsWith("'") && w.endsWith("'") && w.length > 1)) w = w.slice(1, -1)
    out.push(w)
  }
  const WRAPPERS = new Set(['sudo', 'command', 'exec', 'env', 'nohup', 'time', 'builtin'])
  while (out.length > 0 && (WRAPPERS.has(out[0]!) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(out[0]!))) out.shift()
  return out
}

// `git [global options] <subcommand> <rest...>` → the subcommand and its words,
// or null for anything that is not a git command.
function gitCommand(w: string[]): { sub: string; rest: string[] } | null {
  if (w[0] !== 'git') return null
  let i = 1
  while (i < w.length && w[i]!.startsWith('-')) {
    const opt = w[i]!
    i += 1
    // Options that take their value as the next word.
    if (opt === '-C' || opt === '-c' || opt === '--git-dir' || opt === '--work-tree' || opt === '--namespace') i += 1
  }
  const sub = w[i]
  return sub ? { sub, rest: w.slice(i + 1) } : null
}

// A short-flag cluster (`-rf`, `-xdf`) carrying `letter`, or the long form.
function hasFlag(rest: string[], letter: string, long: string | null): boolean {
  return rest.some(t => (long !== null && (t === long || t.startsWith(`${long}=`))) || (/^-[A-Za-z]+$/.test(t) && t.includes(letter)))
}

// `rm -rf` is let through only where every operand is clearly a temp path: under
// a system temp root (the same list hooks/enforce-worktree-edits.sh calls a
// throwaway root), or a variable whose name says temp (`$TMPDIR`, `"$tmp"`,
// `${TMPROOT}`). Anything else — a bare name, a repo path, `$HOME`, a glob —
// is not clearly temp and the command is held.
function isClearlyTemp(operand: string): boolean {
  if (/^(\/private)?\/tmp\/.+/.test(operand)) return true
  if (/^(\/private)?\/var\/folders\/.+/.test(operand)) return true
  if (/^\$\{?[A-Za-z_]*(TMP|TEMP|tmp|temp)[A-Za-z0-9_]*\}?(\/.*)?$/.test(operand)) return true
  return false
}

// The vocabulary. Each entry names the fact it read; the names are what the
// dialog, the deny reason and `/guard` show. Conservative on purpose: a command
// not listed here is never held, and a listed one is held only in the spelling
// that destroys (`git clean -n` is a dry run, `git restore --staged .` only
// unstages, `rm -rf /tmp/x` is a temp directory).
function destructiveRule(command: string): string | null {
  for (const segment of segments(command)) {
    const w = words(segment)
    if (w.length === 0) continue
    if (w[0] === 'rm') {
      const rest = w.slice(1)
      const recursive = hasFlag(rest, 'r', '--recursive') || hasFlag(rest, 'R', null)
      const force = hasFlag(rest, 'f', '--force')
      const operands = rest.filter(t => !t.startsWith('-') || t === '-')
      if (recursive && force && operands.length > 0 && !operands.every(isClearlyTemp)) return 'rm -rf outside a temp directory'
      continue
    }
    const git = gitCommand(w)
    if (!git) continue
    const { sub, rest } = git
    if (sub === 'push' && (hasFlag(rest, 'f', '--force') || rest.some(t => t.startsWith('--force-with-lease') || t === '--force-if-includes'))) return 'force push'
    if (sub === 'branch') {
      const hardDelete = hasFlag(rest, 'D', null)
      const softDelete = hasFlag(rest, 'd', '--delete')
      if (hardDelete || (softDelete && hasFlag(rest, 'f', '--force'))) return 'git branch -D'
    }
    if (sub === 'worktree' && rest[0] === 'remove' && hasFlag(rest.slice(1), 'f', '--force')) return 'git worktree remove --force'
    if (sub === 'reset' && rest.includes('--hard')) return 'git reset --hard'
    if (sub === 'clean' && hasFlag(rest, 'f', '--force') && !hasFlag(rest, 'n', '--dry-run')) return 'git clean -f'
    if (sub === 'checkout') {
      const operands = rest.filter(t => !t.startsWith('-'))
      if (operands.includes('.')) return 'git checkout -- .'
    }
    if (sub === 'restore') {
      const operands = rest.filter(t => !t.startsWith('-'))
      const stagedOnly = (hasFlag(rest, 'S', '--staged')) && !(hasFlag(rest, 'W', '--worktree'))
      if (operands.includes('.') && !stagedOnly) return 'git restore .'
    }
  }
  return null
}

// Path helpers: separator '/', which is what $.session.root() and $.fs.stat's
// realPath answer on the surfaces this plugin runs on.
const trimSlash = (p: string): string => (p.length > 1 ? p.replace(/\/+$/, '') : p)
const parentOf = (p: string): string => {
  const cut = p.lastIndexOf('/')
  if (cut < 0) return ''
  return cut === 0 ? '/' : p.slice(0, cut)
}
const baseOf = (p: string): string => p.slice(p.lastIndexOf('/') + 1)
const joinPath = (dir: string, name: string): string => (dir === '/' ? `/${name}` : `${trimSlash(dir)}/${name}`)
const isUnder = (path: string, root: string): boolean => path === root || path.startsWith(`${trimSlash(root)}/`)

// An agent worktree inside the repository is a legitimate place to write even
// though its path sits under the repo root: the objective shapes
// (`.agent-worktrees/<objective>/...`) and every legacy shape
// hooks/lib/objective-common.sh recognises.
function isAgentWorkspacePath(path: string, repoRoot: string, agentDirname: string, agentRoot: string | undefined): boolean {
  if (isUnder(path, joinPath(repoRoot, agentDirname))) return true
  if (agentRoot && isUnder(path, trimSlash(agentRoot))) return true
  return /(^|\/)\.(claude|cursor|codex)\/\.?worktrees\//.test(path)
}

function reasonFor(repoRoot: string, objectiveId: string, agentDirname: string, agentRoot: string | undefined): string {
  const base = agentRoot ? trimSlash(agentRoot) : joinPath(repoRoot, agentDirname)
  return `${PLUGIN}: Repo edits must happen in an objective worktree, not the main checkout (${repoRoot}). Objective '${objectiveId}' is active: work in ${base}/${objectiveId}/task-NNN (worker) or .../integration (integrator). Ask the orchestrator which one is yours — do not create a new worktree.`
}

const onOff = (v: boolean): string => (v ? 'on' : 'off')

function guardText(holdOn: boolean, denyOn: boolean, h: number, c: number, last: GuardHold | null, d: number, lastWrite: GuardDeniedWrite | null): string {
  const lines = [
    `${PLUGIN} — in-process holds on top of the bash guards (which stay canonical).`,
    '',
    `hold_destructive_commands: ${onOff(holdOn)}`,
    '  A Bash call that force-pushes, deletes a branch with -D, removes a worktree with --force, resets --hard, cleans with -f, runs rm -rf outside a temp directory, or discards the working tree (git checkout -- . / git restore .) pauses in a Proceed/Cancel dialog. Cancel refuses it. Where nothing can draw the dialog (claude -p, the SDK) the call goes through unheld.',
    `  This session: ${h} hold${h === 1 ? '' : 's'}, ${c} cancelled${last ? `; last: ${last.rule} → ${last.answer} (${last.command})` : ''}.`,
    '',
    `deny_main_checkout_writes: ${onOff(denyOn)}`,
    '  While an objective is active (SUPERPOWERS_OBJECTIVE_ID, or an objective.json with status active under .dev-files/objectives/) and this session sits in the main checkout rather than a worktree, an Edit/Write/MultiEdit/NotebookEdit inside the repository is refused with the objective\'s worktrees named. Writes under .dev-files/ and inside any agent worktree pass.',
    `  This session: ${d} write${d === 1 ? '' : 's'} refused${lastWrite ? `; last: ${lastWrite.path} (objective ${lastWrite.objectiveId})` : ''}.`,
    '',
    `Change either in /config (${PLUGIN}) or with \`claude plugin configure ${PLUGIN}\`.`,
  ]
  return lines.join('\n')
}

export const register: Register = (on, options) => {
  const holdOn = options.hold_destructive_commands !== false
  const denyOn = options.deny_main_checkout_writes !== false

  // ---------------------------------------------------------------- startup
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'guard',
      description: `Show what ${PLUGIN} holds and refuses, and both options' current values`,
      immediate: true,
    })
    return next(e)
  })

  // ------------------------------------------- 1. destructive-command hold
  // Judged before `next`: a hold is a pause in front of the call, never an
  // undo after it. The `.catch` lets the call through when this hook fails —
  // the bash guards are the binding layer; this is the convenience on top.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    if (!holdOn) return next(e)
    const rule = destructiveRule(e.command)
    if (rule === null) return next(e)
    const shown = preview(e.command)

    // Nothing to draw the dialog on: a hold the person cannot answer must not
    // become a silent deny, so the call goes through and the debug log says so.
    const surfaces = await $.session.surfaces()
    if (surfaces.length === 0) {
      const at = await $.clock.now()
      await update($, holds, n => (n ?? 0) + 1)
      await update($, lastHold, () => ({ command: shown, rule, answer: 'unasked', at }))
      $.ui.log(`${PLUGIN}: ${rule} let through unheld — no surface to ask on: ${shown}`, { to: 'debug' })
      return next(e)
    }

    let answer: 'proceed' | 'cancel' | 'dismissed'
    try {
      const chosen = await $.ui.ask(`${PLUGIN}: this is a ${rule}. Run \`${shown}\`?`, { options: ['Proceed', 'Cancel'], header: 'Guard' })
      answer = chosen === 'Proceed' ? 'proceed' : 'cancel'
    } catch {
      // The dialog was dismissed (Esc) on a surface that drew it: the person was
      // asked and did not say Proceed.
      answer = 'dismissed'
    }
    const at = await $.clock.now()
    await update($, holds, n => (n ?? 0) + 1)
    await update($, lastHold, () => ({ command: shown, rule, answer, at }))
    if (answer === 'proceed') return next(e)
    await update($, cancelled, n => (n ?? 0) + 1)
    return { deny: `${PLUGIN}: ${rule} ${answer === 'dismissed' ? 'dismissed at the hold (Esc; answer Proceed to run it)' : 'cancelled at the hold'}: ${shown}` }
  }).catch(($, e, next) => next(e))

  // ----------------------------------------- 2. main-checkout write deny
  // The rule of hooks/enforce-worktree-edits.sh for the one case this hook
  // judges: the session sits in the main checkout, an objective is active, and
  // the target resolves inside the repository (not under .dev-files/, not in an
  // agent worktree). Everything else passes to the bash hook, which stays
  // canonical. The `.catch` lets the write through when this hook fails.
  //
  // The matcher is a RegExp rather than a list because `MultiEdit` is not in
  // this build's built-in tool table (2.1.302 folds it into `Edit`), and the
  // list form types against that table; the RegExp keeps the name for a build
  // that still registers it. `e` is therefore the whole union and the target
  // is read by key: `file_path` for Edit/Write/MultiEdit, `notebook_path` for
  // NotebookEdit.
  on('tool.call', { tool: /^(Edit|Write|MultiEdit|NotebookEdit)$/ }, async ($, e, next) => {
    if (!denyOn) return next(e)
    const target = 'notebook_path' in e ? e.notebook_path : 'file_path' in e ? e.file_path : undefined
    if (typeof target !== 'string' || target === '') return next(e)

    // The main checkout only: in a linked worktree $.session.root() is the
    // worktree and $.session.repo().root the main working tree, and they differ.
    const repo = await $.session.repo()
    if (!repo?.root) return next(e)
    const root = await $.session.root()
    if (trimSlash(root) !== trimSlash(repo.root)) return next(e)

    // Where the repository and the target really are: symlinks and `..` folded,
    // both sides resolved the same way. A target not there yet is placed by its
    // nearest existing ancestor. A path that cannot be placed is passed on —
    // the bash hook judges it; this mirror refuses only what it can show.
    let repoReal = trimSlash(repo.root)
    try {
      repoReal = trimSlash((await $.fs.stat(repo.root, { resolve: true })).realPath ?? repo.root)
    } catch {
      // The repo root always exists; keep its own spelling if resolution fails.
    }
    let real: string | undefined
    try {
      real = (await $.fs.stat(target, { resolve: true })).realPath
    } catch {
      real = undefined
    }
    if (real === undefined) {
      let dir = parentOf(target)
      let tail = baseOf(target)
      for (let climb = 0; climb < MAX_CLIMB && real === undefined; climb += 1) {
        const probe = dir === '' ? '.' : dir
        try {
          const found = (await $.fs.stat(probe, { resolve: true })).realPath
          if (found !== undefined) real = joinPath(found, tail)
        } catch {
          // not there either: climb one more
        }
        if (real !== undefined || dir === '' || dir === '/') break
        tail = `${baseOf(dir)}/${tail}`
        dir = parentOf(dir)
      }
    }
    if (real === undefined || !isUnder(real, repoReal)) return next(e)

    // The Claude config directory is version-controlled for backup, not a
    // project checkout (enforce-worktree-edits.sh's own carve-out).
    const configRoot = trimSlash((await $.env.get('CLAUDE_CONFIG_DIR')) || `${(await $.env.get('HOME')) ?? ''}/.claude`)
    if (configRoot !== '/.claude' && isUnder(repoReal, configRoot)) return next(e)

    const stateDirname = (await $.env.get('SUPERPOWERS_OBJECTIVE_STATE_DIRNAME')) || '.dev-files/objectives'
    const agentDirname = (await $.env.get('SUPERPOWERS_AGENT_WORKTREE_DIRNAME')) || '.agent-worktrees'
    const agentRoot = await $.env.get('SUPERPOWERS_AGENT_WORKTREE_ROOT')
    if (isUnder(real, joinPath(repoReal, '.dev-files'))) return next(e)
    if (isAgentWorkspacePath(real, repoReal, agentDirname, agentRoot)) return next(e)

    // Is an objective active? SUPERPOWERS_OBJECTIVE_ID wins; else the first
    // objective.json under the state directory whose status is `active` — the
    // same reading as hooks/lib/objective-common.sh active_objective_id.
    let objectiveId = (await $.env.get('SUPERPOWERS_OBJECTIVE_ID')) ?? ''
    if (objectiveId === '') {
      const stateDir = joinPath(repoReal, stateDirname)
      if (await $.fs.exists(stateDir)) {
        const ids = (await $.fs.list(stateDir)).filter(d => d.kind === 'dir').map(d => d.name).sort()
        for (const id of ids) {
          const path = `${stateDir}/${id}/objective.json`
          if (!(await $.fs.exists(path))) continue
          const obj = parseObject(await $.fs.read(path))
          if (obj && obj.status === 'active') {
            objectiveId = str(obj.id) || id
            break
          }
        }
      }
    }
    if (objectiveId === '') return next(e)

    const at = await $.clock.now()
    await update($, deniedWrites, n => (n ?? 0) + 1)
    await update($, lastDeniedWrite, () => ({ path: target, objectiveId, at }))
    return { deny: reasonFor(repoReal, objectiveId, agentDirname, agentRoot) }
  }).catch(($, e, next) => next(e))

  // ------------------------------------------------------------ 3. /guard
  on('command.run', { command: 'guard' }, async $ => {
    const h = await read($, holds)
    const c = await read($, cancelled)
    const last = await read($, lastHold)
    const d = await read($, deniedWrites)
    const lastWrite = await read($, lastDeniedWrite)
    return { text: guardText(holdOn, denyOn, h, c, last, d, lastWrite) }
  })
}
