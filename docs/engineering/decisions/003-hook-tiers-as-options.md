# ADR 003 — Hook tiers as plugin options, not separate plugins

**Status:** Accepted — 2026-10-17

## Context

[`hooks-classification.md`](../architecture/hooks-classification.md) sorts every hook into
a category and concludes that two groups should not be on for everyone: the
**notification** hooks (desktop and phone notifications, the VPN exit check, the
usage-capture collector start), which tell a human something and change nothing about the
work, and the **contributor** hooks (the `/reload-plugins` reminder, `report.md` link
validation, the hand-written `SKILL.md` guard), which are useful to someone working *on*
this plugin and noise to someone merely using it. Until V5 all of them shipped wholesale
to every install, because the hook manifest is one file and a hook is either in it or not.

The V5 plan proposed fixing that by **splitting the plugin into three**: `core`, `notify`
and `contrib`, each with its own manifest, each installable on its own. On review the split
costs more than it saves:

- **Cross-plugin file dependencies.** Every hook sources `hooks/lib/hook-output.sh`, and
  several share `lib/worktree-common.sh`, `lib/platform-tools.sh` and `lib/write-targets.py`.
  A plugin cannot reach into another plugin's install directory, so each split plugin would
  carry its own copy of the shared libraries, and the three copies would drift.
- **The 36-copy duplication problem.** The repository already mirrors its manifests and
  rules across six surfaces on five platforms. Three plugins multiply every manifest,
  marketplace entry, version pin, install doc, platform adapter and CI check by three,
  turning the existing cross-platform sync burden into one three times larger before a
  single hook changes.
- **Directory re-review.** The plugin is listed in Anthropic's plugin directory, which
  reviews a plugin as a whole. Three plugins are three listings, three reviews, three
  privacy policies and three sets of the scanner's rules to hold, for a change whose only
  user-visible effect is "fewer hooks fire by default".

Meanwhile Claude Code already has a mechanism for per-install switches: the manifest's
`userConfig` block, whose every option is exported to each hook process as
`CLAUDE_PLUGIN_OPTION_<NAME>`. The plugin uses it for its three credentials and two mod
options.

## Decision

Implement the two tiers as **two non-sensitive boolean `userConfig` options** in
`.claude-plugin/plugin.json`:

| Option | Default | Gates |
|---|---|---|
| `notification_hooks` | `true` | `hooks/notify.sh`, `scripts/notify-pushover.sh`, `hooks/ensure-exit.sh`, `hooks/usage-capture-ensure.sh` |
| `contributor_hooks` | `false` | `hooks/plugin-reload-reminder.sh`, `hooks/validate-report-links.sh`, `hooks/skill-creator-guard.sh` |

`hooks/lib/hook-output.sh` gains `hook_tier_enabled <tier>` (reads the variable, accepts
`true/false`, `1/0`, `yes/no`, `on/off` case-insensitively, applies the default when unset)
and `hook_tier_gate <tier> [silent|allow|suppress]`, which each gated hook calls as the
first thing after reading stdin. When the tier is off the gate emits the no-op the hook's
event and host dialect need — nothing for a PostToolUse, SessionStart, UserPromptSubmit or
Notification hook; `hook_allow`'s platform-correct JSON for a PreToolUse guard, because
Cursor fail-closes on empty stdout — and exits 0. When the tier is on, the hook runs exactly
as before, including its own existing opt-ins (`TAMIRS_USAGE_CAPTURE`, `CLAUDE_EXIT_*`,
the Pushover credentials).

Core-safety-invariant, worktree-lifecycle and user-facing convenience hooks are never
gated. The hook manifests (`hooks/hooks.json`, `platforms/cursor/hooks.json`) are
unchanged: the gate lives in the hook, not in the wiring.

## Consequences

**Easier:**

- **No migration for installed users.** The plugin stays one plugin with one manifest and
  one marketplace entry. An existing install picks the new defaults up on the next version
  bump: notifications keep working, the three contributor hooks go quiet. Nobody
  reinstalls, re-adds a marketplace, or re-enters a credential.
- **Codex and Cursor get the defaults for free.** Neither host has `userConfig`, so neither
  exports the variable, and `hook_tier_enabled` falls back to the manifest default. The
  generated `platforms/codex/hooks.json` the Codex CLI loads (the same scripts) and the same guard Cursor's bundle wires behave
  as a Claude Code install with untouched options would. A contributor on either host can
  still export the variable by hand.
- **One review, one privacy policy, one set of shared libraries.** Nothing is duplicated,
  the directory listing is unchanged in shape, and `hooks/lib/` stays the single copy.
- **Switchable from `/config` and the shell.** `claude plugin configure tamirs-superpowers`
  sets both options; `/config` shows them as rows beside the mod options.

**Harder:**

- **The gate is a convention, not a structural guarantee.** A new hook in either tier must
  remember to call `hook_tier_gate`. `tests/test-hook-tiers.sh` holds the current set exactly
  (the seven hooks are the only callers) so an unlisted addition fails the suite, but it
  cannot know that a new hook *should* have been gated — that stays a review item against
  `hooks-classification.md`.
- **Off is "exit early", not "not installed".** A gated-off hook still starts a bash
  process per event and sources `hook-output.sh` before exiting. The cost is a few
  milliseconds per event and was judged acceptable against the split; a host-side
  mechanism for declaring a hook conditional on an option would remove it.
- **The option names are now an interface.** `CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS` and
  `CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS` are read by shipped hooks and documented for
  Codex/Cursor contributors to set by hand; renaming an option is a breaking change.

**A future split stays possible.** The tier is already the unit a split would cut along:
each gated hook names its tier in one line, and the manifest names the same tier in one
option. If the host ever grows a cross-plugin dependency mechanism or the directory
accepts a bundle, moving a tier into its own plugin is a matter of moving the files and
deleting the gate calls — nothing in this decision has to be undone first.
