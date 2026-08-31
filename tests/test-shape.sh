#!/usr/bin/env bash
# test-shape.sh — repo-shape conditionality.
#
# WHAT THIS SUITE IS FOR
#   This plugin generates, sets up and validates OTHER people's repositories, and
#   a long list of its scripts assumed the shape of THIS one: a Makefile, CI, a
#   plugin manifest, a JS or Python stack, shadcn UI. On a repo shaped otherwise
#   they did not fail — they went quiet, and a caller read the silence as
#   success. Every case below therefore comes in a matched pair:
#
#     - the NEGATIVE case  — the shape that used to be assumed away
#     - the POSITIVE control — the shape it was assumed to be
#
#   The control is not decoration. Four checks in the session that produced this
#   file passed while testing nothing, because a negative assertion against a
#   script that silently no-ops looks exactly like a negative assertion against a
#   script that correctly declined. A pair distinguishes them.
#
# Hermetic: temp fixtures only, no network, no gh, no writes outside mktemp.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require git jq python3

TMP="$(harness_tmpdir)"

# Keep every fixture out of reach of the developer's real git config / gh auth.
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset GH_TOKEN GITHUB_TOKEN 2>/dev/null || true

# new_repo <name> — a hermetic git repo under $TMP, path echoed.
new_repo() {
  local d="$TMP/$1"
  harness_new_repo "$d"
  printf '%s' "$d"
}

# rc <cmd...> — run, discard output, echo the exit status.
rc() { "$@" >/dev/null 2>&1; echo $?; }

GATES="$ROOT/skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh"
DOCTOR="$ROOT/scripts/doctor.sh"
GUARD="$ROOT/hooks/guard-sensitive-files.sh"
DONE="$ROOT/hooks/check-done.sh"
DETECT="$ROOT/skills/dev-workflow/start-dev/scripts/detect-stack.sh"
SCAFFOLD_DETECT="$ROOT/skills/repo/repo-scaffold/scripts/detect-stack.sh"
SHAPE="$ROOT/skills/repo/_contract/scripts/detect-contract-profile.sh"
WT_LIB="$ROOT/hooks/lib/worktree-common.sh"
SCORE="$ROOT/skills/repo/_contract/scripts/score-standards-gaps.sh"

# ===========================================================================
section "pre-PR gates: a repo with no gate FAILS instead of passing silently"
# ===========================================================================

nogate="$(new_repo gates-none)"
out="$(bash "$GATES" "$nogate" 2>&1)"; status=$?
judge "no Makefile / no scripts -> non-zero exit (was: exit 0)" 1 "$status"
judge "  ... and names the cause"        yes "$(has "$out" "no pre-PR gate could be detected")"
judge "  ... and lists what it probed"   yes "$(has "$out" "probed, and found nothing runnable")"
judge "  ... and forbids claiming a pass" yes "$(has "$out" "NO GATE RAN")"

# POSITIVE CONTROL 1 — a Makefile target is found and run.
mkgate="$(new_repo gates-make)"
printf 'validate:\n\t@echo VALIDATED\n' > "$mkgate/Makefile"
out="$(bash "$GATES" "$mkgate" 2>&1)"; status=$?
judge "Makefile 'validate' target -> exit 0" 0 "$status"
judge "  ... names the detected runner"   yes "$(has "$out" "Makefile target 'validate'")"
judge "  ... actually ran it"             yes "$(has "$out" "VALIDATED")"

# POSITIVE CONTROL 2 — the gate's failure is propagated, not swallowed.
mkfail="$(new_repo gates-make-fail)"
printf 'validate:\n\t@exit 3\n' > "$mkfail/Makefile"
judge "a failing Makefile gate -> non-zero exit" 1 "$(rc bash "$GATES" "$mkfail")"

# POSITIVE CONTROL 3 — a package.json script is a gate too.
pkgg="$(new_repo gates-pkg)"
printf '{"name":"x","scripts":{"validate":"echo hi"}}\n' > "$pkgg/package.json"
out="$(bash "$GATES" "$pkgg" 2>&1)"
judge "package.json 'validate' script is detected" yes "$(has "$out" "package.json script 'validate'")"

# A dependency NAMED "test" must not be mistaken for a script.
pkgdep="$(new_repo gates-pkg-dep)"
printf '{"name":"x","devDependencies":{"validate":"1.0.0"}}\n' > "$pkgdep/package.json"
judge "a dependency named 'validate' is not a gate" 1 "$(rc bash "$GATES" "$pkgdep")"

# The one explicit opt-out, and only that spelling.
judge "SUPERPOWERS_PRE_PR_GATES=none exits 0" 0 \
  "$(SUPERPOWERS_PRE_PR_GATES=none rc bash "$GATES" "$nogate")"
