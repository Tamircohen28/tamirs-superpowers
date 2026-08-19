.PHONY: help setup setup-plan capture install update uninstall validate lint test plugin-validate test-repo-contract \
	check-manifest-versions check-platform-equivalence check-agent-drift \
	check-feature-equivalence check-platform-targets platform-targets-sync \
	platform-targets-assert platform-targets-cochange agent\:check agent-polish-gate \
	assert-contract repo-standards-gate opencode-agents opencode-agents-check \
	check-marketplace-schema check-doc-claims test-hooks doctor check-version-truth \
	check-capability-registry validate-roles check-gemini-adapter gemini-extension \
	gemini-extension-check bootstrap-dev

SKILLS_DIR := skills
HOOKS_DIR  := hooks
CONTRACT_DIR := skills/repo/_contract

help:
	@echo "Available targets:"
	@echo "  setup                   — render repo config onto this machine (detect, diff, confirm)"
	@echo "  setup-plan              — show what setup would change; writes nothing"
	@echo "  capture                 — the inverse: review this machine's hand-edits back into the repo"
	@echo "  install                 — bootstrap ~/.claude/settings.json and specialist agents"
	@echo "  update                  — refresh plugin + agents"
	@echo "  uninstall               — remove installed agents and uninstall plugin when possible"
	@echo "  validate                — full CI-parity local gate (lint, contract, JSON, skills)"
	@echo "  agent:check             — drift + feature equivalence + platform targets (agents)"
	@echo "  agent-polish-gate       — sync platform targets + assert current + agent:check (agents, pre-PR)"
	@echo "  repo-standards-gate     — agent-polish-gate + assert-contract (release PR polish exit)"
	@echo "  assert-contract         — repo-standards P1/P2/P3 exit gate (--manifests-only on release PRs)"
	@echo "  platform-targets-sync   — refresh latest_known in platform-targets.json (agents)"
	@echo "  platform-targets-assert — fail if validated_against lags latest_known (agents)"
	@echo "  platform-targets-cochange — CI: require platform-targets.json when repo skills change"
	@echo "  opencode-agents         — regenerate .opencode/agent/*.md from agents/*.md"
	@echo "  opencode-agents-check   — fail if .opencode/agent/ has drifted from agents/"
	@echo "  lint                    — shellcheck .sh files only"
	@echo "  test-hooks              — behavior tests for hooks/ (tests/test-*.sh)"
	@echo "  test-repo-contract      — contract fixtures (app-gold, plugin-gold, claude-plugin-gold)"
	@echo "  plugin-validate         — claude plugin validate (requires Claude Code CLI)"
	@echo "  check-manifest-versions — plugin manifests agree with each other"
	@echo "  check-marketplace-schema — extraKnownMarketplaces is a record, not an array"
	@echo "  check-doc-claims        — skill counts and target coverage match reality"
	@echo "  doctor                  — environment/install health report"
	@echo "  check-version-truth     — every manifest/doc agrees with plugin-version.json"
	@echo "  check-capability-registry — core/capabilities/ registry is valid"
	@echo "  validate-roles          — canonical roles, agents, workflow schemas"
	@echo "  check-gemini-adapter    — Gemini CLI extension adapter"
	@echo "  gemini-extension        — regenerate the Gemini extension mirror"
	@echo "  bootstrap-dev           — contributor toolchain setup"
	@echo "  test                    — alias for validate"

setup:
	@bash scripts/setup.sh apply

setup-plan:
	@bash scripts/setup.sh plan

# The inverse direction. `review` shows the classified change set, then asks
# about each offerable hunk; with no terminal it prints and adopts nothing.
capture:
	@bash scripts/capture-config.sh review

install:
	@bash scripts/install.sh

update:
	@bash scripts/update.sh

uninstall:
	@bash scripts/uninstall.sh

test-hooks:
	@echo "--- Hook behavior tests ---"
	@find tests -maxdepth 1 -name 'test-*.sh' 2>/dev/null | sort | while read -r f; do \
	  echo "==> $$f"; bash "$$f" || exit 1; \
	done

validate: lint test-hooks test-repo-contract check-manifest-versions check-platform-equivalence \
	check-marketplace-schema check-doc-claims check-version-truth check-capability-registry \
	validate-roles check-gemini-adapter
	@echo "--- Validating JSON files ---"
	@find . -name '*.json' -not -path '*/.git/*' | while read f; do \
	  jq empty "$$f" 2>&1 && echo "  OK  $$f" || { echo "  FAIL $$f"; exit 1; }; \
	done
	@echo "--- Validating SKILL.md frontmatter (portable + tamirs + claude tiers) ---"
	@python3 -c "import yaml" 2>/dev/null || python3 -m pip install -q -r scripts/requirements-validate.txt
	@python3 scripts/validate-skill-frontmatter.py
	@echo "--- Checking for orphan hook scripts (not referenced in hooks.json) ---"
	@if [ -d "$(HOOKS_DIR)" ] && [ -f "$(HOOKS_DIR)/hooks.json" ]; then \
	  find $(HOOKS_DIR) -maxdepth 1 -name '*.sh' | while read f; do \
	    base=$$(basename "$$f"); \
	    grep -q "$$base" $(HOOKS_DIR)/hooks.json || { echo "  WARN  $$f not referenced in hooks.json"; }; \
	  done; \
	else \
	  echo "  hooks/ absent — skipping orphan hook check"; \
	fi
	@echo "All local checks passed. Run 'make plugin-validate' for full Claude Code validation."

