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
5. Cut the tag and release:

   ```bash
   gh workflow run release.yml -f version=X.Y.Z
   ```

6. Publish through the `Tamircohen28/tamirs-marketplace` catalog if you distribute there.

**Cut the release after merging a manifest bump.** The push-to-master job *Manifest/tag
version alignment* reports a pending release as a `::warning::` rather than failing — the tag
provably cannot exist at merge time, so failing there was a race, not a signal. Master stays
green; the warning is the reminder. Leaving it unreleased strands installed users on the
cached copy.

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