out="$(SUPERPOWERS_PRE_PR_GATES=none bash "$GATES" "$nogate" 2>&1)"
judge "  ... but still says no gate ran" yes "$(has "$out" "NO GATE RAN")"
judge "a typo'd opt-out is rejected, not honoured" 1 \
  "$(SUPERPOWERS_PRE_PR_GATES=skip rc bash "$GATES" "$nogate")"

# Go and Rust repos have a gate even with no Makefile.
gorepo="$(new_repo gates-go)"; printf 'module x\n\ngo 1.22\n' > "$gorepo/go.mod"
out="$(bash "$GATES" "$gorepo" 2>&1)"
judge "a Go module is recognised as a gate" yes "$(has "$out" "detected go.mod")"

# ===========================================================================
section "doctor: an ordinary repo is healthy, a broken plugin repo is not"
# ===========================================================================

plain="$(new_repo doctor-plain)"
printf '# hi\n' > "$plain/README.md"
out="$(bash "$DOCTOR" "$plain" </dev/null 2>&1)"; status=$?
judge "non-plugin repo -> exit 0 (was: exit 1)" 0 "$status"
judge "  ... no 'no canonical version' BROKEN" no "$(has "$out" "BROKEN")"
judge "  ... and says why the check does not apply" yes "$(has "$out" "not a plugin repo")"

# POSITIVE CONTROL — a repo that DOES ship a plugin and has no canonical
# version is still broken. Without this, "doctor never fails" would pass.
badplugin="$(new_repo doctor-plugin-broken)"
mkdir -p "$badplugin/.claude-plugin"
printf '{"name":"x","version":"1.0.0"}\n' > "$badplugin/.claude-plugin/plugin.json"
out="$(bash "$DOCTOR" "$badplugin" </dev/null 2>&1)"; status=$?
judge "plugin repo without plugin-version.json -> exit 1" 1 "$status"
judge "  ... and names the real problem" yes "$(has "$out" "plugin repo without plugin-version.json")"

# POSITIVE CONTROL — this repo, which IS a plugin repo, still passes.
judge "the plugin's own repo still passes doctor" 0 "$(rc bash "$DOCTOR" "$ROOT")"

# ===========================================================================
section "sensitive-file guard: shadcn is detected, not assumed"
# ===========================================================================

guard_decision() { # guard_decision <file-path> -> allow|deny
  local d
  d="$(jq -n --arg f "$1" '{tool_name:"Edit", tool_input:{file_path:$f}}' \
       | bash "$GUARD" 2>/dev/null \
       | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  printf '%s' "${d:-allow}"
}

plainui="$(new_repo guard-plain)"
mkdir -p "$plainui/src/components/ui"
printf 'export const Button = () => null\n' > "$plainui/src/components/ui/button.tsx"
judge "hand-written src/components/ui/ is ALLOWED (no shadcn)" allow \
  "$(guard_decision "$plainui/src/components/ui/button.tsx")"

# POSITIVE CONTROL — the same path in a real shadcn project is still blocked.
shad="$(new_repo guard-shadcn)"
mkdir -p "$shad/src/components/ui"
printf '{"style":"default"}\n' > "$shad/components.json"
printf 'export const Button = () => null\n' > "$shad/src/components/ui/button.tsx"
judge "src/components/ui/ in a shadcn project is DENIED" deny \
  "$(guard_decision "$shad/src/components/ui/button.tsx")"

# dist/: build output is what git ignores, not what a path is called.
distr="$(new_repo guard-dist)"
mkdir -p "$distr/dist" "$distr/build"
printf 'dist/\n' > "$distr/.gitignore"
printf 'x\n' > "$distr/dist/bundle.js"
printf 'x\n' > "$distr/build/keep.js"
judge "gitignored dist/ is DENIED (genuine build output)" deny "$(guard_decision "$distr/dist/bundle.js")"
judge "tracked build/ is ALLOWED (not ignored -> not build output)" allow \
  "$(guard_decision "$distr/build/keep.js")"

# Unconditional rules must stay unconditional.
judge "a lockfile is still DENIED"  deny  "$(guard_decision "$plainui/yarn.lock")"
judge "a workflow is still DENIED"  deny  "$(guard_decision "$plainui/.github/workflows/ci.yml")"
judge "ordinary source is ALLOWED"  allow "$(guard_decision "$plainui/src/app.ts")"

# ===========================================================================
section "definition-of-done: CI evidence is demanded only where CI exists"
# ===========================================================================

done_msg() { # done_msg <repo>
  ( cd "$1" && SUPERPOWERS_VALIDATION_TIER=3 bash "$DONE" </dev/null 2>&1 >/dev/null )
}