check-agent-drift:
	@bash scripts/check-agent-drift.sh .

check-feature-equivalence:
	@bash scripts/check-feature-equivalence.sh .

check-platform-targets:
	@bash scripts/check-platform-targets.sh .

check-marketplace-schema:
	@bash scripts/check-marketplace-schema.sh .

check-doc-claims:
	@bash scripts/check-doc-claims.sh .

doctor:
	@bash scripts/doctor.sh .

check-version-truth:
	@echo "--- Version truth (plugin-version.json) ---"
	@bash scripts/check-version-truth.sh .

check-capability-registry:
	@echo "--- Capability registry ---"
	@bash scripts/check-capability-registry.sh .

validate-roles:
	@echo "--- Canonical roles / agents / workflow schemas ---"
	@bash scripts/validate-roles.sh .

check-gemini-adapter:
	@echo "--- Gemini CLI adapter ---"
	@bash scripts/check-gemini-adapter.sh .

gemini-extension:
	@bash scripts/build-gemini-extension.sh .

gemini-extension-check:
	@bash scripts/build-gemini-extension.sh . --check

platform-targets-sync:
	@bash scripts/check-platform-targets.sh . --sync

platform-targets-assert:
	@bash scripts/check-platform-targets.sh . --assert-current

platform-targets-cochange:
	@bash scripts/check-platform-targets.sh . --require-co-change

opencode-agents:
	@bash scripts/build-opencode-agents.sh .

opencode-agents-check:
	@bash scripts/build-opencode-agents.sh . --check

agent\:check: check-agent-drift check-feature-equivalence check-platform-targets opencode-agents-check

agent-polish-gate: platform-targets-sync platform-targets-assert agent\:check

assert-contract:
	@PROFILE=$$(bash $(CONTRACT_DIR)/scripts/detect-contract-profile.sh .); \
	bash $(CONTRACT_DIR)/scripts/assert-contract.sh . "$$PROFILE" --manifests-only

repo-standards-gate: agent-polish-gate assert-contract

check-platform-equivalence: check-feature-equivalence check-platform-targets

# Lint EVERY tracked shell script, at any depth. The previous recipe used
# `find ... -maxdepth 1` over three directories, which silently excluded all 47
# skills/<domain>/<skill>/scripts/*.sh, every fixture script, .cursor/hooks/, and
# hooks/lib/ — including worktree-common.sh, which CLAUDE.md requires be
# shellchecked. See docs/engineering/refactor/file-inventory.md section 2.1.
lint:
	@echo "--- shellcheck (all tracked *.sh, any depth) ---"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  n=0; \
	  for f in $$(git ls-files --cached --others --exclude-standard '*.sh' 2>/dev/null || find . -name '*.sh' -not -path './.git/*'); do \
	    shellcheck -S warning --exclude SC2034 "$$f" || exit 1; \
	    n=$$((n+1)); \
	  done; \
	  echo "  shellcheck passed ($$n files)"; \
	else \
	  echo "  shellcheck not installed — skipping (brew install shellcheck)"; \
	fi

test-repo-contract:
	@echo "--- Repo contract (scaffold-gold / app-gold) ---"
	@CONTRACT_OFFLINE=1 bash $(CONTRACT_DIR)/scripts/assert-contract.sh \
	  $(CONTRACT_DIR)/fixtures/scaffold-gold app-gold
	@echo "--- Repo contract (scaffold-plugin-gold / plugin-gold) ---"
	@cd $(CONTRACT_DIR)/fixtures/scaffold-plugin-gold && npm run build
	@CONTRACT_OFFLINE=1 bash $(CONTRACT_DIR)/scripts/assert-contract.sh \
	  $(CONTRACT_DIR)/fixtures/scaffold-plugin-gold plugin-gold
	@echo "--- Feature equivalence (scaffold-claude-plugin-gold) ---"
	@$(MAKE) -C $(CONTRACT_DIR)/fixtures/scaffold-claude-plugin-gold agent\:check

check-manifest-versions:
	@echo "--- Manifest/tag version alignment ---"
	@git fetch --tags --quiet 2>/dev/null || true
	@bash $(CONTRACT_DIR)/scripts/check-manifest-version-alignment.sh . --manifests-only

plugin-validate:
	@echo "--- claude plugin validate (primary validator) ---"
	@if command -v claude >/dev/null 2>&1; then \
	  claude plugin validate . && echo "  plugin validate passed"; \
	else \
	  echo "  claude CLI not found — install from claude.ai/code"; \
	  exit 1; \
	fi

test: validate
