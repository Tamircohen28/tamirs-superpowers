# Versioning and release

[Semantic Versioning](https://semver.org/). Full policy:
[`skills/repo/_contract/references/versioning-policy.md`](../../../skills/repo/_contract/references/versioning-policy.md).

---

## One canonical version

[`plugin-version.json`](../../../plugin-version.json) is the **single source of truth**.
Everything else is a declared *consumer*:

| Consumer | Kind | Required |
|---|---|:--:|
| `.claude-plugin/plugin.json` `.version` | JSON field | yes — Claude's update cache key |
| `.cursor-plugin/plugin.json` `.version` | JSON field | yes |
| `.codex-plugin/plugin.json` `.version` | JSON field | yes |
| `gemini-extension.json` `.version` | JSON field | yes (absent trees skip, not fail) |
| `README.md` version badge | text pattern | yes — the first version a visitor sees |
| `platform-targets.json` `.reviewed_by_skill` | JSON field | yes |
| `CHANGELOG.md` latest release heading | changelog heading | advisory |

```bash
bash scripts/check-version-truth.sh .          # verify
bash scripts/check-version-truth.sh . --sync   # repair every consumer
```

**Never hand-edit a consumer.** Edit `plugin-version.json`, then sync. If you must touch a
manifest by hand, use a targeted string replace — a `json.dump` or `jq` round-trip escapes
unicode (an em dash becomes `\u2014`) and reformats the file.

The changelog consumer is advisory on purpose: a manifest bump legitimately lands before its
release section is written, so a mismatch warns rather than fails, and `--sync` never
rewrites changelog history.

## Bump rules

| Bump | When |
|---|---|
| **PATCH** | Hook or skill bug fixes, docs-only changes, non-breaking config tweaks |
| **MINOR** | New skills, new optional hooks, a new platform target, backward-compatible features |
| **MAJOR** | Removed skills, breaking hook behavior, renamed slash commands, a changed skill contract |

**A version bump is required for delivery.** Claude Code and Codex treat the manifest
`version` as the update cache key, so shipped changes without a bump never reach installed
users — `/reload-plugins` does not fetch from GitHub. See
[`rules/dev/plugin-version-bump.md`](../../../rules/dev/plugin-version-bump.md).

## Release checklist

1. Move `[Unreleased]` entries in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`.
2. Set the version in `plugin-version.json`, then `bash scripts/check-version-truth.sh . --sync`.
3. `make validate`.
4. Open and merge the release PR.
5. The merge cuts the tag and release on its own: `release.yml` runs on every push to master
   that changes `plugin-version.json` and releases that version when it has no tag yet. A
   push whose version is already tagged stops quietly. To re-cut by hand (a version that is
   not on master yet, or a failed run):

   ```bash
   gh workflow run release.yml -f version=X.Y.Z
   ```

6. Publish through the `Tamircohen28/tamirs-marketplace` catalog if you distribute there.
7. The same workflow run then builds the Claude-only distribution and tags it `vX.Y.Z-claude`,
   moving the tag `claude` (the one Anthropic's plugin directory tracks) onto it. Nothing to
   do unless the `claude-dist` job fails; see
   [directory-distribution.md](directory-distribution.md).

**A merged manifest bump releases itself.** The push-to-master job *Manifest/tag version
alignment* still reports the minutes before the tag exists as a `::warning::`, because the
tag provably cannot exist at merge time. If that warning outlives the `Release` run, the run
failed: read it and re-dispatch. Before the push trigger existed, that warning was the only
reminder, and 5.6.8 through 6.1.2 sat untagged for three weeks behind a green check.

**Never move a manifest version backwards** past a cut release. That is real drift and fails
CI on every event.

## Update behavior per platform

| Situation | What users see |
|---|---|
| New commits, **same** version | Claude Code / Codex: "already at the latest version"; the cached copy is unchanged. Cursor with Auto Refresh: picks it up anyway |
| Version bumped + tag pushed | The update downloads a new cache directory; older Claude Code needs `/reload-plugins` |
| Gemini CLI | `gemini extensions install` re-resolves from the git URL |
| OpenCode | Path install — a `git pull` in the checkout is the update |
| Local development | `claude --plugin-dir .`, or a `command`-source marketplace entry with `mode: "link"` (Claude Code 2.1.229+), so the cache never enters the picture |

## Verify a tag matches the manifest

```bash
VER=$(jq -r .version plugin-version.json)
git tag -l "v${VER}" | grep -q . || echo "missing tag v${VER}"
```

## Dependabot

Major-version PRs are blocked in `.github/dependabot.yml`. Review minors by hand after
reading upstream changelogs.

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
