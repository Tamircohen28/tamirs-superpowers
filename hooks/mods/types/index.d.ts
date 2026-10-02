// The mod's $.state contract (Claude Code >= 2.1.287 "mods"). Named by
// .claude-plugin/plugin.json `types`; `claude plugin validate` holds every
// $.state key hooks/mods/register.tsx names to what is declared here.
//
// Every value here is session state the host keeps across a hot reload of the
// module. Nothing is persisted: the objective is re-read from disk, the usage
// figures are re-pushed by `session.measure`, the warning re-derives.

/** One task of the active objective, as the pane draws it. */
export type ModsObjectiveTask = {
  id: string
  title: string
  /** core/workflow/task-schema.json `status`. */
  status: string
  role?: string
  branch?: string
  /** core/workflow/handoff-schema.json `status`, when a handoff file exists. */
  handoff?: string
}

/** The objective `.dev-files/objectives/<id>/objective.json` describes. */
export type ModsObjective = {
  id: string
  title: string
  /** core/workflow/objective-schema.json `status`. */
  status: string
  tasks: ModsObjectiveTask[]
  /** When the pane last re-read it, `$.clock.now()` milliseconds. */
  readAt: number
}

/** `$.session.usage()` figures as `session.measure` last pushed them. */
export type ModsUsage = {
  contextPercent?: number
  rateLimits: { kind: string; percentUsed: number; resetsAt?: string }[]
  costUsd?: number
}

/** The rate-limit window that crossed the warning threshold, while it has. */
export type ModsLimitWarning = {
  kind: string
  percentUsed: number
  resetsAt?: string
}

declare module 'claude-code' {
  interface PluginState {
    'tamirs-superpowers': {
      objective: ModsObjective | null
      usage: ModsUsage | null
      limitWarning: ModsLimitWarning | null
      /** The person pressed Dismiss on the warning band at this percentage. */
      dismissedAtPercent: number
      /** Subagents spawned and not yet completed, for the spinner suffix. */
      workers: number
    }
  }
}