noci="$(new_repo done-noci)"
printf 'echo hi\n' > "$noci/script.sh"
out="$(done_msg "$noci")"
judge "no CI -> the reminder still fires"        yes "$(has "$out" "tier 3, delivery")"
judge "no CI -> does not demand 'gh pr checks'"  no  "$(has "$out" "gh pr checks")"
judge "no CI -> says so, and forbids inventing one" yes "$(has "$out" "NO CI configuration")"

# POSITIVE CONTROL — with CI present the demand comes back.
withci="$(new_repo done-ci)"
printf 'echo hi\n' > "$withci/script.sh"
mkdir -p "$withci/.github/workflows"
printf 'name: CI\non: [push]\n' > "$withci/.github/workflows/ci.yml"
out="$(done_msg "$withci")"
judge "GitHub Actions present -> cites gh pr checks" yes "$(has "$out" "gh pr checks")"

# POSITIVE CONTROL 2 — a non-GitHub CI is named, and gh is NOT prescribed.
glci="$(new_repo done-gitlab)"
printf 'echo hi\n' > "$glci/script.sh"
printf 'stages: [test]\n' > "$glci/.gitlab-ci.yml"
out="$(done_msg "$glci")"
judge "GitLab CI is named"                    yes "$(has "$out" "GitLab CI")"
judge "  ... and gh commands are not offered" no  "$(has "$out" "gh pr checks")"

# ===========================================================================
section "stack detection: an unknown stack is stated, never silent"
# ===========================================================================

unk="$(new_repo stack-unknown)"
printf 'hello\n' > "$unk/README.md"
out="$(bash "$DETECT" "$unk" 2>/dev/null)"
judge "unknown stack -> emits an explicit NO-VALIDATION line" yes "$(has "$out" "# NO-VALIDATION:")"
judge "  ... which is a shell comment (safe to execute)" yes "$(has "$out" "#")"
err="$(bash "$DETECT" "$unk" 2>&1 >/dev/null)"
judge "  ... and warns on stderr too" yes "$(has "$err" "NO VALIDATION COMMANDS")"

# POSITIVE CONTROL — the languages that used to emit nothing now emit commands.
for pair in "go:go.mod:go test ./..." \
            "rust:Cargo.toml:cargo test" \
            "java:pom.xml:verify" \
            "elixir:mix.exs:mix test" \
            "dotnet:app.csproj:dotnet test" \
            "swift:Package.swift:swift test" \
            "bazel:MODULE.bazel:bazel test //..."; do
  name="${pair%%:*}"; rest="${pair#*:}"; f="${rest%%:*}"; want="${rest#*:}"
  d="$(new_repo "stack-$name")"
  printf 'x\n' > "$d/$f"
  out="$(bash "$DETECT" "$d" 2>/dev/null)"
  judge "$name emits '$want'" yes "$(has "$out" "$want")"
  judge "  ... and no NO-VALIDATION line" no "$(has "$out" "NO-VALIDATION")"
done

# Package manager comes from what the repo declares, not from a lockfile alone.
pmrepo="$(new_repo stack-pm)"
printf '{"name":"x","packageManager":"pnpm@9.0.0","scripts":{"test":"echo t"}}\n' > "$pmrepo/package.json"
printf '{}\n' > "$pmrepo/package-lock.json"
out="$(bash "$DETECT" "$pmrepo" 2>/dev/null)"
judge "packageManager field beats the lockfile" "pnpm test" "$(printf '%s' "$out" | head -1)"
# NB: a substring test cannot express "not npm" here — "pnpm test" contains
# "npm test". The whole line is compared instead.

bunrepo="$(new_repo stack-bun)"
printf '{"name":"x","scripts":{"test":"echo t"}}\n' > "$bunrepo/package.json"
: > "$bunrepo/bun.lockb"
judge "bun.lockb selects bun" yes "$(has "$(bash "$DETECT" "$bunrepo" 2>/dev/null)" "bun test")"

# pytest is emitted only where pytest is configured.
pynone="$(new_repo stack-py-plain)"
printf '[project]\nname = "x"\n' > "$pynone/pyproject.toml"
judge "pyproject without pytest -> no bare 'pytest' command" no \
  "$(has "$(bash "$DETECT" "$pynone" 2>/dev/null)" "pytest")"
pyyes="$(new_repo stack-py-pytest)"
printf '[project]\nname = "x"\n[tool.pytest.ini_options]\n' > "$pyyes/pyproject.toml"
judge "pyproject WITH [tool.pytest] -> pytest is emitted" yes \
  "$(has "$(bash "$DETECT" "$pyyes" 2>/dev/null)" "pytest")"

