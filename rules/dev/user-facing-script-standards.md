---
alwaysApply: false
globs:
  - "scripts/**/*"
  - "skills/**/scripts/**/*"
  - "hooks/**/*"
---

# User-Facing Script Standards

Applies to scripts intended for direct human or agent invocation, regardless of which provider authors them:

- `scripts/` at the repo root (`install.sh`, `update.sh`, `uninstall.sh`, `doctor.sh`, and similar)
- skill helper scripts under `skills/**/scripts/`

Internal-only helpers are not required to expose the same UX surface, but the portability, non-blocking, and dependency rules below apply to **every** script in this repo.

**Never** place a user-facing `.sh` file at the repository root — use `scripts/` and wire it through a `Makefile` target.

---

## 1. CLI contract

Every user-facing script must:

1. Support `--help` / `-h` — print usage (script name, arguments, flags, at least one concrete example) and exit `0`.
2. Support `--verbose` / `-v` — enable detailed logging.
3. Carry a top-of-file usage block documenting purpose, arguments, flags, and an example.
4. Fail fast on an unknown flag, with a clear error and a usage hint.
5. Keep help text truthful when flags or positionals change.

Scripts that mutate state must offer explicit preview/safety behavior where relevant (`--dry-run`), and must never delete or overwrite user work without it being the stated purpose of the invocation.

## 2. Shell baseline

- `#!/usr/bin/env bash` and `set -euo pipefail`.
- Shellcheck-clean at `-S warning` (`make lint`).
- Quote expansions; prefer `printf` over `echo` for anything with data in it.

## 3. Portability: macOS and Linux

Both are first-class. CI runs Linux; the primary development machine is macOS. A script that works on only one is broken.

The differences that actually bite:

| Do not | Do |
|--------|----|
| `sed -i 's/a/b/' f` | `sed -i.bak 's/a/b/' f && rm -f f.bak`, or rewrite via `python3` |
| `sed '/pat/i text'` (GNU-only insert) | `python3` for line insertion |
| `readlink -f` | `cd "$(dirname "$0")" && pwd`, or `python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))'` |
| `date -d`, `date --iso-8601` | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `grep -P` | `grep -E` |
| `stat -c` | `wc -c` / `find -size`, or branch on `uname` |
| `mktemp -p DIR` | `mktemp -d` (and `trap 'rm -rf "$tmp"' EXIT`) |
| `realpath`, `timeout`, `sha256sum` assumed present | Detect, or use the BSD spelling (`shasum -a 256`) |

Assume **bash 3.2** unless the script checks `BASH_VERSINFO` — macOS ships 3.2. No `declare -A`, no `${var^^}`, no `mapfile`, without a guard.

### Windows / PowerShell — explicitly unsupported

**This repo's scripts do not support Windows PowerShell or `cmd.exe`, and will not.** Windows users run these scripts under **WSL2** or **Git Bash**, both of which provide the bash + coreutils baseline above.

This is a declaration, not a gap to be quietly worked around:

- Do not add PowerShell variants of existing scripts.
- Do not degrade a script's POSIX behavior to accommodate Windows path separators or CRLF.
- Do state the WSL2/Git Bash requirement in any user-facing install doc that references a script.
- A script that happens to work natively on Windows is fine; it is not tested there, and no fix is owed if it breaks.

## 4. Non-interactive by default

Every script must complete a normal run with **no TTY, no prompts, and no stdin**. Agents, hooks, CI, and cloud sessions all invoke scripts this way.

- Never prompt unconditionally. If a confirmation is genuinely needed, gate it behind a TTY check and provide a non-interactive path:

  ```bash
  if [[ -t 0 ]]; then read -r -p "Delete N branches? [y/N] " ans; else ans="${ASSUME_YES:-n}"; fi
  ```

- Never require an editor, pager, or browser. Set `GIT_PAGER=cat` / `--no-pager` where git might page.
- Never start an OAuth or browser login flow on the user's behalf. Report the missing auth and stop.

### Stdin must never block

