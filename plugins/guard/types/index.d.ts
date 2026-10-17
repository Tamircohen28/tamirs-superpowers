// The guard plugin's $.state contract (Claude Code >= 2.1.287 "mods"). Named by
// .claude-plugin/plugin.json `types`; `claude plugin validate` holds every
// $.state key plugins/guard/hooks/register.tsx names to what is declared here.
//
// Every value here is session state the host keeps across a hot reload of the
// module. Nothing is persisted: the counts restart with the session, and
// `/guard` reads them back so the person can see what the guard has done.

/** The last destructive-command hold the guard raised, as `/guard` reports it. */
export type GuardHold = {
  /** The shell command the hold was raised on, cut to one line. */
  command: string
  /** Which vocabulary entry matched (`force push`, `rm -rf`, ...). */
  rule: string
  /**
   * How the hold ended: the person pressed Proceed or Cancel, dismissed the
   * dialog (read as Cancel), or nothing could draw it and the call went through.
   */
  answer: 'proceed' | 'cancel' | 'dismissed' | 'unasked'
  /** `$.clock.now()` milliseconds when the hold ended. */
  at: number
}

/** The last main-checkout write the guard refused, as `/guard` reports it. */
export type GuardDeniedWrite = {
  /** The path the tool named. */
  path: string
  /** The objective that was active. */
  objectiveId: string
  /** `$.clock.now()` milliseconds when it was refused. */
  at: number
}

declare module 'claude-code' {
  interface PluginState {
    'tamirs-superpowers-guard': {
      /** Destructive-command holds raised this session. */
      holds: number
      /** Of those, cancelled or dismissed (the call was refused). */
      cancelled: number
      lastHold: GuardHold | null
      /** Main-checkout writes refused this session. */
      deniedWrites: number
      lastDeniedWrite: GuardDeniedWrite | null
    }
  }
}