# ===========================================================================
section "scaffold stack detection: files beat prose, and prose says it guessed"
# ===========================================================================

srcgo="$(new_repo scaffold-src-go)"
printf 'module x\n' > "$srcgo/go.mod"
j="$(bash "$SCAFFOLD_DETECT" "a react frontend dashboard" "$srcgo" --json 2>/dev/null)"
judge "a Go source dir is not called 'node' because the prose says react" go \
  "$(printf '%s' "$j" | jq -r .language)"
judge "  ... and the answer is marked as file-derived" files \
  "$(printf '%s' "$j" | jq -r .source)"

# POSITIVE CONTROL — with no files, prose still answers, and is labelled a guess.
j="$(bash "$SCAFFOLD_DETECT" "a react frontend dashboard" "" --json 2>/dev/null)"
judge "prose-only still resolves a stack" node "$(printf '%s' "$j" | jq -r .stack)"
judge "  ... and is marked as description-derived" description "$(printf '%s' "$j" | jq -r .source)"
err="$(bash "$SCAFFOLD_DETECT" "a react frontend dashboard" "" 2>&1 >/dev/null)"
judge "  ... and says out loud that it GUESSED" yes "$(has "$err" "GUESSED")"

# Nothing at all is an explicit unknown, not a silent 'generic'.
err="$(bash "$SCAFFOLD_DETECT" "" "" 2>&1 >/dev/null)"
judge "no signal at all -> UNKNOWN STACK is stated" yes "$(has "$err" "UNKNOWN STACK")"

# plugin-hint is now reachable from files, where it used to need the word "plugin".
plugsrc="$(new_repo scaffold-src-plugin)"
mkdir -p "$plugsrc/.claude-plugin"
printf '{"name":"p","version":"1.0.0"}\n' > "$plugsrc/.claude-plugin/plugin.json"
judge "a plugin manifest yields plugin-hint from files" plugin-hint \
  "$(bash "$SCAFFOLD_DETECT" "some tool" "$plugsrc" 2>/dev/null)"

# ===========================================================================
section "worktree dependency install: every ecosystem, or a logged reason"
# ===========================================================================

# The installers themselves (go, cargo, npm...) are not assumed present; what is
# asserted is that the function RECOGNISES the ecosystem and records what it did
# or could not do. A silent log was the original defect.
wt_log() { # wt_log <fixture-dir>
  ( set +u
    # shellcheck source=hooks/lib/worktree-common.sh
    source "$WT_LIB" >/dev/null 2>&1
    SUPERPOWERS_WORKTREE_INSTALL_DEPS=1 run_worktree_post_setup "$1" >/dev/null 2>&1
    cat "$1/session-files/worktree-setup.log" 2>/dev/null )
}

# Stub every installer so the assertion measures THIS code, not which toolchains
# happen to be installed on the machine running the suite. A skip here would be
# the same kind of silence the suite exists to catch.
STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
for b in go cargo bundle composer npm deno uv poetry pipenv; do
  printf '#!/bin/sh\nexit 0\n' > "$STUBBIN/$b"
  chmod +x "$STUBBIN/$b"
done

for pair in "go:go.mod:go mod download" \
            "rust:Cargo.toml:cargo fetch" \
            "ruby:Gemfile:bundle install" \
            "php:composer.json:composer install" \
            "uv:uv.lock:uv sync" \
            "deno:deno.json:deno install"; do
  name="${pair%%:*}"; rest="${pair#*:}"; f="${rest%%:*}"; want="${rest#*:}"
  d="$TMP/wt-$name"; mkdir -p "$d"; printf 'x\n' > "$d/$f"
  log="$(PATH="$STUBBIN:$PATH" wt_log "$d")"
  judge "$name worktree logs '$want'" yes "$(has "$log" "$want")"
done

# package.json with NO lockfile used to install nothing at all, silently.
d="$TMP/wt-node-nolock"; mkdir -p "$d"; printf '{"name":"x"}\n' > "$d/package.json"
judge "package.json without a lockfile falls back to npm install" yes \
  "$(has "$(PATH="$STUBBIN:$PATH" wt_log "$d")" "npm install (no lockfile present)")"

# uv / poetry-less Python must SAY it installed nothing, not go quiet.
d="$TMP/wt-py-bare"; mkdir -p "$d"; printf '[project]\nname="x"\n' > "$d/pyproject.toml"
log="$(PATH="/usr/bin:/bin" wt_log "$d")"
judge "a Python repo with no env manager logs why deps were skipped" yes \
  "$(has "$log" "deps NOT installed")"

