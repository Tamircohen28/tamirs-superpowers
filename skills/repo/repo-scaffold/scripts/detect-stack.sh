#!/usr/bin/env bash
# detect-stack.sh — detect the tech stack for a repo being scaffolded.
#
# Usage:
#   detect-stack.sh "<description>" [<src-path>]
#   detect-stack.sh "<description>" [<src-path>] --json
#
# stdout (default): one token from the scaffolder's vocabulary —
#   nextjs | node | python | swift | generic | plugin-hint
# stdout (--json): the full detection, including facts the token cannot carry.
# Exit 0 always.
#
# WHY THE DESCRIPTION IS NOW A LAST RESORT
#   This script decided a new repo's stack partly by grepping the user's prose:
#   a description containing the word "cli" produced a Node repo, and
#   `plugin-hint` was reachable ONLY from prose, never from files. A sentence is
#   a statement of intent; a file tree is a fact. Files are now consulted first
#   and much more widely (Go, Rust, Ruby, Java/Kotlin, PHP, .NET, Elixir, Deno,
#   Bun, Terraform, agent-kit plugin layouts), the package manager is read from
#   the `packageManager` field and every lockfile rather than guessed, and a
#   prose-derived answer is labelled as a guess on stderr so the caller can see
#   which kind of answer it got.
#
#   The stdout vocabulary is deliberately unchanged: it selects scaffold
#   templates, and inventing new tokens would hand repo-scaffold a stack it has
#   no templates for. A language the scaffolder has no template for maps to
#   `generic` on stdout and is reported precisely in --json / on stderr.
set -euo pipefail

DESCRIPTION="${1:-}"
SRC="${2:-}"
MODE="token"
for arg in "$@"; do
  case "$arg" in
    --json) MODE="json" ;;
  esac
done
[[ "$SRC" == --* ]] && SRC=""

description_lower="$(printf '%s' "$DESCRIPTION" | tr '[:upper:]' '[:lower:]')"

STACK=""            # the scaffolder token
LANGUAGE=""         # the precise language/ecosystem, when known
PACKAGE_MANAGER=""  # for node/deno/bun/python/php ecosystems
SOURCE=""           # "files" | "description" | "none"

# --- file signals (authoritative) --------------------------------------------
detect_package_manager() {
  local p="$1" pm=""
  if [[ -f "$p/package.json" ]] && command -v jq >/dev/null 2>&1; then
    pm="$(jq -r '.packageManager // empty' "$p/package.json" 2>/dev/null | cut -d@ -f1)"
  fi
  if [[ -z "$pm" ]]; then
    if   [[ -f "$p/pnpm-lock.yaml" ]];                    then pm=pnpm
    elif [[ -f "$p/yarn.lock" ]];                         then pm=yarn
    elif [[ -f "$p/bun.lockb" || -f "$p/bun.lock" ]];     then pm=bun
    elif [[ -f "$p/package-lock.json" ]];                 then pm=npm
    elif [[ -f "$p/package.json" ]];                      then pm=npm
    fi
  fi
  printf '%s' "$pm"
}

