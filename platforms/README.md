# `platforms/` — adapter metadata

One thin `adapter.yaml` per supported target, in the shape of REFACTOR-SPEC §21.

These files are a **routing table, not a source of truth**. They answer "where do I
find this platform's manifest, install doc, and test?" in a fixed shape, so adding a
new provider is a directory plus one registry entry rather than a hunt through the
tree.

The authoritative capability statement — all 19 capability keys, per-capability
`status`, `validation`, `notes`, and `fallback` — lives in
[`core/capabilities/platforms.json`](../core/capabilities/platforms.json). Each
`adapter.yaml` carries only the four coarse keys named by the spec, and
`tests/test-platform-adapters.sh`-style checks assert they equal the registry, so
the summary here can never drift away from the registry it summarises.

## Field contract

| Field | Meaning |
|-------|---------|
| `id` | Short adapter id; matches the directory name. |
| `display_name` | Human-facing name. |
| `registry_key` | Key into `core/capabilities/platforms.json` → `platforms`. |
| `capabilities` | The four coarse keys from spec §21. `agents` maps to the registry's `subagents`; the other three are the same key. Values use the registry's status vocabulary (`native`, `adapter`, `emulated`, `partial`, `unsupported`, `unknown`). |
| `manifest` | Path to the platform's manifest/config, or `null` when the platform has none. |
| `install.type` | `marketplace`, `extension`, or `path`. |
| `install.doc` | Path to the user install guide. |
| `validation.command` | The command that proves this adapter loads. |

Adding a platform: create `platforms/<id>/adapter.yaml`, add the matching entry to
`core/capabilities/platforms.json`, and write `docs/user/install/<id>.md`. Do not
copy skills, rules, or agents.

## Platform facts that do NOT generalise

Every fact below was measured against a real CLI, and every one of them is the
*opposite* on a sibling platform. They are collected here because the failure mode is
specifically reading one adapter and assuming the next one behaves the same way.

| Behaviour | OpenCode | Gemini CLI |
|---|---|---|
| **Symlinks in a skill tree** | **Not followed, at any level** (verified 1.18.11). A symlinked `skills` dir, a symlinked domain dir, and a symlinked individual skill dir each discover **zero** skills. | **Followed.** Measured at the workspace tier (`.gemini/skills/<name> -> ../../skills/<domain>/<name>`) and through `gemini skills install --path`. |
| **Nested skill discovery** | **Recurses.** One `skills.paths` entry finds `SKILL.md` arbitrarily deep beneath it, so the canonical `skills/<domain>/<name>/` layout works unchanged. | **One level only.** `<root>/skills/<name>/SKILL.md` and nothing deeper, so the canonical two-level tree resolves to zero skills. |
| **Consequence for the adapter** | No skill adapter at all — `opencode.json` `skills.paths` points at the canonical tree in place. | A **generated flat mirror** at `.gemini/skills/`, built as a symlink farm precisely *because* symlinks are followed there. |

The practical rule: **the install mechanism is a measured property of the platform, not
a house style.** Neither adapter's approach is portable to the other, and copying one
into the other silently discovers zero skills — a failure that looks like nothing at
all rather than an error.

## The adapter pattern

Where a platform's format genuinely differs, both OpenCode and Gemini converged
independently on the same shape, and a third platform should follow it rather than
invent a fourth:

- a **bash-only generator**, no new runtime dependency
  (`scripts/build-opencode-agents.sh`, `scripts/build-gemini-extension.sh`);
- output **committed**, so installing from a clone needs no build step;
- a **generated-file header** in every output naming its source and its generator;
- a **`--check` mode** that regenerates into a temp dir and diffs, so CI fails on drift
  without touching the working tree;
- a platform contract test that runs `--check` and asserts nothing was hand-edited.

Translate only what the schema forces. A translation that merely *reformats* canonical
content is duplication wearing a build script, and the canonical file should be pointed
at instead.

### Translate meaning, not just syntax

The subtle failure is a translation that parses, loads, and is wrong. The canonical
agent `tools:` field is an **allowlist** — `tools: Read, Grep, Glob` means read-only.
Emitting only the granted tools into OpenCode's `tools` object satisfies the schema and
loads without error, but leaves every unlisted tool **enabled**: verified on 1.18.11,
that shape resolves to `bash: true, edit: true, write: true, task: true`, silently
handing a read-only reviewer write access. The generator therefore emits explicit
`deny` for every non-granted tool. When translating a permission or capability field,
check what the *absence* of an entry means on the target — it is rarely "denied".

### Re-base relative links for the new depth

The same failure, one step removed: there, meaning was lost in *translation*; here,
context is lost in *relocation*. Canonical `agents/<n>.md` sits one level below the
root, so its links read `](../core/policies/safety.md)`. The generated file sits at
`.opencode/agent/<n>.md` — two levels down — where that identical text points at
`.opencode/core/...`, which does not exist. Copying the body verbatim silently
invalidated all 24 relative links: the file still parsed, still loaded, and every link
in it was dead.

Both generators hit this independently, and both fix it the same way — one level deeper
means one more `../`:

```bash
tail -n "+$body_start" "$f" | sed 's|](\.\./|](../../|g'
```

Only `](../` is rewritten, so absolute paths, anchors and `http(s)` URLs are untouched.

**Assert it against the filesystem, not the syntax.** A frontmatter- or schema-only test
cannot see this class of bug by construction — the output is well-formed either way. Both
platform suites now resolve every `](../…)` in their generated files against real paths
and count the failures, and both were confirmed able to fail by reverting the fix on one
file. The general rule for any generated file: **whatever the source's location meant,
re-derive it for the destination** — relative links, but equally `$0`-relative script
paths, `CLAUDE_PLUGIN_ROOT`-style anchors, and include directives.
