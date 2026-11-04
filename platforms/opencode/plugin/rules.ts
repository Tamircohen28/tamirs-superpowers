// rules.ts — the pure decision functions behind the OpenCode 2 guard plugin.
//
// Nothing here touches the filesystem, the environment, a process or the OpenCode
// context. Every fact a rule needs arrives as an argument, so tests/test-opencode-v2.sh
// can drive each rule with plain Node (`node --test`), with no OpenCode host and no
// npm install. guard.ts is the thin IO layer that gathers the facts and wires
// these functions to ctx.permission.hook / ctx.shell.hook.
//
// Each function names the shell hook it mirrors. The hooks stay canonical
// (hooks/*.sh run on Claude Code, Codex and Cursor); this file is the OpenCode
// translation of their DECISIONS, not of their plumbing. Where a hook's judgment
// depends on something OpenCode cannot provide (a session worktree slug, a hook
// envelope), the narrower rule is stated and the reason recorded inline.
//
// ADR 004 (docs/engineering/decisions/004-permission-levels.md) adds two things here:
// the protected-path table of D10.1 (mirrored from hooks/lib/write-targets.py, held
// equal to core/permissions/actions.json by rules.test.mjs) and the pure half of the
// permission-guard bridge (D8): the payload guard.ts hands to hooks/permission-guard.sh
// and the reading of its answer. On OpenCode every ask is delivered as a deny, because
// `opencode --auto` approves a plugin ask (measured O1c) and only a deny is final (O1b).
//
// Erasable TypeScript only — no enums, no parameter properties, no namespaces —
// so `node file.ts` works without a build step.

export type Effect = "allow" | "ask" | "deny"

export interface Decision {
  readonly effect: Effect
  readonly reason?: string
}

export const ALLOW: Decision = { effect: "allow" }

export function deny(reason: string): Decision {
  return { effect: "deny", reason }
}

// ---------------------------------------------------------------- paths ---

// Normalise a path for pattern matching: forward slashes, no trailing slash.
export function normPath(p: string): string {
  let s = p.replace(/\\/g, "/")
  while (s.length > 1 && s.endsWith("/")) s = s.slice(0, -1)
  return s
}

// True when `child` is `parent` or lies beneath it (both already absolute).
export function isWithin(child: string, parent: string): boolean {
  const c = normPath(child)
  const p = normPath(parent)
  if (!p) return false
  return c === p || c.startsWith(p.endsWith("/") ? p : p + "/")
}

// ---------------------------------------------- hooks/guard-sensitive-files.sh ---

export interface SensitiveFacts {
  /** git toplevel of the file being written, when it is inside a repo. */
  readonly repoRoot?: string | null
  /** `<repoRoot>/components.json` exists (shadcn) — the only honest signal that components/ui/ is generated. */
  readonly hasShadcnConfig?: boolean
  /** `git check-ignore` says the path is ignored (only consulted for build-output dirs). */
  readonly gitIgnored?: boolean
}

/** write: a file. delete: a file or tree removed. tree: a path a copy, move, link or extraction fills. */
export type WriteKind = "write" | "delete" | "tree"

/**
 * Mirrors the `classify` function of hooks/guard-sensitive-files.sh rule for rule
 * (the generated-file pass; the R4 protected paths are protectedReason below).
 * Returns the deny reason, or null when the path is not protected. Like the shell
 * hook, no text names an override (ADR 004 D10.5): the user's PM_ALLOW_PROTECTED=1
 * still skips this pass, but a deny never advertises it to the agent.
 */
/**
 * The workflow half of sensitiveReason, exported on its own because no environment switch may
 * reach it (ADR 004 D3, F6): guard-sensitive-files.sh judges it before PM_ALLOW_PROTECTED. The
 * workflows directory itself counts, and so does a `.github` that a delete or a tree write removes
 * or fills (the shell hook also checks the directory exists; this pure rule cannot, so it denies).
 */
export function workflowReason(file: string, kind: WriteKind = "write", via = ""): string | null {
  const f = normPath(file)
  const context = via ? ` (via: ${via})` : ""
  const holds = /\/\.github$/.test(f) && (kind === "delete" || kind === "tree")
  if (!/\/\.github\/workflows(?:\/|$)/.test(f) && !holds) return null
  // R4 `workflow.edit` (ADR 004 D10.5): the remedy is the user, not a route around
  // this guard — a remote write tool is the same change with no guard on it.
  return (
    `BLOCKED: '${file}' ${holds ? "holds the GitHub Actions workflows" : "is a GitHub Actions workflow"}.${context} ` +
    "Changing a workflow is an R4 action (workflow.edit): ask the user to approve this exact change and to make it themselves, " +
    "rather than routing it through another tool or a remote API."
  )
}

export function sensitiveReason(file: string, facts: SensitiveFacts = {}, kind: WriteKind = "write", via = ""): string | null {
  const f = normPath(file)
  const context = via ? ` (via: ${via})` : ""
  const workflow = workflowReason(file, kind, via)
  if (workflow) return workflow
  if (/\.lock$|\/package-lock\.json$|\/pnpm-lock\.yaml$|\/bun\.lockb$|\/go\.sum$/.test(f)) {
    return (
      `BLOCKED: '${file}' is a package-manager lockfile — it is generated, never hand-edited.${context} ` +
      "Change the manifest (package.json / Cargo.toml / pyproject.toml / go.mod) and re-run the package manager so the lockfile is regenerated."
    )
  }
  if (f.includes("/.yarn/releases/")) {
    return `BLOCKED: '${file}' is the vendored Yarn binary under .yarn/releases/.${context} Change it with 'yarn set version <version>', not by editing the file.`
  }
  if (/\/components\/ui\//.test(f)) {
    if (facts.repoRoot && facts.hasShadcnConfig) {
      return (
        `BLOCKED: '${file}' sits under components/ui/ in a shadcn project (detected: ${facts.repoRoot}/components.json) — these files are generated.${context} ` +
        "Re-generate with the shadcn CLI's add command, or move your customisation into a wrapper component outside components/ui/."
      )
    }
    return null
  }
  if (/\/(dist|build|out|\.next|target\/debug|target\/release)\//.test(f)) {
    // Blocked only when git ignores it, and only for content — `rm -rf dist/` is fine.
    if (kind !== "delete" && facts.repoRoot && facts.gitIgnored) {
      return (
        `BLOCKED: '${file}' is build output — git ignores this path in ${facts.repoRoot}, so it is regenerated by the build and any edit here is discarded.${context} ` +
        "Change the source and re-run the build."
      )
    }
  }
  return null
}

