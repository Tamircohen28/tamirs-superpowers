---
alwaysApply: true
---

# Plugin version bump

Applies when you change **shipped plugin content**: `skills/`, `hooks/`, `agents/`, `core/`, plugin manifests, `scripts/`, `opencode.json`, or `.mcp.json`.

## The rule, in one line

**Edit one file — [`plugin-version.json`](../../plugin-version.json) — then run `scripts/check-version-truth.sh --sync`. Never hand-edit a consumer.**

```bash
# 1. Set the new version in the single canonical source
#    (targeted string replace on the "version" line — see below)
# 2. Propagate it everywhere
bash scripts/check-version-truth.sh --sync

# 3. Verify (this is what CI runs)
bash scripts/check-version-truth.sh
```

`plugin-version.json` lists every consumer of the version string — each platform manifest, the README badge, `platform-targets.json`, the changelog heading — with the field or pattern that carries it. The script is the only thing that should write those values. Adding a new target means adding a consumer entry, not remembering one more file.

Consumers that do not exist in the tree are skipped, not failed — a target's manifest may legitimately not exist yet.

### Editing the version safely

Use a **targeted string replace on the one version line**. Never a `jq`/`json.dump` full rewrite: a round-trip escapes non-ASCII (`—` becomes `—`) and reformats the whole file, producing a diff that hides the actual change.

```bash
python3 - <<'PY'
import pathlib
p = pathlib.Path("plugin-version.json"); s = p.read_text()
p.write_text(s.replace('"version": "2.0.1"', '"version": "2.1.0"', 1))
PY
```

## Why the version matters

