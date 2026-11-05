.PHONY: help install update uninstall validate test lint agent\:check agent-polish-gate \
	check-agent-drift check-feature-equivalence check-platform-targets check-action-pinning \
	platform-targets-sync platform-targets-assert

# Registering a marketplace is the install. The verbs below are the ones Claude Code
# documents (claude plugin marketplace add | update | remove); Codex's are printed by
# `make help`, Cursor adds a marketplace from its UI, and OpenCode has no marketplace.
MARKETPLACE_NAME := $(shell jq -r .name .claude-plugin/marketplace.json)

help:
	@echo "install update uninstall validate test lint agent\:check agent-polish-gate"
	@echo ""
	@echo "Add this marketplace:"
	@echo "  Claude Code   /plugin marketplace add TamirCohen28/scaffold-marketplace-gold"
	@echo "  Codex         codex plugin marketplace add TamirCohen28/scaffold-marketplace-gold"
	@echo "  Cursor        .cursor-plugin/marketplace.json is read from this repo (see README)"
	@echo "  OpenCode      no marketplace — see README"

install:
	claude plugin marketplace add .

update:
	claude plugin marketplace update $(MARKETPLACE_NAME)

uninstall:
	claude plugin marketplace remove $(MARKETPLACE_NAME)

validate:
	bash scripts/validate-marketplace.sh .

test: validate

lint:
	@for f in .claude-plugin/marketplace.json .cursor-plugin/marketplace.json .agents/plugins/marketplace.json; do jq empty $$f; done

check-agent-drift:
	bash scripts/check-agent-drift.sh .

check-feature-equivalence:
	bash scripts/check-feature-equivalence.sh .

check-platform-targets:
	bash scripts/check-platform-targets.sh .

check-action-pinning:
	bash scripts/check-action-pinning.sh .

platform-targets-sync:
	bash scripts/check-platform-targets.sh . --sync

platform-targets-assert:
	bash scripts/check-platform-targets.sh . --assert-current

agent\:check: validate check-agent-drift check-feature-equivalence check-platform-targets check-action-pinning

agent-polish-gate: platform-targets-sync platform-targets-assert agent\:check