// ------------------------------- protected paths (ADR 004 D10.1, hooks/lib/write-targets.py) ---
//
// The plugin's permission policy, its guard files and every host settings store that
// could widen what an agent may do are R4 `policy.edit` (plus `config.global.write`
// for a repository's .git/hooks and .git/config). No environment switch unlocks them:
// PM_ALLOW_PROTECTED reaches only the generated-file rules above. The table is the
// `equivalents.paths` of those two ids in core/permissions/actions.json, the same
// fallback write-targets.py carries; rules.test.mjs holds all three equal.

export type ProtectedId = "policy.edit" | "config.global.write"

export const PROTECTED_PATHS: Readonly<Record<ProtectedId, readonly string[]>> = {
  "policy.edit": [
    "{home}/.config/tamirs-superpowers/**",
    "{home}/.local/state/tamirs-superpowers/**",
    "{repo}/.tamirs-superpowers/**",
    "{plugin_root}/hooks/**",
    "{plugin_root}/core/permissions/**",
    "{plugin_root}/scripts/resolve-permission.sh",
    "{plugin_root}/scripts/plugin-config.sh",
    "{plugin_root}/scripts/lib/permission-common.sh",
    "{home}/.claude/plugins/cache/**",
    "{home}/.claude/settings*.json",
    "{repo}/.claude/settings*.json",
    "{home}/.gemini/settings.json",
    "{home}/.gemini/policies/**",
    "{home}/.gemini/extensions/tamirs-superpowers/**",
    "{repo}/.gemini/**",
    "{home}/.codex/config.toml",
    "{home}/.codex/hooks*",
    "{home}/.codex/rules/**",
    "{home}/.codex/plugins/**",
    "{home}/.cursor/hooks.json",
    "{home}/.cursor/cli-config.json",
    "{home}/.cursor/permissions.json",
    "{repo}/.cursor/hooks.json",
    "{home}/.config/opencode/**",
    "{repo}/opencode.json",
    "{repo}/.opencode/**",
    "{home}/.config/gh/**",
    "{home}/.gitconfig",
  ],
  "config.global.write": ["{repo}/.git/hooks/**", "{repo}/.git/config"],
}

export interface ProtectedFacts {
  /** The passwd home first, then the session HOME: protecting one more directory only tightens (D3). */
  readonly homes: readonly string[]
  /** The running plugin's root; a `.git` at that root makes it a source checkout, where guard files are an R4 ask. */
  readonly pluginRoots: readonly { readonly root: string; readonly sourceCheckout: boolean }[]
  /** True for a directory that holds a `.git` entry, or is the session cwd: what `{repo}` means. */
  readonly isRepoRoot: (dir: string) => boolean
  /**
   * Whether the volume holding a path matches names case-insensitively (macOS APFS): true, false, or null
   * when it cannot tell. Absent or null folds — folding only ever protects one spelling more (F4a).
   */
  readonly caseInsensitive?: (path: string) => boolean | null
}

export interface ProtectedHit {
  readonly mode: "deny" | "ask"
  readonly id: ProtectedId
  readonly pattern: string
  /** The spelling of the path that matched (its lexical form or its realpath). */
  readonly form: string
}

