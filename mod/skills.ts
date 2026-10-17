// The bundled skills as the mod names them: the labels the opt-in classifier
// chooses between, the one-line descriptions the prompt box's typeahead shows,
// and which skills belong to the dev-workflow category (the ones that get the
// live objective appended when they expand). Static by design: nothing here
// reads a SKILL.md at run time. Each description line is derived from that
// skill's `description` frontmatter at authoring time and kept under 80
// characters; when a skill's description changes, change its line here too.
//
// The three internal companions (changelog-review, docs-review, mcp-pagination)
// are `user-invocable: false` and are left out of every table: they are not
// for the person to type.

/** The 26 public skills, one typeahead line each, in category order. */
export const SKILL_DESCRIPTIONS: Readonly<Record<string, string>> = {
  // dev-workflow
  'plan-dev': 'Turn a task, spec or review doc into a structured plan before any code',
  'start-dev': 'Implement a task from an issue number, free text or spec file',
  'orchestrate-dev': 'Run a multi-part objective as a task graph of worker agents',
  'worker-dev': 'Execute exactly one task of an objective orchestrate-dev planned',
  'deliver-dev': 'Turn an integrated objective into a delivery: the PR, the handoff',
  'pr-dev': 'Drive an open PR to merge: review comments, CI, final checks',
  'switch-dev': 'Hand off mid-task to another platform without losing context',
  decision: 'Pick between options an agent left waiting on your decision',
  // debugging
  'targeted-debug': 'Find the root cause behind a stack trace, panic or crash log',
  'diagnose-refusal': 'Find which layer refused, blocked or filtered a session',
  // repo
  'repo-scaffold': 'Create a new GitHub repository with production-ready infrastructure',
  'repo-standards': 'Audit or polish a repository to the house standards',
  'multi-agent-repo': 'Audit or set up a repository for multi-agent development',
  'github-policy': 'Bring branch protection, rulesets and required checks to policy',
  cleanup: 'Tidy a GitHub repo: prune merged branches, stale worktrees, clutter',
  // toolkit
  'skill-creator': 'Create or improve an Agent Skill, or fix one that does not trigger',
  'find-skill': 'Find a skill, plugin or agent for a task and compare candidates',
  retro: 'Turn this session into durable rules, hooks or memory',
  'session-report': 'What this session cost and where the tokens went',
  'notify-setup': 'Reach your phone when Claude Code needs you (Pushover)',
  'capture-config': 'Make a hand-edit to a global agent config permanent everywhere',
  'usage-capture': 'Record or inspect local LLM requests: usage logs, latency',
  // mcp
  'mcp-builder': 'Build an MCP server wrapping an API, database or service',
  // documentation
  'platform-sync': 'Catch up with what the targeted AI coding platforms changed',
  'dark-terminal-doc': 'A single-file HTML document in a dark terminal aesthetic',
  // creative
  'field-notebook-ui': 'A UI or artifact in the engineer\'s field-notebook look',
}

/** The public skill names, in table order. */
export const PUBLIC_SKILLS: readonly string[] = Object.keys(SKILL_DESCRIPTIONS)

/** The skills a prompt is classified against: the public names plus `none`. */
export const SKILL_LABELS = [...PUBLIC_SKILLS, 'none'] as const

/** The skills under skills/dev-workflow/: the ones that read orchestration state. */
export const DEV_WORKFLOW_SKILLS: ReadonlySet<string> = new Set([
  'plan-dev', 'start-dev', 'orchestrate-dev', 'worker-dev', 'deliver-dev', 'pr-dev', 'switch-dev', 'decision',
])

export function isDevWorkflowSkill(name: string): boolean {
  return DEV_WORKFLOW_SKILLS.has(name)
}

/** One row of the prompt box's typeahead, as `prompt.autocomplete` takes it. */
export type AutocompleteRow = { text: string; label: string; description: string }

/** Every row the mod can offer: the public skills, `/objective`, `/switch-dev handoff`. */
export const AUTOCOMPLETE_ROWS: readonly AutocompleteRow[] = [
  ...PUBLIC_SKILLS.map(name => ({ text: `/${name}`, label: `/${name}`, description: SKILL_DESCRIPTIONS[name] ?? '' })),
  { text: '/objective', label: '/objective', description: 'Show the active objective and its tasks (no model turn)' },
  { text: '/switch-dev handoff', label: '/switch-dev handoff', description: 'Write the handoff now — before a rate-limit window closes' },
]

/**
 * The rows whose `text` starts with `token` (case-insensitively), for a token
 * that opens with `/`; none for any other token.
 */
export function autocompleteRows(token: string): AutocompleteRow[] {
  if (!token.startsWith('/')) return []
  const prefix = token.toLowerCase()
  return AUTOCOMPLETE_ROWS.filter(row => row.text.toLowerCase().startsWith(prefix))
}

export function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length
}

/** The `skill-suggest.seen` store value: the labels already suggested, as a list. */
export function seenLabels(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []
}