A script that reads stdin **must not** hang when stdin is an idle terminal or an inherited descriptor. This is a real, observed failure: `scripts/statusline.sh` does `input=$(cat)` and blocks forever when invoked without piped input, which is why the smoke test must run as `smoke.sh </dev/null`.

Required pattern for any script that consumes stdin:

```bash
# Read stdin only when it is not an idle TTY, and never wait indefinitely.
input=""
if [[ ! -t 0 ]]; then
  input=$(timeout 2 cat 2>/dev/null || true)   # where `timeout` exists
fi
```

If `timeout` may be absent (macOS without coreutils), guard on `command -v timeout` and fall back to the `[[ -t 0 ]]` check alone. A script that gets empty stdin must degrade to a sane default and exit `0`, not error.

Callers must still redirect (`</dev/null`) when invoking scripts from a hook or a test harness — belt and braces, since the caller is the only party who knows the descriptor is inherited.

## 5. Dependency detection

Classify every external tool a script uses:

| Tier | Meaning | Behavior when missing |
|------|---------|-----------------------|
| **Required runtime** | `git`, POSIX shell, the provider's own CLI | Fail fast with a clear message naming the tool |
| **Optional feature** | `gh`, `jq`, `node`, `python3` for a non-core path, Pushover credentials | Degrade explicitly: skip the feature and say so, or fall back. Never silently pretend |
| **Contributor/validation** | `shellcheck`, PyYAML, platform CLIs | Only in `make` targets and CI, never in a user-facing runtime path |

```bash
require() { command -v "$1" >/dev/null 2>&1 || { printf 'error: %s is required (%s)\n' "$1" "$2" >&2; exit 1; }; }
have()    { command -v "$1" >/dev/null 2>&1; }

require git "install from https://git-scm.com"
have jq || printf 'note: jq not found — falling back to grep parsing\n' >&2
```

Never let an optional dependency silently downgrade correctness. `shellcheck` absence currently makes `make lint` skip shell coverage rather than fail — acceptable for a contributor target, never acceptable for a user-facing one.

`scripts/doctor.sh` is the single place that reports detected platform, plugin version, git, shell, `jq`, `gh`, other optional dependencies, available capabilities, missing optional features, and install health.

## 6. Machine-readable output where orchestration consumes it

Any script an agent or another script parses must offer a stable, machine-readable mode — `--json` (preferred) or `--porcelain` with a documented, versioned line format.

- Machine output goes to **stdout**, alone. Human progress, warnings, and diagnostics go to **stderr**.
- Exit codes are part of the contract: `0` success, `1` failure, and any other code documented in the usage block.
- JSON must parse (`jq empty`) even on the failure path — emit `{"ok": false, "error": "..."}` rather than half a document.
- Human-readable output may change freely. Machine output is an interface: changing a key or a code is a breaking change and needs a version bump ([`plugin-version-bump.md`](plugin-version-bump.md)).

`skills/dev-workflow/_shared/scripts/resolve-worktree.sh` is the model: it prints one JSON object on stdout that a caller consumes with `jq`, and nothing else.

```bash
worktree=$(skills/dev-workflow/_shared/scripts/resolve-worktree.sh ... | jq -r .worktree_path)
```

## 7. Hook scripts

Hooks (`hooks/*.sh`, wired via `hooks/hooks.json`) are loaded by Claude Code and Codex; Cursor does not wire them. Unexpected stdout from a hook subprocess interferes with hook response parsing.

**Never use `echo` in a hook script.**

| Instead of | Use |
|------------|-----|
| `echo "message" >> "$TIMELINE"` | `pm_timeline_append "$TIMELINE" "$TS" "$tool_name" "$agent"` |
| `echo "event" \| pm_trace_append` | `pm_emit_event ...` |
| `\|\| echo "fallback"` in `$()` | `\|\| printf '%s\n' "fallback"` |
| `echo "value" > "$FILE"` | `printf '%s\n' "$value" > "$FILE"` |

Hooks must also finish fast and never block on stdin — the rules in §4 apply with no exceptions.

## 8. Documentation synchronization

When a script's interface changes, update the examples in `README.md`, the relevant `docs/user/` pages, and `docs/engineering/` where location or purpose moved.