# POSITIVE CONTROL — a repo with nothing to install says exactly that.
d="$TMP/wt-empty"; mkdir -p "$d"; printf 'hi\n' > "$d/README.md"
judge "a repo with no manifest logs 'nothing installed'" yes \
  "$(has "$(wt_log "$d")" "nothing installed")"

# Lockfile digest: absent lockfiles must not produce a digest that can "match".
( # shellcheck source=hooks/lib/worktree-common.sh
  source "$WT_LIB" >/dev/null 2>&1
  d="$TMP/hash-none"; mkdir -p "$d"
  h_none="$(worktree_lockfile_hash "$d")"
  d2="$TMP/hash-go"; mkdir -p "$d2"; printf 'x h1:abc\n' > "$d2/go.sum"
  h_go="$(worktree_lockfile_hash "$d2")"
  printf '%s\n%s\n' "${h_none:-EMPTY}" "${h_go:-EMPTY}" ) > "$TMP/hashes"
judge "no lockfile -> empty digest (so 'unchanged' can never be claimed)" EMPTY \
  "$(sed -n 1p "$TMP/hashes")"
judge "go.sum -> a real digest (positive control)" no \
  "$(has "$(sed -n 2p "$TMP/hashes")" "EMPTY")"

# ===========================================================================
section "shape detector: the facts the rest of the plugin now reads"
# ===========================================================================

judge "this repo is detected as a plugin repo" true \
  "$(bash "$SHAPE" "$ROOT" --json | jq -r .is_plugin_repo)"
judge "  ... and its contract profile is unchanged" app-gold "$(bash "$SHAPE" "$ROOT")"
judge "the plugin-gold fixture still detects as plugin-gold" plugin-gold \
  "$(bash "$SHAPE" "$ROOT/skills/repo/_contract/fixtures/scaffold-plugin-gold")"
judge "a plain repo is not a plugin repo" false \
  "$(bash "$SHAPE" "$plain" --json | jq -r .is_plugin_repo)"
judge "a plain repo reports no CI" none "$(bash "$SHAPE" "$plain" --json | jq -r .ci_system)"
judge "a repo with .gitlab-ci.yml reports gitlab_ci" gitlab_ci \
  "$(bash "$SHAPE" "$glci" --json | jq -r .ci_system)"
judge "shadcn is reported from components.json" true \
  "$(bash "$SHAPE" "$shad" --json | jq -r .shadcn)"

# ===========================================================================
section "standards contract: every _when_* condition, both directions"
# ===========================================================================

# inv <overrides-json> — a minimal standards inventory with everything ABSENT,
# then the given overrides merged in. Scoring it tells us exactly which checks
# fire for that shape.
inv() {
  jq -nc --argjson o "$1" '
  {
    readme: {exists:true, has_badges:false, has_prerequisites:true, has_quick_start:true,
             has_license_line:true, has_banner:true, has_author_badge:true,
             has_version_badge:false, has_ai_targets:true, has_multi_install:true},
    makefile: {install:false, update:false, uninstall:false},
    versioning: {root_changelog:false, versioning_doc:false, changelog_unreleased:true,
                 agents_references_versioning:true, manifest_versions_match:true,
                 manifest_count:0, manifest_version_tag_match:true, release_tags_exist:false},
    ai_platforms: {count:1},
    docs: {readme:false, changelog:false, contributing:false, user_dir:false, engineering_dir:false},
    github: {ci_workflow:false, secret_scan_job:false, pr_template:true, dependabot:true},
    root_files: {license:false, codeowners:true, gitignore:true, claude_md:true, agents_md:true},
    branch_governance: {readable:false, protection_enabled:false, requires_ci_check:false,
                        allow_auto_merge:false, delete_branch_on_merge:false,
                        rulesets:{}, actions:{checked:false, violations:0}},
    hygiene: {misplaced_top_level_docs:0, ticket_named_outside_engineering:0, empty_dirs:0,
              self_hosted_ci:false, root_shell_scripts:0}
  } * $o'
}

# fires <id> <overrides-json> -> yes|no
fires() {
  local ids
  ids="$(inv "$2" | bash "$SCORE" app-gold | jq -r '.gaps[].id')"
  case "$ids" in *"$1"*) echo yes ;; *) echo no ;; esac
}

EXPERIMENT='{}'
PUBLISHED='{"makefile":{"install":true}}'
RELEASED='{"versioning":{"release_tags_exist":true}}'
WITHCI='{"github":{"ci_workflow":true}}'

section "  docs tree (S2-*) — _when_published"
judge "unpublished experiment is NOT told to build a docs tree" no "$(fires S2-01 "$EXPERIMENT")"
judge "  positive control: a published repo IS"                 yes "$(fires S2-01 "$PUBLISHED")"

