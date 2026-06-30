# Troubleshooting

## Plugin fails to install — "dependency unresolved"

**Symptom:** `/plugin install tamirs-superpowers` fails with a message about an unresolved dependency.

**Cause:** One of the three third-party marketplaces hasn't been registered yet.

**Fix:** Register all three marketplaces, then retry:
```
/plugin marketplace add warpdotdev/claude-code-warp
/plugin marketplace add anthropics/knowledge-work-plugins
/plugin marketplace add obra/superpowers
/plugin install tamirs-superpowers
```

---

## Hook errors at session start — "jq: command not found"

**Symptom:** On session start, you see a hook error mentioning `jq`.

**Fix:** Install jq: `brew install jq`

The worktree hooks use `jq` to parse session state JSON.

---

## Edits are being blocked — "Repo edits must happen in a dedicated worktree"

**Symptom:** Every time you try to edit a file, Claude gets a hook denial.

**Cause:** The `enforce-worktree-edits.sh` hook is working as intended — it blocks edits to the main checkout and requires them to happen inside the session's worktree.

**Fix (option A):** Let Claude use the worktree. After your first prompt, a worktree is created at `~/.claude/worktrees/<repo>/<slug>/`. Use `EnterWorktree` to switch into it before editing.

**Fix (option B):** If you deliberately want to edit the main checkout (e.g. you're working on this plugin itself), temporarily disable the `enforce-worktree-edits` hook in `/plugin settings` or run from a directory that isn't a git repo.

---

## Skill not found — "/plan-dev: unknown command"

**Symptom:** A skill slash command returns "unknown command".

**Fix:**
1. Check the plugin is enabled: `/plugin list`
2. Reload: `/reload-plugins`
3. Confirm the SKILL.md file exists under `skills/dev-workflow/plan-dev/SKILL.md` in the install directory

---

## Statusline shows nothing

**Symptom:** The statusline area in Claude Code is blank.

**Cause:** `scripts/statusline.sh` requires `git` to be on the PATH in the shell Claude Code launches.

**Fix:** Ensure `git` is on your PATH. Test with: `which git` in your terminal.

---

## Cross-marketplace dependency fails after fresh machine setup

**Symptom:** After installing on a new machine, a plugin like `warp` or `superpowers` fails to resolve.

**Cause:** Claude Code only installs cross-marketplace dependencies if the target marketplace is already registered AND allowlisted in `marketplace.json`. If you skipped Step 1 of the Quick Start, the marketplaces aren't registered.

**Fix:** Re-run the three `/plugin marketplace add` commands from [Quick Start](quick-start.md), then `/plugin install tamirs-superpowers` again.

---

## Agent-kit: `npm run validate` fails after scaffold

**Symptom:** `validate.mjs` reports missing paths or `NO GENERATED MARKER`.

**Cause:** `dist/` was not built, or someone edited generated files by hand.

**Fix:**

```bash
npm run build
npm run validate
```

Only edit files under `canonical/`. See [Agent-kit repos](agent-kit.md).

---

## Agent-kit: `repo-standards polish` uses wrong contract profile

**Symptom:** Polish gate expects `app-gold` checks but you have an agent-kit repo (or vice versa).

**Cause:** Profile is auto-detected from `canonical/rules/` — if that directory is missing or misnamed, detection falls back to `app-gold`.

**Fix:** Ensure `canonical/rules/core.md` exists. Re-run review:

```text
/tamirs-superpowers:repo-standards review
```

Confirm the report lists `plugin-gold` as the contract profile.

---

## Agent-kit: marketplace install fails with relative path error

**Symptom:** `/plugin marketplace add` works but plugin entry with `source: "./plugins/..."` fails when marketplace was added via URL instead of git path.

**Cause:** Claude Code resolves relative `source` paths only when the marketplace is added from a git repo checkout.

**Fix:** Add marketplace via GitHub repo path:

```text
/plugin marketplace add TamirCohen28/my-agent-kit
```

See [Agent-kit repos — Install as a Claude Code plugin](agent-kit.md#install-as-a-claude-code-plugin).