detect_from_files() {
  local p="$1"

  # Agent-kit / plugin layout — a fact, where it used to be prose-only.
  if [[ -f "$p/.claude-plugin/plugin.json" || -f "$p/.claude-plugin/marketplace.json" \
        || -f "$p/agent-kit.config.json" || -d "$p/canonical/rules" ]]; then
    STACK="plugin-hint"; LANGUAGE="agent-kit"; return 0
  fi

  if [[ -f "$p/next.config.js" || -f "$p/next.config.ts" || -f "$p/next.config.mjs" \
        || -f "$p/next.config.cjs" ]]; then
    STACK="nextjs"; LANGUAGE="javascript"; return 0
  fi
  if [[ -f "$p/package.json" ]]; then
    if grep -q '"next"[[:space:]]*:' "$p/package.json" 2>/dev/null; then
      STACK="nextjs"; LANGUAGE="javascript"; return 0
    fi
    STACK="node"
    if [[ -f "$p/tsconfig.json" ]]; then LANGUAGE="typescript"; else LANGUAGE="javascript"; fi
    return 0
  fi
  if [[ -f "$p/deno.json" || -f "$p/deno.jsonc" ]]; then
    STACK="generic"; LANGUAGE="deno"; PACKAGE_MANAGER="deno"; return 0
  fi
  if [[ -f "$p/pyproject.toml" || -f "$p/requirements.txt" || -f "$p/setup.py" || -f "$p/setup.cfg" ]]; then
    STACK="python"; LANGUAGE="python"
    if   [[ -f "$p/uv.lock" ]];      then PACKAGE_MANAGER="uv"
    elif [[ -f "$p/poetry.lock" ]];  then PACKAGE_MANAGER="poetry"
    elif [[ -f "$p/Pipfile.lock" ]]; then PACKAGE_MANAGER="pipenv"
    else PACKAGE_MANAGER="pip"
    fi
    return 0
  fi
  if [[ -f "$p/Package.swift" ]]; then
    STACK="swift"; LANGUAGE="swift"; PACKAGE_MANAGER="swiftpm"; return 0
  fi
  if compgen -G "$p/*.xcodeproj" >/dev/null 2>&1 || compgen -G "$p/*.xcworkspace" >/dev/null 2>&1; then
    STACK="swift"; LANGUAGE="swift"; PACKAGE_MANAGER="xcode"; return 0
  fi

  # Languages the scaffolder has no template for: report the language
  # precisely, hand the caller `generic` so it does not pick a wrong template.
  if [[ -f "$p/go.mod" ]];        then STACK="generic"; LANGUAGE="go";      return 0; fi
  if [[ -f "$p/Cargo.toml" ]];    then STACK="generic"; LANGUAGE="rust";    PACKAGE_MANAGER="cargo"; return 0; fi
  if [[ -f "$p/Gemfile" ]];       then STACK="generic"; LANGUAGE="ruby";    PACKAGE_MANAGER="bundler"; return 0; fi
  if [[ -f "$p/pom.xml" ]];       then STACK="generic"; LANGUAGE="java";    PACKAGE_MANAGER="maven"; return 0; fi
  if [[ -f "$p/build.gradle" || -f "$p/build.gradle.kts" ]]; then
    STACK="generic"; LANGUAGE="java-kotlin"; PACKAGE_MANAGER="gradle"; return 0
  fi
  if [[ -f "$p/composer.json" ]]; then STACK="generic"; LANGUAGE="php";     PACKAGE_MANAGER="composer"; return 0; fi
  if [[ -f "$p/mix.exs" ]];       then STACK="generic"; LANGUAGE="elixir";  PACKAGE_MANAGER="hex"; return 0; fi
  if compgen -G "$p/*.sln" >/dev/null 2>&1 || compgen -G "$p/*.csproj" >/dev/null 2>&1; then
    STACK="generic"; LANGUAGE="dotnet"; PACKAGE_MANAGER="nuget"; return 0
  fi
  if compgen -G "$p/*.tf" >/dev/null 2>&1; then
    STACK="generic"; LANGUAGE="terraform"; return 0
  fi
  return 1
}

# --- description signals (a guess, and labelled as one) ----------------------
detect_from_description() {
  local d="$1"
  if echo "$d" | grep -qE '\b(plugin|agent-kit|marketplace|claude code plugin|skills distribution)\b'; then
    STACK="plugin-hint"; return 0
  fi
  if echo "$d" | grep -qE '\b(next\.?js|nextjs|vercel)\b'; then STACK="nextjs"; LANGUAGE="javascript"; return 0; fi
  if echo "$d" | grep -qE '\b(react|vue|angular|vite|frontend|tailwind)\b'; then STACK="node"; LANGUAGE="javascript"; return 0; fi
  if echo "$d" | grep -qE '\b(python|fastapi|flask|django|poetry|uvicorn|pydantic|pandas|numpy)\b'; then STACK="python"; LANGUAGE="python"; return 0; fi
  if echo "$d" | grep -qE '\b(swift|swiftui|macos|xcode|ios)\b'; then STACK="swift"; LANGUAGE="swift"; return 0; fi
  if echo "$d" | grep -qE '\b(go|golang)\b'; then STACK="generic"; LANGUAGE="go"; return 0; fi
  if echo "$d" | grep -qE '\b(rust|cargo)\b'; then STACK="generic"; LANGUAGE="rust"; return 0; fi
  if echo "$d" | grep -qE '\b(node|express|npm|typescript)\b'; then STACK="node"; LANGUAGE="typescript"; return 0; fi
  return 1
}

# 1. Files win, always.
if [[ -n "$SRC" && -d "$SRC" ]]; then
  if detect_from_files "$SRC"; then
    SOURCE="files"
    [[ -z "$PACKAGE_MANAGER" ]] && PACKAGE_MANAGER="$(detect_package_manager "$SRC")"
  fi
fi

# 2. Only then the prose, and say out loud that it is a guess.
if [[ -z "$STACK" ]]; then
  if detect_from_description "$description_lower"; then
    SOURCE="description"
    echo "detect-stack: no file signal in '${SRC:-<no src given>}' — stack '$STACK' was GUESSED from the description text, not observed. Pass --tech to be certain." >&2
  fi
fi

# 3. Nothing at all. `generic` is the answer, but not a silent one.
if [[ -z "$STACK" ]]; then
  STACK="generic"
  SOURCE="none"
  echo "detect-stack: UNKNOWN STACK — no file signal and no description match. Falling back to '$STACK', which scaffolds no language-specific tooling (no test runner, no lint config, no CI build step). Pass --tech to choose one." >&2
fi

if [[ "$MODE" == "json" ]]; then
  cat <<EOF
{
  "stack": "$STACK",
  "language": "${LANGUAGE:-unknown}",
  "package_manager": "${PACKAGE_MANAGER:-unknown}",
  "source": "$SOURCE"
}
EOF
  exit 0
fi

echo "$STACK"
