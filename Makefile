.PHONY: help install update uninstall validate lint test plugin-validate test-repo-contract \
	check-manifest-versions check-platform-equivalence check-agent-drift \
	check-feature-equivalence check-platform-targets platform-targets-sync \
	platform-targets-assert platform-targets-cochange agent\:check agent-polish-gate

SKILLS_DIR := skills
HOOKS_DIR  := hooks
CONTRACT_DIR := skills/repo/_contract

help:
	@echo "Available targets:"
	@echo "  install                 — bootstrap ~/.claude/settings.json and specialist agents"
	@echo "  update                  — refresh plugin + agents"
	@echo "  uninstall               — remove installed agents and uninstall plugin when possible"
	@echo "  validate                — full CI-parity local gate (lint, contract, JSON, skills)"
	@echo "  agent:check             — drift + feature equivalence + platform targets (agents)"
	@echo "  agent-polish-gate       — sync platform targets + assert current + agent:check (agents, pre-PR)"
	@echo "  platform-targets-sync   — refresh latest_known in platform-targets.json (agents)"
	@echo "  platform-targets-assert — fail if validated_against lags latest_known (agents)"
	@echo "  platform-targets-cochange — CI: require platform-targets.json when repo skills change"
	@echo "  lint                    — shellcheck .sh files only"
	@echo "  test-repo-contract      — contract fixtures (app-gold, plugin-gold, claude-plugin-gold)"
	@echo "  plugin-validate         — claude plugin validate (requires Claude Code CLI)"
	@echo "  check-manifest-versions — plugin manifests agree with each other"
	@echo "  test                    — alias for validate"

install:
	@bash scripts/install.sh

update:
	@bash scripts/update.sh

uninstall:
	@bash scripts/uninstall.sh

validate: lint test-repo-contract check-manifest-versions check-platform-equivalence
	@echo "--- Validating JSON files ---"
	@find . -name '*.json' -not -path '*/.git/*' | while read f; do \
	  jq empty "$$f" 2>&1 && echo "  OK  $$f" || { echo "  FAIL $$f"; exit 1; }; \
	done
	@echo "--- Validating SKILL.md frontmatter (all official Claude Code fields) ---"
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

platform-targets-sync:
	@bash scripts/check-platform-targets.sh . --sync

platform-targets-assert:
	@bash scripts/check-platform-targets.sh . --assert-current

platform-targets-cochange:
	@bash scripts/check-platform-targets.sh . --require-co-change

agent\:check: check-agent-drift check-feature-equivalence check-platform-targets

agent-polish-gate: platform-targets-sync platform-targets-assert agent\:check

check-platform-equivalence: check-feature-equivalence check-platform-targets

lint:
	@echo "--- shellcheck ---"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  find scripts $(CONTRACT_DIR)/scripts -maxdepth 1 -name '*.sh' 2>/dev/null | \
	    while read -r f; do shellcheck -S warning --exclude SC2034 "$$f" || exit 1; done; \
	  if [ -d "$(HOOKS_DIR)" ]; then \
	    find $(HOOKS_DIR) -maxdepth 1 -name '*.sh' 2>/dev/null | \
	      while read -r f; do shellcheck -S warning --exclude SC2034 "$$f" || exit 1; done; \
	  fi; \
	  echo "  shellcheck passed"; \
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