section "  LICENSE (S5-01) — _when_published"
judge "unpublished repo is not required to carry a LICENSE" no  "$(fires S5-01 "$EXPERIMENT")"
judge "  positive control: a published repo is"             yes "$(fires S5-01 "$PUBLISHED")"

section "  root CHANGELOG (S5-03) / versioning doc (S10-02) — _when_release_model"
judge "no release model -> no root CHANGELOG demanded" no  "$(fires S5-03 "$EXPERIMENT")"
judge "  positive control: tagged repo is"             yes "$(fires S5-03 "$RELEASED")"
judge "no release model -> no versioning.md demanded"  no  "$(fires S10-02 "$EXPERIMENT")"
judge "  positive control: tagged repo is"             yes "$(fires S10-02 "$RELEASED")"

section "  version badge (S1-07) — _when_release_model"
judge "no release model -> no version badge demanded" no  "$(fires S1-07 "$EXPERIMENT")"
judge "  positive control: tagged repo is"            yes "$(fires S1-07 "$RELEASED")"

section "  Makefile lifecycle (S1-08) — _when_published"
judge "unpublished repo needs no install/update/uninstall" no "$(fires S1-08 "$EXPERIMENT")"
judge "  positive control: a released repo does"          yes "$(fires S1-08 "$RELEASED")"

section "  CI/license badges (S1-02) — _when_ci"
judge "no CI and no LICENSE -> no badge gap" no  "$(fires S1-02 "$EXPERIMENT")"
judge "  positive control: with CI, badges are demanded" yes "$(fires S1-02 "$WITHCI")"

section "  secret-scan job (S3-02) — _when_ci"
judge "no CI -> no 'CI missing secret-scan job'" no "$(fires S3-02 "$EXPERIMENT")"
judge "  positive control: with CI, it fires"    yes "$(fires S3-02 "$WITHCI")"
judge "  and 'No .github/workflows CI' still fires (S3-01 is unconditional)" yes \
  "$(fires S3-01 "$EXPERIMENT")"

section "  S4-04 (auto-merge) is retired, S4-05 is not"
GOV='{"branch_governance":{"readable":true,"protection_enabled":true,"requires_ci_check":true,"allow_auto_merge":false,"delete_branch_on_merge":false,"rulesets":{"safety_active":true,"pr_ci_active":true,"strict_required_status_checks":false,"requires_conversation_resolution":true,"requires_linear_history":true,"blocks_force_push":true,"blocks_deletion":true},"actions":{"checked":false,"violations":0}}}'
judge "auto-merge off is no longer scored as a defect" no  "$(fires S4-04 "$GOV")"
judge "  positive control: delete_branch_on_merge still is" yes "$(fires S4-05 "$GOV")"

section "  unconditional checks stay unconditional"
judge "AGENTS.md missing still fires" yes "$(fires S5-04 '{"root_files":{"agents_md":false}}')"
judge "  positive control: present -> silent" no "$(fires S5-04 '{}')"

# ===========================================================================
section "merge policy: the method, the branch, and the JSON reader"
# ===========================================================================

MERGEPOL="$ROOT/skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh"

# A scripted `gh`. GH_SQUASH/GH_MERGE/GH_REBASE set what the repository allows;
# GH_HEAD_PROTECTED decides whether the PR's head branch is governed. Nothing
# here reaches the network.
GHBIN="$TMP/ghbin"; mkdir -p "$GHBIN"
cat > "$GHBIN/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"--json squashMergeAllowed"*)
    printf '{"squashMergeAllowed":%s,"mergeCommitAllowed":%s,"rebaseMergeAllowed":%s,"deleteBranchOnMerge":true,"viewerPermission":"ADMIN"}\n' \
      "${GH_SQUASH:-true}" "${GH_MERGE:-true}" "${GH_REBASE:-true}" ;;
  "api repos/{owner}/{repo}")            printf '{"allow_auto_merge":true}\n' ;;
  *"--json nameWithOwner"*)              printf '%s\n' "${GH_REPO:-acme/widget}" ;;
  *"--json baseRefName"*)                printf 'main\n' ;;
  *"--json headRefName"*)                printf 'release/1.x\n' ;;
  *"branches/release/1.x/protection"*)   [ "${GH_HEAD_PROTECTED:-false}" = true ] && { printf '{"required_status_checks":{"strict":false,"contexts":[]}}\n'; exit 0; }; exit 1 ;;
  *protection*)                          [ -n "${GH_BASE_CLASSIC:-}" ] && { printf '%s\n' "$GH_BASE_CLASSIC"; exit 0; }; exit 1 ;;
  # Rulesets: the effective-rules endpoint. Default [] = "answered, no rules",
  # which is what a purely classic (or unprotected) repository returns.
  *"repos/demo/pinned/rules/branches/main"*)
    # Only reachable when --repo actually pinned GH_REPO: the path is built from
    # OWNER_REPO. A distinctive context makes the assertion non-vacuous.
    printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"pinned-ok"}]}}]\n'; exit 0 ;;
  *"rules/branches/release/1.x"*)        [ "${GH_RULES_ERROR:-false}" = true ] && exit 1; printf '%s\n' "${GH_HEAD_RULES:-[]}" ; exit 0 ;;
  *"rules/branches/"*)                   [ "${GH_RULES_ERROR:-false}" = true ] && exit 1; printf '%s\n' "${GH_BASE_RULES:-[]}" ; exit 0 ;;
  *graphql*)                             printf '{"data":{"repository":{"mergeQueue":null}}}\n' ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$GHBIN/gh"

