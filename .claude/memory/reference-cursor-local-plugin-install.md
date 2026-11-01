---
name: reference-cursor-local-plugin-install
description: Cursor 3.27 local plugins must be a real copy under ~/.cursor/plugins/local (symlinks are rejected); the marketplace import stays pinned to an old commit
metadata:
  type: reference
---

Desktop 3.27.22 logs `loadUserLocalPlugin <name> rejected: symlink target ... is outside ~/.cursor/plugins/local` and loads nothing, so install with `git archive HEAD | tar -x -C ~/.cursor/plugins/local/<name>`, then restart Cursor. The proof is in `~/Library/Application Support/Cursor/logs/<newest>/window1/exthost/anysphere.cursor-agent-host/Cursor Plugins.log` (`... loaded in N ms`, `failures=0`).

The marketplace-imported copy is pinned to the commit the import recorded (here `c9399aa`, plugin 2.0.1) and keeps loading beside the local one until the Dashboard marketplace is refreshed; it needs a Cursor login, so it is the user's step.

`cursor-agent -p --plugin-dir <checkout> --trust --workspace <dir>` is the headless route. Prove a hook ran by diffing a run with and without the plugin and reading the file on disk: the user's global `~/.claude` hooks are imported by the CLI and produce near-identical block messages, so a block alone proves nothing. The per-version release notes are at cursor.com/docs/release-notes/ide; cursor.com/changelog is date-only. Related: [[feedback-verify-mechanism-claims]].
