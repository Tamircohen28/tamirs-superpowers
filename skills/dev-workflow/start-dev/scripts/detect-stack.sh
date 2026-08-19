#!/usr/bin/env bash
# detect-stack.sh — auto-detect project stack and emit the validation commands to run.
#
# Usage:
#   bash scripts/detect-stack.sh [project-root]
#
# Output (stdout): one shell command per line that should be executed for validation.
# Exit code: 0 always — callers decide whether to abort on command failure.
#
# Example output:
#   make validate
#   pnpm test
#   pnpm run lint
#
# The skill's Step 4 sources this output and runs each command in sequence.
#
# WHY SILENCE IS NOT AN ACCEPTABLE ANSWER
#   The previous version knew six languages. For a Java, Kotlin, PHP, .NET,
#   Elixir, Swift or Bazel repo it emitted NOTHING, and start-dev's step 4 then
#   ran nothing and reported success — validation that never happened, reported
#   as validation that passed. When nothing is detected this now emits a single
#   `# NO-VALIDATION: <reason>` line (a shell comment, so a caller that executes
#   each line is unharmed) and repeats it on stderr. A caller must treat that
#   line as "this repo was NOT validated", never as "there was nothing to do".
#
#   Commands are also emitted only when the tool they invoke is actually
#   configured: `python -m pytest` used to be emitted for any repo with a
#   pyproject.toml, pytest installed or not.

set -euo pipefail

ROOT="${1:-.}"
EMITTED=0
DETECTED=()

emit() { echo "$1"; EMITTED=$((EMITTED + 1)); }
detected() { DETECTED+=("$1"); }

has_file() { [ -f "$ROOT/$1" ]; }
# any_file <glob> — true when at least one match exists at the repo root.
any_file() {
  local g
  for g in "$ROOT"/$1; do [ -e "$g" ] && return 0; done
  return 1
}
# grep_file <file> <ere> — quiet grep that never trips set -e.
grep_file() { [ -f "$ROOT/$1" ] && grep -qE "$2" "$ROOT/$1" 2>/dev/null; }

# make_target <name> — handles the escaped-colon spelling (`agent\:check:`).
make_target() {
  local esc="${1//:/\\\\?:}"
  [ -f "$ROOT/Makefile" ] && grep -qE "^${esc}:" "$ROOT/Makefile" 2>/dev/null
}

# ---------- Makefile-based repos (Claude Code plugins, config-heavy projects) ----------
if [ -f "$ROOT/Makefile" ]; then
  detected "Makefile"
  if   make_target validate; then emit "make validate"
  elif make_target test;     then emit "make test"
  elif make_target lint;     then emit "make lint"
  fi

  # Multi-platform / agent-kit pre-PR gate (after stack validate) — mandatory in start-dev + pr-dev
  PRE_PR_SCRIPT="$ROOT/skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh"
  if [ -f "$PRE_PR_SCRIPT" ]; then
    emit "bash \"$PRE_PR_SCRIPT\" \"$ROOT\""
  elif make_target repo-standards-gate; then emit "make repo-standards-gate"
  elif make_target agent-polish-gate;   then emit "make agent-polish-gate"
  elif make_target agent:check;         then emit "make agent:check"
  fi
fi

# ---------- Node / JavaScript / TypeScript ----------
if has_file package.json; then
  PKG="$ROOT/package.json"
  detected "package.json"

  # Package manager, in order of authority: the corepack `packageManager` field
  # (what the repo DECLARES), then the lockfile that exists, then npm. Reading
  # the lockfile alone missed bun entirely and mis-called every corepack repo.
  PM=""
  if command -v jq >/dev/null 2>&1; then
    PM="$(jq -r '.packageManager // empty' "$PKG" 2>/dev/null | cut -d@ -f1)"
  fi
  if [ -z "$PM" ]; then
    if   has_file pnpm-lock.yaml; then PM="pnpm"
    elif has_file yarn.lock;      then PM="yarn"
    elif has_file bun.lockb || has_file bun.lock; then PM="bun"
    else PM="npm"
    fi
  fi

  # script <name> — is this npm script actually declared? (Not "does the string
  # appear anywhere in package.json", which matched dependency names.)
  script() {
    if command -v jq >/dev/null 2>&1; then
      [ -n "$(jq -r --arg s "$1" '.scripts[$s] // empty' "$PKG" 2>/dev/null)" ]
    else
      grep -qE "\"$1\"[[:space:]]*:" "$PKG" 2>/dev/null
    fi
  }

  script test      && emit "$PM test"
  script lint      && emit "$PM run lint"
  if script typecheck; then
    emit "$PM run typecheck"
  elif script type-check; then
    emit "$PM run type-check"
  elif has_file tsconfig.json; then
    emit "npx tsc --noEmit"
  fi
fi

# ---------- Deno ----------
if has_file deno.json || has_file deno.jsonc; then
  detected "Deno"
  emit "deno check ."
  emit "deno lint"
  [ -d "$ROOT/tests" ] || [ -d "$ROOT/test" ] && emit "deno test"
fi