mp() { # mp <env assignments...> -> the resolved JSON
  ( cd "$TMP" && env PATH="$GHBIN:$PATH" "$@" bash "$MERGEPOL" 42 2>/dev/null )
}

judge "squash allowed -> squash" squash \
  "$(mp GH_SQUASH=true | jq -r .merge_method)"
judge "squash forbidden, merge allowed -> merge" merge \
  "$(mp GH_SQUASH=false GH_MERGE=true | jq -r .merge_method)"
judge "only rebase allowed -> rebase (was: never chosen)" rebase \
  "$(mp GH_SQUASH=false GH_MERGE=false GH_REBASE=true | jq -r .merge_method)"
judge "  ... and the choice names its reason" yes \
  "$(has "$(mp GH_SQUASH=false GH_MERGE=false GH_REBASE=true | jq -r .merge_method_source)" "allows rebase")"
judge "no method allowed -> warned, not silently squashed" yes \
  "$(has "$(mp GH_SQUASH=false GH_MERGE=false GH_REBASE=false | jq -r '.warnings[0] // ""')" "none of squash/merge/rebase")"

judge "unprotected head branch -> delete_branch true" true \
  "$(mp GH_HEAD_PROTECTED=false | jq -r .delete_branch)"
judge "protected head branch -> delete_branch false (was: always true)" false \
  "$(mp GH_HEAD_PROTECTED=true | jq -r .delete_branch)"
judge "  ... and says which branch and why" yes \
  "$(has "$(mp GH_HEAD_PROTECTED=true | jq -r .delete_branch_source)" "release/1.x is protected")"

# --- rulesets: protection can live in a second, independent system ----------
# The classic endpoint 404s on a ruleset-governed branch, and reading only it
# reported "no protection" for a branch requiring nine checks and a PR.
RS='[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"shellcheck"},{"context":"Secret scan"}]}},{"type":"pull_request","parameters":{"required_approving_review_count":0}}]'

judge "ruleset-only base: required checks are found (was: [])" 2 \
  "$(mp GH_BASE_RULES="$RS" | jq -r '.required_checks | length')"
judge "  ... and the source names rulesets, not classic" rulesets \
  "$(mp GH_BASE_RULES="$RS" | jq -r .protection_source)"
judge "  ... strict comes from the ruleset policy" false \
  "$(mp GH_BASE_RULES="$RS" | jq -r .strict_branch_update)"
judge "  ... a pull_request rule with 0 approvals is NOT requires_review" false \
  "$(mp GH_BASE_RULES="$RS" | jq -r .requires_review)"

RS_APPROVE='[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]'
judge "ruleset requiring 1 approval -> requires_review true" true \
  "$(mp GH_BASE_RULES="$RS_APPROVE" | jq -r .requires_review)"

RS_STRICT='[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}]'
judge "ruleset strict policy -> strict_branch_update true" true \
  "$(mp GH_BASE_RULES="$RS_STRICT" | jq -r .strict_branch_update)"

# Classic and rulesets are a UNION, not alternatives.
CLASSIC='{"required_status_checks":{"strict":false,"contexts":["legacy-ci"]}}'
judge "classic + rulesets: contexts are unioned" 3 \
  "$(mp GH_BASE_CLASSIC="$CLASSIC" GH_BASE_RULES="$RS" | jq -r '.required_checks | length')"
judge "  ... and the source names both" classic+rulesets \
  "$(mp GH_BASE_CLASSIC="$CLASSIC" GH_BASE_RULES="$RS" | jq -r .protection_source)"
judge "classic-only repo is not mislabelled as using rulesets" classic \
  "$(mp GH_BASE_CLASSIC="$CLASSIC" | jq -r .protection_source)"

# jq's `//` treats FALSE as empty, so `.strict // "null"` turned an explicit
# strict=false into null and pr-dev took the loose path by accident.
judge "classic strict=false is reported false, not null" false \
  "$(mp GH_BASE_CLASSIC="$CLASSIC" | jq -r .strict_branch_update)"

