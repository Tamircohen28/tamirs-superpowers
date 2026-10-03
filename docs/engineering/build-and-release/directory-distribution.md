# The Claude-only distribution (Anthropic's plugin directory)

How this repository ships to [Anthropic's plugin directory](https://claude.ai/directory) without
becoming a Claude-only repository: a generated, tagged subset of `master`, rebuilt on every
release, that nobody edits by hand.

## Why a separate tree at all

The directory reads one plugin folder from one tracked branch or tag and runs its own checks on
every commit it picks up (its [pre-submission checklist](https://claude.com/docs/plugins/pre-submission-checklist)
is the public list). Several of those checks are about the *tree*, not the plugin:

| Directory rule | What this repository has on `master` | Result on `master` |
|---|---|---|
| 512 files or fewer | 1,100+ (tests, docs, evals, fixtures, four platform mirrors) | held for a reviewer |
| No symbolic links | 29 under `.gemini/skills/` | held, and flagged as an inventory gap |
| Only files the plugin needs | `.cursor/`, `.codex-plugin/`, `opencode.json`, `tests/`, … | the validator ran out of budget and stopped (`VALIDATION_INCOMPLETE`) |
| No `CLAUDE.md` at the plugin root | the contributor `CLAUDE.md` | warning |

None of that is wrong for a five-platform source repository, and this toolkit stays one. So the
directory gets the subset it needs, generated from `master`, and `master` stays the only place
anyone commits. The source fixes the directory asked for (credentials from `userConfig` only,
a mod that writes every `$` call at the call site and runs no subprocess, scoped
`allowed-tools`, listing URLs and a privacy policy) were made on `master` and ship to every
platform, because they are correct everywhere.

Leading multi-platform plugins (obra/superpowers, the universal marketplace template,
Anthropic's own official marketplace) all ship one repository that every platform reads in
place, with no lean build. They are small enough not to hit the file-count and symlink holds.
Generating a release artifact that a stable ref tracks is the standard answer elsewhere
(`gh-pages`, Homebrew bottles, a provider's release zip), and it is what this does.

## The two tags

| Tag | Moves? | What it is |
|---|---|---|
| `v<version>-claude` | never | The Claude-only tree of release `v<version>`. The permanent record of what was submitted. |
| `claude` | every release | The tag the directory tracks. `release.yml` moves it onto the newest `v<version>-claude` commit. |

The generated commit's parent is the previous generated commit, so `git log claude` reads as
the release history of the distribution and nothing else. No branch points at these commits:
git keeps a commit alive as long as a tag does, and the absence of a branch is the point.
There is nothing to check out and edit.

One version number everywhere: the generated `plugin.json` carries the same `version` as
`master`'s, bumped by the usual single-source flow ([`plugin-version-bump.md`](../../../rules/dev/plugin-version-bump.md)),
which satisfies the directory's "raise it with every release" rule without a second counter.

## What is in the tree

[`scripts/build-claude-dist.sh`](../../../scripts/build-claude-dist.sh) writes it:

1. **Roots, copied whole**: `.claude-plugin/plugin.json`, `.claude-plugin/icon.png`,
   `.mcp.json`, `hooks/`, `mod/`, `agents/`, `skills/`, `core/`, `rules/`, `output-styles/`,
   `templates/`, `config/`, `scripts/`, `platforms/claude/`, `LICENSE`, `SECURITY.md`,
   `PRIVACY.md`, `plugin-version.json`. Symbolic links are dereferenced.
2. **Pruned from those roots**: every `evals/`, `fixtures/` and `eval-viewer/` directory,
   the other platforms' build and setup scripts (`build-cursor-commands.sh`,
   `scripts/lib/setup-codex.sh`, …), the other platforms' install and comparison docs,
   `typecheck-mods.sh`, and the two distribution scripts themselves. `CHANGELOG.md`,
   `docs/changelog/` and `docs/engineering/` are left out on purpose: they are where this
   repository describes what it *used* to do, and the directory's scanner reads a sentence
   such as "no longer reads the token from the environment" as a credential read. For the
   same reason no shipped file names a credential variable or the gh token command; the
   check below fails on one.
3. **README**: `platforms/claude/directory/README.md` replaces the five-platform README. It is
   what the listing shows, so it names everything the plugin runs, sends and fetches.
4. **Link closure**: every relative Markdown link in a shipped file is followed; a target
   under `docs/user/` or inside the roots is pulled in, transitively, so no shipped doc points at
   a 404. A target outside the distribution (`CLAUDE.md`, `AGENTS.md`, another platform's
   manifest, a pruned fixture) is left out and listed. A target that exists nowhere is
   reported as already broken on `master`.

The result is around 380 files and no symlinks. Nothing in it is edited after the build.

Not in the tree, deliberately: `CLAUDE.md` and `AGENTS.md` (contributor instructions, never
loaded as plugin context), `tests/`, `evals/`, `docs/engineering/`, `.github/`, the
`.cursor*`/`.codex*`/`.gemini`/`.opencode`/`.agents` mirrors, `gemini-extension.json`,
`opencode.json`, the `Makefile`, and the three root version pins.

## The check that runs on every pull request

[`scripts/check-claude-dist.sh`](../../../scripts/check-claude-dist.sh) holds a built tree to
the directory's rules before anything is pushed: file count, symlinks, file sizes and types,
the manifest's listing fields and a square PNG icon, every credential-shaped `userConfig`
option marked `sensitive`, every MCP credential a `${user_config.KEY}` reference and every
local MCP server started by running a plugin file directly (no shell in front of it), no shipped script or mod
reading a credential from the environment or a file, no download-and-run and no package
launcher, hook commands in the plain `"${CLAUDE_PLUGIN_ROOT}"/path` form, a mod that hands
`$` to no helper and runs no process, no bare `Bash`/`Skill`/`Write`/`Edit`/`WebFetch`/`WebSearch`
in any `allowed-tools`, no credential name in shipped prose, a README that
resolves its links, and, where the `claude` CLI is present, `claude plugin validate --strict`
and `claude plugin test` on the built tree.

It is part of `make validate` (`make check-claude-dist` runs it alone) and the `claude-dist`
job of [`ci.yml`](../../../.github/workflows/ci.yml) runs it with the CLI installed. The
portal is the authority; this is the local stand-in, so a change that would block or hold
the listing fails on the pull request rather than at release. It mirrors the automated rules
only; the [Anthropic Software Directory Policy](https://support.claude.com/en/articles/13145358-anthropic-software-directory-policy)
still applies to what the plugin does.

## How a release flows

`release.yml` is unchanged up to the GitHub release; the `claude-dist` job runs after it:

1. Check out the commit `v<version>` names.
2. Build the tree and run the check against it; stop on any failure (the release tag already
   exists, so a failed distribution never blocks the marketplace release).
3. Confirm the built `plugin.json` carries `<version>`.
4. Write the tree as a git tree through a scratch index, commit it with the previous `claude`
   commit as parent (none on the first run), tag the commit `v<version>-claude`, and move the
   tag `claude` onto it with a forced tag push.
5. Write the step summary. The directory finds the new commit through the push webhook or
   its scheduled check; "Check for new commits" on the plugin's portal page runs it at once.

Rollback is one of: move `claude` back to the previous `v<version>-claude` tag, or type that
tag into the **Tracked branch or tag** field on the portal's Settings tab.

## Protecting the tags

A tag ruleset on `v*` and `claude` should allow only the release workflow to create or move
them. Two facts shape it:

- `claude` is moved with a forced tag push on every release, so the ruleset must allow
  updates and non-fast-forwards for the bypass actor, and the bypass actor must be able to
  push `v*-claude`.
- The default `GITHUB_TOKEN` cannot be named in a ruleset's bypass list. Set the repository
  secret `RELEASE_PUSH_TOKEN` to a fine-grained personal access token with **Contents:
  write** on this repository, and the `claude-dist` job pushes with it (the checkout step
  reads `secrets.RELEASE_PUSH_TOKEN || github.token`). Add the token's owner, or a GitHub App
  if one is used instead, to the ruleset's bypass list. Until the secret exists the default
  token pushes, which works as long as no ruleset guards the tags.

Ruleset settings, in the GitHub UI (Settings → Rules → Rulesets → New tag ruleset):

| Field | Value |
|---|---|
| Target tags | `v*` and `claude` (two include patterns) |
| Rules | Restrict creations, Restrict updates, Restrict deletions |
| Bypass list | the `RELEASE_PUSH_TOKEN` owner (or the App), mode *Always* |
| Enforcement | Active |

## Submitting and resubmitting

The portal submission's repository and folder cannot change after it is created, but the
tracked ref can. The first `v<version>-claude` tag exists only once a release has run, so:

1. Merge the pull request that carries the source changes.
2. Cut the release (`gh workflow run release.yml -f version=X.Y.Z`); wait for the
   `claude-dist` job to report the two tags.
3. On the plugin's page at <https://claude.ai/directory/manage>, Settings → **Tracked branch
   or tag** → `claude` → Save.
4. If the submission was rejected, **Resubmit for review** on the Review tab; otherwise
   **Check for new commits**.

Every later release needs only step 2: the moved tag is picked up on its own.

## Keeping the three in step

| Change on `master` | What follows |
|---|---|
| A new root-level file the plugin needs | add it to `ROOTS` in `build-claude-dist.sh`; the link closure does not reach files nothing links to |
| A new development-only subtree under a shipped root | add it to `PRUNE_DIRS`/`PRUNE_PATHS`, or the file count climbs toward 512 |
| A new `userConfig` option whose name contains `token`, `secret`, `key` or `password` | it must be `sensitive: true`, or the check fails |
| A new rule in the directory's checklist | mirror it in `check-claude-dist.sh`, so it fails here first |
| A new outbound call in shipped code | describe it in `PRIVACY.md` and `platforms/claude/directory/README.md` before the security scan asks |