# ---------- Python ----------
if has_file pyproject.toml || has_file setup.py || has_file requirements.txt || has_file setup.cfg; then
  detected "Python"
  # Runner prefix: use the project's environment manager rather than a bare
  # `python`, which resolves to whatever happens to be on PATH.
  PYRUN="python -m"
  if   has_file uv.lock     && command -v uv >/dev/null 2>&1;     then PYRUN="uv run python -m"
  elif has_file poetry.lock && command -v poetry >/dev/null 2>&1; then PYRUN="poetry run python -m"
  fi

  # pytest only when pytest is actually configured — the old unconditional
  # `python -m pytest` failed on every unittest-only project.
  if has_file pytest.ini \
     || grep_file pyproject.toml '\[tool\.pytest' \
     || grep_file setup.cfg '\[tool:pytest\]' \
     || grep_file tox.ini '\[pytest\]' \
     || grep_file requirements.txt '(^|[^a-z])pytest' \
     || grep_file pyproject.toml '"?pytest"?'; then
    emit "$PYRUN pytest"
  elif [ -d "$ROOT/tests" ] || [ -d "$ROOT/test" ]; then
    emit "$PYRUN unittest discover"
  fi
  if   grep_file pyproject.toml '\[tool\.ruff' || has_file ruff.toml || has_file .ruff.toml; then
    emit "ruff check ."
  elif grep_file pyproject.toml '\[tool\.flake8' || has_file .flake8; then
    emit "flake8"
  fi
  grep_file pyproject.toml '\[tool\.mypy' && emit "mypy ."
fi

# ---------- Go ----------
if has_file go.mod; then
  detected "Go"
  emit "go build ./..."
  emit "go test ./..."
  emit "go vet ./..."
fi

# ---------- Rust ----------
if has_file Cargo.toml; then
  detected "Rust"
  emit "cargo test"
  emit "cargo clippy -- -D warnings"
fi

# ---------- Ruby ----------
if has_file Gemfile; then
  detected "Ruby"
  if [ -d "$ROOT/spec" ]; then
    emit "bundle exec rspec"
  elif [ -f "$ROOT/Rakefile" ]; then
    emit "bundle exec rake test"
  elif [ -d "$ROOT/test" ]; then
    emit "bundle exec ruby -Itest -e 'Dir.glob(\"./test/**/*_test.rb\").each { |f| require f }'"
  fi
  has_file .rubocop.yml && emit "bundle exec rubocop"
fi

# ---------- Java / Kotlin / Scala (Gradle, Maven, sbt) ----------
if has_file build.gradle || has_file build.gradle.kts || has_file settings.gradle || has_file settings.gradle.kts; then
  detected "Gradle (Java/Kotlin)"
  if [ -x "$ROOT/gradlew" ]; then emit "./gradlew build"; else emit "gradle build"; fi
fi
if has_file pom.xml; then
  detected "Maven (Java)"
  if [ -x "$ROOT/mvnw" ]; then emit "./mvnw -B verify"; else emit "mvn -B verify"; fi
fi
if has_file build.sbt; then
  detected "sbt (Scala)"
  emit "sbt test"
fi

# ---------- PHP ----------
if has_file composer.json; then
  detected "PHP (composer)"
  if grep_file composer.json '"scripts"[[:space:]]*:.*' && grep_file composer.json '"test"'; then
    emit "composer test"
  elif [ -f "$ROOT/phpunit.xml" ] || [ -f "$ROOT/phpunit.xml.dist" ]; then
    emit "vendor/bin/phpunit"
  fi
  { has_file phpstan.neon || has_file phpstan.neon.dist; } && emit "vendor/bin/phpstan analyse"
fi

# ---------- .NET ----------
if any_file '*.sln' || any_file '*.csproj' || any_file '*.fsproj'; then
  detected ".NET"
  emit "dotnet build"
  emit "dotnet test"
fi

# ---------- Elixir ----------
if has_file mix.exs; then
  detected "Elixir"
  emit "mix test"
  grep_file mix.exs 'credo' && emit "mix credo"
fi

# ---------- Swift ----------
if has_file Package.swift; then
  detected "Swift (SwiftPM)"
  emit "swift build"
  emit "swift test"
elif any_file '*.xcodeproj' || any_file '*.xcworkspace'; then
  detected "Swift (Xcode)"
  emit "xcodebuild -list"
fi

# ---------- Bazel ----------
if has_file WORKSPACE || has_file WORKSPACE.bazel || has_file MODULE.bazel; then
  detected "Bazel"
  emit "bazel build //..."
  emit "bazel test //..."
fi

# ---------- Terraform ----------
if any_file '*.tf'; then
  detected "Terraform"
  emit "terraform fmt -check -recursive"
  emit "terraform validate"
fi

# ---------- Shell-only repos ----------
if [ "$EMITTED" -eq 0 ] && command -v shellcheck >/dev/null 2>&1; then
  if [ -n "$(find "$ROOT" -name '*.sh' -not -path '*/.git/*' -print -quit 2>/dev/null)" ]; then
    detected "shell scripts"
    emit "find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck -S warning"
  fi
fi

# ---------- Nothing detected: say so, loudly, on both channels ----------
if [ "$EMITTED" -eq 0 ]; then
  if [ "${#DETECTED[@]}" -gt 0 ]; then
    reason="recognised ${DETECTED[*]} but found no configured test/lint entry point"
  else
    reason="no recognised build, test, or lint configuration at $ROOT"
  fi
  echo "# NO-VALIDATION: $reason — this repo was NOT validated. Do not report step 4 as passed."
  echo "detect-stack: NO VALIDATION COMMANDS — $reason." >&2
  echo "detect-stack: add a Makefile target, an npm script, or a test runner config, and re-run." >&2
fi