# delete_branch is destructive and unrecoverable from the PR, so an unreadable
# head must keep the branch rather than guess.
judge "ruleset-protected head -> delete_branch false (was: true)" false \
  "$(mp GH_HEAD_RULES='[{"type":"deletion"}]' | jq -r .delete_branch)"
judge "unreadable head protection -> keeps the branch (fails closed)" false \
  "$(mp GH_RULES_ERROR=true | jq -r .delete_branch)"
judge "  ... and says the read failed rather than implying it is protected" yes \
  "$(has "$(mp GH_RULES_ERROR=true | jq -r .delete_branch_source)" "could not be read")"

# --- --repo: the target must be statable, not inferred from the cwd ---------
# Every gh call resolves the repository from the CURRENT DIRECTORY, so the same
# PR number in a sibling checkout is a real, plausible-looking, unrelated PR.
# That is a wrong ANSWER, not an error, which is why it went unnoticed.
mp_repo() { ( cd "$TMP" && env PATH="$GHBIN:$PATH" bash "$MERGEPOL" --repo demo/pinned 42 2>/dev/null ) ; }

# NON-VACUOUS BY CONSTRUCTION: the fake gh serves "pinned-ok" only from the path
# repos/demo/pinned/..., which is built from the resolved OWNER_REPO. If --repo
# stopped exporting GH_REPO, the cwd fallback (acme/widget) would be used and
# this context could not appear. An assertion that merely echoed the flag back
# would pass with the feature deleted.
judge "--repo reaches the API path, not just the shell" yes \
  "$(has "$(mp_repo | jq -r '.required_checks | join(",")')" "pinned-ok")"

judge "  ... and without --repo that context is NOT reachable (control)" no \
  "$(has "$(mp | jq -r '.required_checks | tostring')" "pinned-ok")"

judge "--repo=<slug> form is accepted" 42 \
  "$( ( cd "$TMP" && env PATH="$GHBIN:$PATH" bash "$MERGEPOL" --repo=demo/pinned 42 2>/dev/null ) | jq -r .pr )"

judge "a slug with no slash is rejected, not silently ignored" 2 \
  "$( ( cd "$TMP" && env PATH="$GHBIN:$PATH" bash "$MERGEPOL" --repo notaslug 42 >/dev/null 2>&1 ); printf '%s' "$?")"

judge "  ... and the PR number is still parsed after the flag" 42 \
  "$( ( cd "$TMP" && env PATH="$GHBIN:$PATH" bash "$MERGEPOL" --repo demo/pinned 42 2>/dev/null ) | jq -r .pr )"

judge "no --repo still works (cwd inference preserved)" 42 \
  "$(mp | jq -r .pr)"

# The policy file must be honoured through the python3 fallback, not discarded.
mkdir -p "$TMP/.dev-files"
printf '{"delivery":{"auto_merge":false}}\n' > "$TMP/.dev-files/policy.json"
judge "policy.json auto_merge=false is honoured (jq present)" skip \
  "$(mp GH_SQUASH=true | jq -r .auto_merge)"

# Same file, with jq removed from PATH: python3 must read it. A PATH built from
# symlinks is the only way to remove one tool without removing the rest.
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for b in bash sh env git cat sed cut head tail tr awk grep dirname basename mktemp printf python3; do
  src="$(command -v "$b" 2>/dev/null)" && ln -sf "$src" "$NOJQ/$b" 2>/dev/null
done
ln -sf "$GHBIN/gh" "$NOJQ/gh"
out="$( cd "$TMP" && env -i HOME="$HOME" PATH="$NOJQ" bash "$MERGEPOL" 42 2>/dev/null )"
judge "without jq, policy.json is still read (python3 fallback)" yes \
  "$(has "$out" '"auto_merge": "skip"')"
judge "  ... and the source names the file, not a default" yes \
  "$(has "$out" 'policy.json delivery.auto_merge=false')"

# POSITIVE CONTROL — with NEITHER reader, the output says the files were unread
# instead of presenting the default as a decision.
NONE="$TMP/noreader"; mkdir -p "$NONE"
for b in bash sh env git cat sed cut head tail tr awk grep dirname basename mktemp; do
  src="$(command -v "$b" 2>/dev/null)" && ln -sf "$src" "$NONE/$b" 2>/dev/null
done
out="$( cd "$TMP" && env -i HOME="$HOME" PATH="$NONE" bash "$MERGEPOL" 42 2>/dev/null )"
judge "with no JSON reader at all, the loss is reported" yes \
  "$(has "$out" "were NOT read")"

harness_summary