function reEscape(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

/** write-targets.py `_tail_regex`: a path glob tail as a regex, `**` crosses directories and `*` does not. */
export function globTailRegex(tail: string): string {
  const dirGlob = tail.endsWith("/**")
  const t = dirGlob ? tail.slice(0, -3) : tail
  let out = ""
  for (let i = 0; i < t.length; i++) {
    if (t.startsWith("**", i)) {
      out += ".*"
      i++
    } else if (t[i] === "*") out += "[^/]*"
    else if (t[i] === "?") out += "[^/]"
    else out += reEscape(t[i])
  }
  return out + (dirGlob ? "(?:/.*)?" : "")
}

/** The literal part of a tail, before its first glob character. */
function fixedPart(tail: string): string {
  const m = /[*?[]/.exec(tail)
  return m ? tail.slice(0, m.index) : tail
}

/** Every proper ancestor directory of an absolute path, `/` excluded (write-targets.py `_ancestors`). */
function ancestors(form: string): string[] {
  const parts = form.split("/")
  const out: string[] = []
  for (let i = 2; i < parts.length; i++) out.push(parts.slice(0, i).join("/"))
  return out
}

/**
 * guard.ts resolves a written `~/x` (or `$HOME/x`) against the cwd, as `<cwd>/~/x`; the shell
 * expands it to a home. Each such spelling is judged under every home too (it only tightens).
 */
function withHomeForms(forms: readonly string[], homes: readonly string[]): string[] {
  const out = [...forms]
  for (const raw of forms) {
    const p = normPath(raw)
    const m = /\/(?:~|\$HOME|\$\{HOME\})(\/.*)?$/.exec(p)
    if (!m) continue
    for (const h of homes) {
      const x = normPath(h) + (m[1] ?? "")
      if (!out.includes(x)) out.push(x)
    }
  }
  return out
}

/**
 * write-targets.py `Protection.match`: every protected rule a path hits, judged on each
 * spelling in `forms` (the lexical path and its realpath, both absolute), case-folded unless
 * `facts.caseInsensitive` shows the volume is case-sensitive. `containing` also counts a
 * path that is an ANCESTOR of a protected one — home, plugin-root and repo-relative alike
 * (deleting or moving `.claude` away removes `.claude/settings.json`). A `{repo}` root
 * itself may be deleted (a temporary repository stays removable), but `tree` — a copy, move
 * or extraction INTO the path — counts the root too: an archive unpacked over a repository
 * can rewrite its settings.
 */
export function protectedHits(forms: readonly string[], facts: ProtectedFacts, containing = false, tree = false): ProtectedHit[] {
  const hits: ProtectedHit[] = []
  const within = containing || tree
  const all = withHomeForms(forms, facts.homes)
  for (const id of Object.keys(PROTECTED_PATHS) as ProtectedId[]) {
    for (const pattern of PROTECTED_PATHS[id]) {
      const m = /^\{(home|repo|plugin_root)\}\/(.+)$/.exec(pattern)
      if (!m) continue
      const [, ph, tail] = m
      const tre = globTailRegex(tail)
      for (const raw of all) {
        const form = normPath(raw)
        const fold = facts.caseInsensitive ? facts.caseInsensitive(form) !== false : true
        const f = (x: string) => (fold ? x.toLowerCase() : x)
        const below = form === "/" ? "/" : f(form) + "/"
        if (ph === "repo") {
          const rx = new RegExp("^" + tre + "$", fold ? "i" : "")
          const roots = ancestors(form).filter((r) => facts.isRepoRoot(r))
          let hit = roots.some((r) => rx.test(form.slice(r.length + 1)))
          if (!hit && within) {
            const bases = tree && facts.isRepoRoot(form) ? [...roots, form] : roots
            hit = bases.some((r) => f(r + "/" + fixedPart(tail)).startsWith(below))
          }
          if (hit) hits.push({ mode: "deny", id, pattern, form })
          continue
        }
        const roots =
          ph === "home"
            ? facts.homes.map((h) => ({ root: h, mode: "deny" as const }))
            : facts.pluginRoots.map((r) => ({ root: r.root, mode: r.sourceCheckout ? ("ask" as const) : ("deny" as const) }))
        for (const { root, mode } of roots) {
          const base = normPath(root)
          if (!base || base === "/") continue
          const rx = new RegExp("^" + reEscape(base) + "/" + tre + "$", fold ? "i" : "")
          const fixed = base + "/" + fixedPart(tail)
          if (rx.test(form) || (within && f(fixed).startsWith(below))) hits.push({ mode, id, pattern, form })
        }
      }
    }
  }
  return hits
}

/** What a write of each kind would do to a protected path, in guard-sensitive-files.sh's words. */
export type TargetKind = WriteKind | "move" | "link"
const KIND_WORDS: Readonly<Record<TargetKind, string>> = {
  write: "would be written",
  delete: "would be deleted",
  tree: "would receive a whole directory tree (a copy, move, link or extraction)",
  move: "would be moved away",
  link: "would become reachable through a new link",
}

/** The R4 remedy (D10.3, D10.5): only the user changes these, outside the agent's reach. It names no bypass. */
export const PROTECTED_REMEDY =
  "Only the user changes plugin permission policy, guard files and host settings (ADR 004 D10): stop and ask them to make " +
  "this change themselves, outside this session. Do not retry it through another tool, command or path."

/**
 * The protected-path verdict for one target, or null. A deny on any spelling wins
 * over an ask; an ask (a guard file of a source checkout) is still an R4 ask, which
 * OpenCode cannot carry — guard.ts delivers it as a deny (D8).
 */
export function protectedReason(
  file: string,
  forms: readonly string[],
  facts: ProtectedFacts,
  kind: TargetKind = "write",
  via = "",
): { readonly mode: "deny" | "ask"; readonly reason: string } | null {
  const hits = protectedHits(forms, facts, kind === "delete" || kind === "move" || kind === "link" || kind === "tree", kind === "tree")
  if (!hits.length) return null
  const hit = hits.find((h) => h.mode === "deny") ?? hits[0]
  const resolved = hit.form === normPath(file) ? "" : ` (resolves to '${hit.form}')`
  const context = via ? ` (via: ${via})` : ""
  const what = `'${file}'${resolved} ${KIND_WORDS[kind]}, and it is protected as ${hit.id} (R4; matches ${hit.pattern}).${context}`
  if (hit.mode === "deny") return { mode: "deny", reason: `BLOCKED: ${what} ${PROTECTED_REMEDY}` }
  return {
    mode: "ask",
    reason:
      `R4 ASK: ${what} This plugin runs from a source checkout, so its guard files are editable, but only with the ` +
      "user's explicit approval of this change.",
  }
}

/** D8 on OpenCode: an ask is not a guard under `--auto` (O1c), so every R3/R4 ask leaves here as a deny. */
export function deliverAsDeny(reason: string): Decision {
  return deny(
    `${reason} OpenCode cannot carry this ask: \`opencode --auto\` approves a plugin ask (measured O1), so it is delivered as a deny (ADR 004 D8).`,
  )
}

// ---------------------------------------------- hooks/enforce-worktree-edits.sh ---

export interface WorktreeFacts {
  /** Main checkout root of the repo the path belongs to; null when the path is not in a git repo. */
  readonly mainRoot: string | null
  /** Active objective id (SUPERPOWERS_OBJECTIVE_ID, or an objective.json with status "active"); null when none. */
  readonly objectiveId: string | null
  /** SUPERPOWERS_AGENT_WORKTREE_ROOT — objective worktrees relocated outside the repo. */
  readonly agentWorktreeRoot?: string
  /** SUPERPOWERS_AGENT_WORKTREE_DIRNAME, default ".agent-worktrees". */
  readonly agentWorktreeDirname?: string
  /** CLAUDE_CONFIG_DIR or ~/.claude — machine housekeeping, never forced through a worktree. */
  readonly claudeConfigRoot?: string
  /** WORKTREE_ROOT or ~/.claude/worktrees — the legacy single-task layout. */
  readonly globalWorktreeRoot?: string
}

/**
 * Mirrors is_agent_workspace / is_objective_worktree_path / is_platform_worktree_path
 * from hooks/lib/objective-common.sh: every layout in which repo edits are legitimate.
 */
export function isAgentWorkspacePath(path: string, facts: WorktreeFacts): boolean {
  const p = normPath(path)
  const dirname = facts.agentWorktreeDirname || ".agent-worktrees"
  if (p.includes(`/${dirname}/`)) return true
  if (facts.agentWorktreeRoot && isWithin(p, facts.agentWorktreeRoot)) return true
  if (/\/\.(claude|cursor|codex)\/\.worktrees\//.test(p)) return true
  if (facts.globalWorktreeRoot && isWithin(p, facts.globalWorktreeRoot)) return true
  if (/\/\.claude\/worktrees\//.test(p)) return true
  return false
}

/**
 * Mirrors judge_target_dir of hooks/enforce-worktree-edits.sh for the objective
 * case. The shell hook denies a main-checkout edit even with no objective, because
 * it can name (and recreate) the session's own worktree as the remedy; OpenCode has
 * no session-slug machinery to derive that worktree from, so a deny there would be
 * a dead end with no destination — the exact "degraded path" the shell hook
 * refuses to create. Hence: no objective, no verdict. With an objective active the
 * remedy exists (the orchestrator's own worktrees) and the deny is the same text.
 */
export function judgeEdit(path: string, facts: WorktreeFacts): Decision {
  if (!facts.mainRoot) return ALLOW
  if (!facts.objectiveId) return ALLOW
  const p = normPath(path)
  if (facts.claudeConfigRoot && isWithin(p, facts.claudeConfigRoot)) return ALLOW
  if (isAgentWorkspacePath(p, facts)) return ALLOW
  if (!isWithin(p, facts.mainRoot)) return ALLOW
  const base = facts.agentWorktreeRoot
    ? normPath(facts.agentWorktreeRoot)
    : `${normPath(facts.mainRoot)}/${facts.agentWorktreeDirname || ".agent-worktrees"}`
  return deny(
    `Repo edits must happen in an objective worktree, not the main checkout (${facts.mainRoot}). ` +
      `Objective '${facts.objectiveId}' is active: work in ${base}/${facts.objectiveId}/task-NNN (worker) or .../integration (integrator). ` +
      "Ask the orchestrator which one is yours — do not create a new worktree.",
  )
}

// ------------------------------------------------------------- objectives ---

export interface ObjectiveEntry {
  readonly id: string
  readonly json: string | null
}

export function parseObject(text: string | null): Record<string, unknown> | null {
  if (text === null) return null
  try {
    const v: unknown = JSON.parse(text)
    return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null
  } catch {
    return null
  }
}

/**
 * Mirrors active_objective_id of hooks/lib/objective-common.sh: the env override
 * wins; else the first objective.json whose status is "active" (ids sorted); else
 * none. Deliberately NOT the mod's looser "first not completed/abandoned" fallback —
 * the guard must only ever deny on the same signal the shell hook denies on.
 */
export function activeObjectiveId(entries: readonly ObjectiveEntry[], envOverride: string | undefined): string | null {
  if (envOverride) return envOverride
  for (const e of [...entries].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))) {
    const obj = parseObject(e.json)
    if (!obj || obj.status !== "active") continue
    return typeof obj.id === "string" && obj.id ? obj.id : e.id
  }
  return null
}

// ------------------------------------------------- hooks/lib/agent-claim.sh ---

/** Filesystem-safe key for a resource identifier — the same bytes claim_key emits. */
export function claimKey(resource: string): string {
  return resource.replace(/[/:@#]/g, "_").replace(/[^A-Za-z0-9._-]/g, "_")
}

export type ClaimStatus = "FREE" | "MINE" | "LIVE" | "STALE" | "ERROR"

export interface ClaimVerdict {
  readonly status: ClaimStatus
  readonly holder?: string
  readonly tool?: string
  readonly ageSeconds?: number
  readonly detail: string
}

export interface ClaimClock {
  readonly now: number // epoch seconds
  readonly host: string
  /** true = alive, false = gone, null = cannot tell (treated as alive, like the shell's EPERM caveat). */
  readonly pidAlive: (pid: number) => boolean | null
  readonly staleSeconds: number // AGENT_CLAIM_STALE_SECONDS, default 900
}

/**
 * Mirrors claim_inspect. `json` is the claim file's text (null = no file). ERROR is
 * returned for anything unreadable or malformed, and callers must treat it as a
 * hard failure — never as FREE.
 */
export function inspectClaim(json: string | null | undefined, me: string, clock: ClaimClock): ClaimVerdict {
  if (json === null || json === undefined) return { status: "FREE", detail: "no claim file" }
  const obj = parseObject(json)
  if (!obj) return { status: "ERROR", detail: "claim file is not valid JSON — claim state is corrupt and cannot be evaluated" }
  const holder = typeof obj.agent_id === "string" ? obj.agent_id : ""
  const tool = typeof obj.tool === "string" ? obj.tool : "unknown"
  const hbRaw = obj.heartbeat_at
  const hb = typeof hbRaw === "number" ? hbRaw : typeof hbRaw === "string" && /^[0-9]+$/.test(hbRaw) ? Number(hbRaw) : NaN
  if (!holder || !Number.isFinite(hb)) {
    return { status: "ERROR", detail: "claim file is missing required fields (agent_id/heartbeat_at) — claim state cannot be evaluated" }
  }
  const age = Math.max(0, clock.now - hb)
  if (holder === me) return { status: "MINE", holder, tool, ageSeconds: age, detail: "self" }
  const pid = typeof obj.pid === "number" ? obj.pid : typeof obj.pid === "string" && /^[0-9]+$/.test(obj.pid) ? Number(obj.pid) : NaN
  const host = typeof obj.host === "string" ? obj.host : ""
  if (host && host === clock.host && Number.isFinite(pid)) {
    if (clock.pidAlive(pid) === false) {
      return { status: "STALE", holder, tool, ageSeconds: age, detail: `holder pid ${pid} is gone on this host` }
    }
  }
  if (age > clock.staleSeconds) {
    return { status: "STALE", holder, tool, ageSeconds: age, detail: `heartbeat older than ${clock.staleSeconds}s` }
  }
  return { status: "LIVE", holder, tool, ageSeconds: age, detail: `heartbeat ${age}s ago` }
}

// ---------------------------------------------------- shell structure parsing ---
//
// A port of claim_shell_segments / claim_effective_segments: the command string is
// read the way a shell reads it. Quoted text and heredoc bodies are ARGUMENTS and
// can never be commands; only the first word of a real segment names the program.
// `git commit -m "git push origin main"` therefore invokes no push.

export type Segment = string[]

export function shellSegments(s: string): Segment[] {
  const out: Segment[] = []
  let seg: string[] = []
  let tok = ""
  let haveTok = false
  let state = 0 // 0 unquoted, 1 single, 2 double
  let expectHd = false
  const pendingHd: string[] = []
  const stack: number[] = []
  let i = 0
  const n = s.length

  const emitTok = () => {
    if (haveTok) {
      if (expectHd) {
        expectHd = false
        pendingHd.push(tok)
      } else {
        seg.push(tok.replace(/\n/g, " "))
      }
    }
    tok = ""
    haveTok = false
  }
  const emitSeg = () => {
    emitTok()
    if (seg.length) out.push(seg)
    seg = []
  }
  const skipHeredocs = () => {
    while (pendingHd.length) {
      const delim = pendingHd.shift() as string
      while (i < n) {
        let j = i
        while (j < n && s[j] !== "\n") j++
        const line = s.slice(i, j).trim()
        i = j < n ? j + 1 : n
        if (line === delim) break
      }
    }
  }

  while (i < n) {
    const c = s[i]
    if (state === 1) {
      if (c === "'") state = 0
      else tok += c
      i++
      continue
    }
    if (state === 2) {
      if (c === "\\" && i + 1 < n) {
        const c2 = s[i + 1]
        if (c2 === '"' || c2 === "\\" || c2 === "$" || c2 === "`") {
          tok += c2
          i += 2
          continue
        }
        tok += c
        i++
        continue
      }
      if (c === '"') {
        state = 0
        i++
        continue
      }
      if (c === "$" && s[i + 1] === "(") {
        stack.push(2)
        emitSeg()
        state = 0
        i += 2
        continue
      }
      tok += c
      haveTok = true
      i++
      continue
    }
    // A `#` that starts a word starts a comment: an apostrophe in it is prose, not a quote.
    if (c === "#" && !haveTok) {
      while (i < n && s[i] !== "\n") i++
      continue
    }
    // `$'…'` — ANSI-C quoting, where `\'` is a quote character, not the end of the quote.
    if (c === "$" && s[i + 1] === "'") {
      let j = i + 2
      while (j < n && s[j] !== "'") {
        if (s[j] === "\\" && j + 1 < n) {
          tok += s[j + 1]
          j += 2
        } else tok += s[j++]
      }
      haveTok = true
      i = j + 1
      continue
    }
    // `(( … ))` is arithmetic: `<<` there is a shift, never a heredoc.
    if (c === "(" && s[i + 1] === "(" && !haveTok) {
      let depth = 0
      let j = i
      for (; j < n; j++) {
        if (s[j] === "(") depth++
        else if (s[j] === ")" && --depth === 0) break
      }
      if (j < n && s[j - 1] === ")") {
        tok = s.slice(i, j + 1)
        haveTok = true
        i = j + 1
        continue
      }
    }
    if (c === "'") {
      state = 1
      haveTok = true
      i++
      continue
    }
    if (c === '"') {
      state = 2
      haveTok = true
      i++
      continue
    }
    if (c === "\\") {
      if (i + 1 < n) {
        const c2 = s[i + 1]
        if (c2 !== "\n") {
          tok += c2
          haveTok = true
        }
        i += 2
      } else i++
      continue
    }
    if (c === "$" && s[i + 1] === "(") {
      stack.push(0)
      emitSeg()
      i += 2
      continue
    }
    if (c === ")" && stack.length) {
      emitSeg()
      state = stack.pop() as number
      i++
      continue
    }
    if (c === "<" && s[i + 1] === "<") {
      emitTok()
      if (s[i + 2] === "<") {
        i += 3
      } else {
        i += 2
        if (s[i] === "-") i++
        expectHd = true
      }
      continue
    }
    if (c === ">" || c === "<" || (c === "&" && s[i + 1] === ">")) {
      // A pending all-digits token is this redirect's fd prefix, not an argument.
      if (/^[0-9]+$/.test(tok)) {
        tok = ""
        haveTok = false
      }
      emitTok()
      if (c === "&") i++
      i++
      if (s[i] === ">") i++
      if (s[i] === "&") i++
      while (i < n && (s[i] === " " || s[i] === "\t")) i++
      while (i < n && !" \t\n;&|()".includes(s[i])) i++
      continue
    }
    if (c === " " || c === "\t") {
      emitTok()
      i++
      continue
    }
    if (c === "\n") {
      emitSeg()
      i++
      skipHeredocs()
      continue
    }
    if (";&|()`".includes(c)) {
      emitSeg()
      i++
      continue
    }
    tok += c
    haveTok = true
    i++
  }
  emitSeg()
  return out
}

const WRAPPERS = new Set(["sudo", "env", "command", "builtin", "exec", "nohup", "nice", "time", "timeout", "stdbuf"])

/** claim_effective_segments: leading FOO=bar and wrappers removed; `sh -c '<string>'` descended into. */
export function effectiveSegments(command: string, depth = 0): Segment[] {
  const out: Segment[] = []
  for (const toks of shellSegments(command)) {
    let k = 0
    let wrapped = false
    while (k < toks.length) {
      const t = toks[k]
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) k++
      else if (WRAPPERS.has(t)) {
        k++
        wrapped = true
      } else if ((t.startsWith("-") || /^[0-9]/.test(t)) && wrapped) k++
      else break
    }
    if (k >= toks.length) continue
    const base = toks[k].split("/").pop() as string
    if (["sh", "bash", "zsh", "ksh", "dash"].includes(base) && depth < 4) {
      const ci = toks.indexOf("-c", k + 1)
      if (ci > 0 && ci + 1 < toks.length) {
        out.push(...effectiveSegments(toks[ci + 1], depth + 1))
        continue
      }
    }
    out.push(toks.slice(k))
  }
  return out
}

// ---------------------------------------------------------- git push parsing ---

export interface PushInvocation {
  /** Resolved destination branches; empty when `error` is set. */
  readonly dests: string[]
  /** --force / -f / --force-with-lease / --force-if-includes / +refspec */
  readonly force: boolean
  /** Set when the destination cannot be determined — the caller must fail loud, never allow. */
  readonly error?: string
}

/**
 * Mirrors claim_push_destinations plus a force flag. One entry per `git push`
 * segment; `[]` when the command invokes no push at all. `fallback` is the
 * current branch's upstream (or name), used ONLY where git itself would use it.
 */
export function gitPushes(command: string, fallback: string | null): PushInvocation[] {
  const pushes: PushInvocation[] = []
  for (const toks of effectiveSegments(command)) {
    if (!toks.length) continue
    const base = toks[0].split("/").pop()
    if (base !== "git") continue
    let j = 1
    let argstart = -1
    while (j < toks.length) {
      const t = toks[j]
      if (["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"].includes(t)) j += 2
      else if (t === "push") {
        argstart = j + 1
        break
      } else if (t.startsWith("-")) j++
      else break
    }
    if (argstart < 0) continue

    let force = false
    let del = false
    let broad = ""
    let noMoreFlags = false
    const positional: string[] = []
    for (let i = argstart; i < toks.length; i++) {
      const t = toks[i]
      if (noMoreFlags) {
        positional.push(t)
        continue
      }
      if (t === "--") noMoreFlags = true
      else if (t === "-d" || t === "--delete") del = true
      else if (t === "--all" || t === "--mirror") broad = t
      else if (["-o", "--push-option", "--receive-pack", "--exec", "--repo"].includes(t)) i++
      else if (t === "--force" || t.startsWith("--force-with-lease") || t === "--force-if-includes") force = true
      else if (/^-[a-zA-Z]+$/.test(t)) {
        if (t.includes("f")) force = true
      } else if (t.startsWith("-")) {
        /* other long flag */
      } else positional.push(t)
    }
    if (positional.some((p) => p.startsWith("+"))) force = true

    if (broad) {
      pushes.push({ dests: [], force, error: `the push uses ${broad}, which sends every ref — the set of destination branches cannot be enumerated from the command` })
      continue
    }
    if (positional.length <= 1) {
      if (del) {
        pushes.push({ dests: [], force, error: "--delete was given with no ref to delete, so the destination branch cannot be determined" })
        continue
      }
      if (!fallback) {
        pushes.push({ dests: [], force, error: "the push names no refspec and the current branch/upstream could not be resolved, so the destination branch cannot be determined" })
        continue
      }
      pushes.push({ dests: [fallback], force })
      continue
    }
    const dests: string[] = []
    let error: string | undefined
    for (const spec of positional.slice(1)) {
      let dst = spec.replace(/^\+/, "")
      let hadColon = false
      if (dst.includes(":")) {
        hadColon = true
        dst = dst.slice(dst.indexOf(":") + 1)
      }
      dst = dst.replace(/^refs\/heads\//, "")
      if (dst === "HEAD" && !hadColon) {
        if (!fallback) {
          error = "the push targets HEAD but the current branch could not be resolved, so the destination branch cannot be determined"
          break
        }
        dst = fallback
      }
      if (dst === "" || dst === "HEAD" || dst.includes("*")) {
        error = `refspec ${spec} does not resolve to a single named destination branch`
        break
      }
      dests.push(dst)
    }
    pushes.push(error ? { dests: [], force, error } : { dests, force })
  }
  return pushes
}

// ------------------------------------------- hooks/protect-other-branches.sh ---

export interface PushFacts {
  /** `owner/repo` of the origin remote; null when it cannot be determined. */
  readonly repoSlug: string | null
  /** Upstream (or name) of the current branch, for a bare `git push`. */
  readonly fallbackBranch: string | null
  /** This agent's claim id — claims it holds itself are MINE, never a block. */
  readonly me: string
  /** Reads the claim for `git:<slug>@<branch>`; receives the claim-file text (null = none). */
  readonly inspect: (resource: string) => ClaimVerdict
  /** When SUPERPOWERS_ROLE=integrator and an objective is active, that objective's id (carve-out for its worker branches). */
  readonly integratorObjectiveId?: string | null
  /** Protected branches a force push is refused on outright (default: every branch). */
  readonly forceAllowedPrefixes?: readonly string[]
}

export function isWorkerBranch(branch: string): boolean {
  return /^worker\/[^/]+\/.+/.test(branch)
}

export function objectiveIdFromBranch(branch: string): string {
  if (branch.startsWith("objective/")) return branch.slice("objective/".length)
  if (branch.startsWith("worker/")) return branch.slice("worker/".length).split("/")[0]
  return ""
}

/**
 * The push half of protect-other-branches.sh, plus the force-push refusal that
 * rules/dev/git-worktree-agent-workflow.md states and the shell hook leaves to the
 * branch-protection layer. Returns ALLOW for a command with no `git push` in it.
 */
export function judgePush(command: string, facts: PushFacts): Decision {
  const pushes = gitPushes(command, facts.fallbackBranch)
  if (!pushes.length) return ALLOW
  for (const push of pushes) {
    if (push.error) {
      return deny(`BLOCKED: this command cannot be checked for conflicts with other agents — ${push.error}. Name the destination explicitly (git push <remote> <branch>) and retry.`)
    }
    for (const branch of push.dests) {
      if (push.force) {
        const ok = (facts.forceAllowedPrefixes ?? []).some((p) => branch.startsWith(p))
        if (!ok) {
          return deny(
            `BLOCKED: force push to '${branch}' refused. A force push rewrites history other agents and the integrator may have already built on; ` +
              "rebase onto the branch tip and push normally, or ask the user to run the force push themselves.",
          )
        }
      }
      if (!facts.repoSlug) {
        return deny(
          `BLOCKED: 'git push' to '${branch}' targets a repository that could not be identified (no origin remote), so the guard cannot tell whether another agent is working on that branch.`,
        )
      }
      const resource = `git:${facts.repoSlug}@${branch}`
      const v = facts.inspect(resource)
      if (v.status === "ERROR") {
        return deny(`BLOCKED: cannot determine whether another agent holds ${resource}: ${v.detail}. Fix the claim state under ~/.agent-work-claims and retry.`)
      }
      if (v.status === "LIVE") {
        const carve = facts.integratorObjectiveId && isWorkerBranch(branch) && objectiveIdFromBranch(branch) === facts.integratorObjectiveId
        if (!carve) {
          return deny(
            `BLOCKED: another agent is actively working on ${resource} (${v.tool ?? "unknown"} ${v.holder ?? ""}, ${v.detail}). ` +
              "Pushing to it now would race their work. Wait for their claim to lapse, coordinate through the orchestrator, or push to your own branch.",
          )
        }
      }
    }
  }
  return ALLOW
}

// ------------------------------------------------------- shell write targets ---

export interface ShellWriteTarget {
  readonly path: string
  /** write / delete: the file changes. move: an `mv` source (moved away is deleted). link: an `ln` target made reachable. */
  readonly kind: TargetKind
  readonly via: string
  /** For a symbolic `ln` source: the link operand, against whose directory a relative target resolves. */
  readonly linkAt?: string
}

/**
 * The subset of hooks/lib/write-targets.py this plugin can read without Python:
 * redirect operands on any fd (`>`, `>>`, `3>`, `<>`, `>& FILE`, under `exec` too),
 * `tee`, `sed -i`, `cp`/`mv`/`install`/`ln`/`rsync` destinations, `tar -x`/`unzip`
 * extraction directories, `mv`, `ln` and `cp -l`/`-s` sources (judged by the
 * protected-path rules only, as write-targets.py judges its SOURCE records) and `rm`
 * operands. A destination that can receive a whole directory (`mv`, `ln`, `rsync`,
 * `cp -r`, an extraction) is a `tree` target: a protected path inside it counts
 * (F4b). Anything built at runtime (`> "$OUT"`, xargs, find -exec, interpreters), git
 * replays and patches are invisible here — the Python helper reports or judges those
 * and this port, honestly, does not see them at all. Paths are returned as written;
 * the caller resolves them against the command's cwd.
 */
/** Destinations that are always directories, though the parse cannot stat them: `cp -r x ~` fills ~/x. */
const DIR_WORDS = /^(?:~[A-Za-z0-9_.-]*|\.|\.\.|\$HOME|\$\{HOME\})$/

function baseName(p: string): string {
  return p.replace(/\/+$/, "").split("/").pop() as string
}

function joinPath(dir: string, name: string): string {
  return dir.replace(/\/+$/, "") + "/" + name
}

export function shellWriteTargets(command: string): ShellWriteTarget[] {
  const out: ShellWriteTarget[] = []
  // Redirect operands are dropped by shellSegments (they are not arguments), so
  // scan the raw text for them separately, outside quotes.
  let state = 0
  for (let i = 0; i < command.length; i++) {
    const c = command[i]
    if (state === 1) {
      if (c === "'") state = 0
      continue
    }
    if (state === 2) {
      if (c === "\\") {
        i++
        continue
      }
      if (c === '"') state = 0
      continue
    }
    if (c === "#" && (i === 0 || " \t\n;&|(".includes(command[i - 1]))) {
      while (i + 1 < command.length && command[i + 1] !== "\n") i++
    } else if (c === "$" && command[i + 1] === "'") {
      let j = i + 2
      while (j < command.length && command[j] !== "'") j += command[j] === "\\" ? 2 : 1
      i = j
    } else if (c === "'") state = 1
    else if (c === '"') state = 2
    else if (c === "\\") i++
    else if ((c === ">" && command[i - 1] !== "<") || (c === "<" && command[i + 1] === ">")) {
      // `>`, `>>`, `>|`, `N>`, `<>` (read-write: it creates the file) and `>& FILE`.
      let j = i + 1
      if (c === "<") j++
      else if (command[j] === ">" || command[j] === "|") j++
      const dup = c === ">" && command[j] === "&"
      if (dup) j++
      while (command[j] === " " || command[j] === "\t") j++
      let k = j
      let q = ""
      let word = ""
      while (k < command.length) {
        const d = command[k]
        if (q) {
          if (d === q) q = ""
          else word += d
        } else if (d === "'" || d === '"') q = d
        else if (" \t\n;&|()".includes(d)) break
        else word += d
        k++
      }
      // `>&2`, `>&-`, `>&3-` duplicate, close or move a descriptor: no file.
      if (word && word !== "/dev/null" && !(dup && /^(?:\d+-?|-)$/.test(word))) out.push({ path: word, kind: "write", via: "redirect" })
      i = k - 1
    }
  }
  for (const toks of effectiveSegments(command)) {
    if (!toks.length) continue
    const base = toks[0].split("/").pop() as string
    const args = toks.slice(1)
    const operands = args.filter((a) => !a.startsWith("-") && a !== "--")
    if (base === "tee") {
      for (const a of operands) out.push({ path: a, kind: "write", via: "tee" })
    } else if (base === "sed" && args.some((a) => a === "-i" || /^-[a-zA-Z]*i/.test(a) || a.startsWith("--in-place"))) {
      // `sed -i -e EXPR file`, `sed -i 's/a/b/' file`: the files are the operands after the script.
      let script = args.some((a) => a === "-e" || a === "--expression" || a === "-f" || a === "--file")
      const files: string[] = []
      for (let k = 0; k < args.length; k++) {
        const a = args[k]
        if (a === "-e" || a === "--expression" || a === "-f" || a === "--file") {
          k++
          continue
        }
        if (a.startsWith("-")) continue
        if (!script) {
          script = true
          continue
        }
        files.push(a)
      }
      for (const f of files) out.push({ path: f, kind: "write", via: "sed -i" })
    } else if (base === "cp" || base === "mv" || base === "install" || base === "ln" || base === "rsync") {
      // `-t DIR` / `--target-directory=DIR` names the destination; every operand is then a source.
      let dir: string | undefined
      let ops = operands
      const ti = args.findIndex((a) => a === "-t" || a === "--target-directory")
      if (ti >= 0 && ti + 1 < args.length) {
        dir = args[ti + 1]
        ops = operands.filter((a) => a !== dir)
      } else {
        const eq = args.find((a) => a.startsWith("--target-directory="))
        if (eq) dir = eq.slice("--target-directory=".length)
      }
      const dest = dir ?? (ops.length >= 2 ? ops[ops.length - 1] : undefined)
      const sources = dir !== undefined ? ops : ops.length >= 2 ? ops.slice(0, -1) : base === "ln" ? ops : []
      const cluster = (re: RegExp) => args.some((a) => /^-[a-zA-Z]+$/.test(a) && re.test(a.slice(1)))
      // mv, ln and rsync can put a whole directory in place, and so can cp -r/-R/-a.
      const kind: TargetKind =
        base === "mv" || base === "ln" || base === "rsync" || args.includes("--recursive") || args.includes("--archive") || (base === "cp" && cluster(/[rRa]/))
          ? "tree"
          : "write"
      if (dest !== undefined) {
        const noTdir = base !== "rsync" && (args.includes("--no-target-directory") || cluster(/T/))
        const intoDir = dir !== undefined || (!noTdir && (sources.length > 1 || dest.endsWith("/") || DIR_WORDS.test(dest)))
        if (intoDir && sources.length) {
          // A source with a trailing slash has no basename: BSD cp and rsync fill the destination itself.
          for (const src of sources) out.push({ path: src.endsWith("/") ? dest : joinPath(dest, baseName(src)), kind, via: base })
        } else out.push({ path: dest, kind, via: base })
      }
      if (base === "mv") for (const a of sources) out.push({ path: a, kind: "move", via: "mv" })
      // A hard or symbolic link — ln, or cp -l/-s — makes its source reachable from the destination.
      const linking = base === "ln" || (base === "cp" && (args.includes("--link") || args.includes("--symbolic-link") || cluster(/[ls]/)))
      if (linking) {
        const symbolic = args.some((a) => a === "--symbolic" || a === "--symbolic-link" || (/^-[a-zA-Z]+$/.test(a) && a.includes("s")))
        for (const a of sources) out.push({ path: a, kind: "link", via: base, ...(symbolic && dest ? { linkAt: dest } : {}) })
      }
    } else if (base === "tar" || base === "bsdtar" || base === "gtar") {
      const first = args[0] ?? ""
      const bundle = first && !first.startsWith("-") && /^[A-Za-z]+$/.test(first) ? first : ""
      const mode = (re: RegExp, longs: readonly string[]) =>
        re.test(bundle) || args.some((a) => longs.includes(a.split("=")[0]) || (/^-[a-zA-Z]+$/.test(a) && re.test(a.slice(1))))
      if (mode(/x/, ["--extract", "--get"]) && !mode(/O/, ["--to-stdout"])) {
        // Extraction fills its -C directories, else the cwd.
        const dirs: string[] = []
        for (let k = 0; k < args.length; k++) {
          const a = args[k]
          if ((a === "-C" || a === "--directory") && k + 1 < args.length) dirs.push(args[k + 1])
          else if (a.startsWith("--directory=")) dirs.push(a.slice("--directory=".length))
          else if (/^-C./.test(a)) dirs.push(a.slice(2))
        }
        for (const d of dirs.length ? dirs : ["."]) out.push({ path: d, kind: "tree", via: "tar -x" })
        if (mode(/P/, ["--absolute-names"])) out.push({ path: "/", kind: "tree", via: "tar -xP" })
      } else if (mode(/[cruA]/, ["--create", "--append", "--update", "--catenate", "--concatenate", "--delete"])) {
        // The archive it writes: `-f FILE`, `--file=FILE`, a cluster ending in f, or `tar czf FILE`.
        for (let k = 0; k < args.length; k++) {
          const a = args[k]
          const next = args[k + 1]
          if ((a === "-f" || a === "--file" || /^-[a-zA-Z]*f$/.test(a) || (k === 0 && bundle.includes("f"))) && next !== undefined && next !== "-") {
            out.push({ path: next, kind: "write", via: "tar" })
          } else if (a.startsWith("--file=") && a !== "--file=-") out.push({ path: a.slice("--file=".length), kind: "write", via: "tar" })
        }
      }
    } else if (base === "unzip") {
      // -l/-t/-v/-z/-Z list or test, -p/-c print: nothing is extracted.
      if (!args.some((a) => /^-[a-zA-Z]+$/.test(a) && /[lptvzZc]/.test(a.slice(1)))) {
        let dest = "."
        for (let k = 0; k < args.length; k++) {
          if (args[k] === "-d" && k + 1 < args.length) dest = args[k + 1]
          else if (/^-d./.test(args[k])) dest = args[k].slice(2)
        }
        out.push({ path: dest, kind: "tree", via: "unzip" })
      }
    } else if (base === "rm") {
      for (const a of operands) out.push({ path: a, kind: "delete", via: "rm" })
    } else if (base === "truncate") {
      for (const a of operands) out.push({ path: a, kind: "write", via: "truncate" })
    }
  }
  return out
}

// ------------------------------------------ hooks/permission-guard.sh (ADR 004 D8) ---
//
// OpenCode runs no shell hook, so guard.ts runs the canonical permission guard itself:
// one source of truth for the action catalog, the conditions and the resolver, instead
// of a TypeScript port of the matcher. The functions here build and read its
// CODEX-dialect payload (`turn_id` set): deny only, a resolver host that reads no option
// store, every ask delivered as a deny (Codex's ask fails open, X1). guard.ts sends the
// guard's OPENCODE dialect instead: this payload without `turn_id`, plus "host":
// "opencode" (honoured only where the host would otherwise read as Claude Code). There
// the guard asks for an R2 call, which D8 accepts as advisory under `--auto` (O1c), and
// denies every R3/R4, never_auto and UNCLASSIFIED call; resolver host opencode, no
// option store, no host-attested channel (ADR 004 D3, D5). guard.ts keeps that ask
// (opencodeVerdict), hands everything else to pgVerdict below, and never sets allow.

/** The bundled GitHub MCP server's tool prefix in the guard's (Claude) vocabulary. */
export const PG_MCP_PREFIX = "mcp__plugin_tamirs-superpowers_github__"

/**
 * OpenCode names an MCP call's permission action `<server>_<tool>` (doc-cited; the
 * live name is unmeasured, ADR 004 item 13). The bundled server is `github` in
 * opencode.json, so `github_<tool>` is one of its tools, or null for anything else.
 */
export function githubMcpTool(action: string): string | null {
  const m = /^github_([A-Za-z0-9_]+)$/.exec(action)
  return m ? m[1] : null
}

export type PgCall =
  | { readonly kind: "shell"; readonly command: string; readonly cwd: string }
  | { readonly kind: "mcp"; readonly tool: string; readonly input: unknown; readonly cwd: string }

/** The PreToolUse payload for hooks/permission-guard.sh, in the Codex dialect; guard.ts derives its OpenCode dialect from it (see the section header). */
export function pgPayload(call: PgCall, sessionID: string): Record<string, unknown> {
  const base = { session_id: sessionID || "opencode", turn_id: "opencode", hook_event_name: "PreToolUse", cwd: call.cwd }
  if (call.kind === "shell") return { ...base, tool_name: "Bash", tool_input: { command: call.command } }
  const input = call.input && typeof call.input === "object" && !Array.isArray(call.input) ? call.input : {}
  return { ...base, tool_name: PG_MCP_PREFIX + call.tool, tool_input: input }
}

/**
 * The environment the guard runs in: the plugin's own, minus what would make it judge
 * as another host. GEMINI_SESSION_ID / GEMINI_PROJECT_DIR switch it to Gemini, whose
 * extension .env it would then read as a raise; CODEX_HOME is dropped too, since the
 * dialect is chosen by the payload, not by whatever the user's shell exported.
 */
export function pgEnv(env: Readonly<Record<string, string | undefined>>): Record<string, string> {
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(env)) {
    if (v === undefined) continue
    if (k === "GEMINI_SESSION_ID" || k === "GEMINI_PROJECT_DIR" || k === "GEMINI_CWD" || k === "CODEX_HOME") continue
    out[k] = v
  }
  return out
}

const PG_HEAD = "tamirs-superpowers permission guard"

/** The guard's own reason, reworded where it names the host it was told it runs on. */
export function opencodeReason(reason: string): string {
  return reason
    .replace(
      "codex cannot carry a hook ask (it would run the call unchecked)",
      "opencode cannot carry a plugin ask (`opencode --auto` approves it, measured O1)",
    )
    .replace("codex has no host-attested channel", "opencode has no host-attested channel")
}

/**
 * Read the guard's answer. `{}` is the only allow; a deny keeps its reason; an ask
 * (the Codex dialect never emits one; guard.ts keeps the OpenCode dialect's R2 ask
 * itself before it calls this) and anything unreadable are denies — the guard's
 * silence is never consent (ADR 004 D4: resolver or guard failure is a deny).
 */
export function pgVerdict(stdout: string): Decision {
  const text = stdout.trim()
  let obj: unknown
  try {
    obj = JSON.parse(text)
  } catch {
    return deny(`${PG_HEAD}: it printed no JSON verdict, so the call is denied (fail closed, ADR 004 D4).`)
  }
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    return deny(`${PG_HEAD}: its verdict is not a JSON object, so the call is denied (fail closed, ADR 004 D4).`)
  }
  const o = obj as Record<string, unknown>
  if (Object.keys(o).length === 0) return ALLOW
  const h = o.hookSpecificOutput as Record<string, unknown> | undefined
  const decision = h && typeof h === "object" ? h.permissionDecision : undefined
  const reason = h && typeof h.permissionDecisionReason === "string" ? opencodeReason(h.permissionDecisionReason) : ""
  if (decision === "allow") return ALLOW
  if (decision === "deny") return deny(reason || `${PG_HEAD} denied the call.`)
  if (decision === "ask") return deliverAsDeny(reason || `${PG_HEAD} asks before this call.`)
  return deny(`${PG_HEAD}: its verdict names no decision, so the call is denied (fail closed, ADR 004 D4).`)
}