Claude Code uses the manifest `version` string as the **cache key** for updates ([plugins reference — Version management](https://code.claude.com/docs/en/plugins-reference#version-management)):

- Pushing commits **without** bumping `version` does **not** deliver changes to installed users.
- `/plugin update` reports **"already at the latest version"** and keeps the cached copy.
- `/reload-plugins` reloads from the **local cache** only — it never fetches from GitHub.

Cursor, Codex, and Gemini CLI read their own manifests. `opencode.json` has **no** version field — OpenCode installs by path, so there is no cache to invalidate. Do not add one for symmetry; the asymmetry is real and recorded in `platform-targets.json`.

## Which bump

| Change type | Semver bump |
|-------------|-------------|
| New or removed skills, new hooks, backward-compatible features | **MINOR** |
| Bug fixes, docs-only in shipped paths, non-breaking hook tweaks | **PATCH** |
| Removed skills, breaking hook behavior, renamed slash commands | **MAJOR** |

Full policy: [`versioning.md`](../../docs/engineering/build-and-release/versioning.md).

## Never move a version backwards

A manifest version must never regress past a cut release. That is real drift, and it fails CI on every event — `--allow-pending-release` included. If a bad version shipped, go forward with a new patch. Never move a published tag.

## The same commit must carry what the bump falsified

`--sync` handles the version string. It does not write prose. In the same commit, update:

| Artifact | Why |
|----------|-----|
| `CHANGELOG.md` — promote `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` | Release notes are generated from it |
| Documented **skill counts**, wherever asserted | `make check-doc-claims` fails the build otherwise |
| `platform-targets.json` `last_reviewed` / per-target `validated_against` | These pin what was actually checked |
| `docs/user/install/<target>.md` | Anything a user copy-pastes |

Never record a `validated_against` you did not observe. Run the target's own `--version` on the machine and write how you got it into `verification_method`. A guessed floor converts "unknown" into a false promise.

## Adding or changing a supported target

A target is not supported until **all five** exist. `make validate` enforces 1–4:

1. A manifest or config for the target, registered as a consumer in `plugin-version.json`
2. `docs/user/install/<target>.md`, linked from `docs/user/install/README.md`
3. An entry in `platform-targets.json` → `supported_targets` **and** `targets.<key>`, with `validated_against`, `verified_on`, `verification_method`, `install_doc`, and any `capability_gaps`
4. Capability facts in [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json)
5. The target named in `README.md` and `AGENTS.md`

"Supports target X" requires test or validation evidence — a manifest file alone is not support.

Marketplace declarations are per-target and not interchangeable. Claude Code's `extraKnownMarketplaces` is a **record keyed by marketplace name** — an array is dropped silently, with no error and no warning. (Since Claude Code 2.1.232 the alias `additionalMarketplaces` is also accepted; identical shape, identical silent array drop — prefer `extraKnownMarketplaces` where older versions must read the file.) `make check-marketplace-schema` guards the shape in real settings files and scaffold templates.

## Release checklist

1. Bump `plugin-version.json`, run `scripts/check-version-truth.sh --sync`
2. Promote the `CHANGELOG.md` entry; update anything the bump falsified
3. `make validate`
4. Open a PR — **never** push a manifest bump directly to the default branch
5. After merge, cut the tag:

   ```bash
   gh workflow run release.yml -f version=X.Y.Z
   ```

   The push-to-default-branch job **Manifest/tag version alignment** emits a `::warning::` ("Release pending") rather than failing — the tag provably cannot exist at merge time, so failing there was a race, not a signal. The warning is the reminder; leaving it unreleased strands installed users on the cached copy.
6. **Verify the tag contains the change** before announcing it:

   ```bash
   git fetch --tags
   git diff "vX.Y.Z" "origin/$(bash skills/dev-workflow/_shared/scripts/default-branch.sh)" \
     -- skills/ hooks/ scripts/ agents/ core/                                  # expect empty
   git show "vX.Y.Z:plugin-version.json" | jq -r .version                     # expect X.Y.Z
   ```

   A tag can be cut from the wrong ref and still look right in the UI. A local install that "has" the feature proves nothing — the cache may have been hand-patched. Only the tag is evidence.
7. Tell users to refresh:

   ```text
   /plugin marketplace update tamirs-marketplace
   /plugin update tamirs-superpowers@tamirs-marketplace
   /reload-plugins
   ```

## Local development without a release

Point the cache at your working tree — **do not edit the cache in place**:

```bash
ls ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/
mv ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/X.Y.Z{,.bak}
ln -s /path/to/your/clone ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/X.Y.Z
```

Then `/reload-plugins`. Claude Code also supports `--plugin-dir` for running straight from a clone.

> **Never hand-edit files under `~/.claude/plugins/cache/`.** Two mechanisms destroy those edits without warning:
>
> - **`autoUpdate`** replaces the version directory wholesale, mid-session.
> - **Version-glob resolution.** Several consumers resolve their own path with `ls .../tamirs-superpowers/*/... | sort -rV | head -1` — *newest version wins*. When an auto-update installs `1.10.0` beside your patched `1.9.0`, the glob moves to the unpatched copy and the change appears "not to have worked". The symptom looks like a bug in the feature; the cause is resolution order.
>
> A symlink survives both. Prune stale cache versions after confirming an update installed.
>
> **Claude Code before 2.1.247** had a third hazard for this exact symlink: the Bash tool's sandbox could delete a dotfile-managed symlink under `~/.claude/` (this cache symlink is precisely that shape) if a later command repointed it — e.g. re-running the `ln -s` above to point at a different clone — to a target outside the sandbox's writable area. Fixed in 2.1.247; on older versions, repointing this symlink from inside a Claude Code session was itself the risk, not just the two mechanisms above.

## CI enforcement

`make validate` and the CI job `Manifest/tag version alignment` fail when:

- any consumer disagrees with `plugin-version.json` (`check-version-truth.sh`);
- a documented skill count or supported target does not match the tree (`check-doc-claims`);
- `extraKnownMarketplaces` appears as an array anywhere (`check-marketplace-schema`);
- a version moves **backwards** relative to the latest `vX.Y.Z` tag.

Pull requests run `--manifests-only` (tag comparison skipped); pushes to the default branch run `--allow-pending-release`. Neither fails a legitimate bump PR — if alignment fails, the cause is real drift, not the pending release.
