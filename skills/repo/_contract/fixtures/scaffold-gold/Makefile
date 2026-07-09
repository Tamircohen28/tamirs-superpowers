.PHONY: help install update uninstall test lint agent\:check agent-polish-gate \
	check-agent-drift check-feature-equivalence check-platform-targets \
	platform-targets-sync platform-targets-assert

help:
	@echo "install update uninstall test lint agent\:check agent-polish-gate"

install:
	npm ci

update:
	npm update

uninstall:
	rm -rf node_modules

test:
	npm test

lint:
	npm run lint

check-agent-drift:
	bash scripts/check-agent-drift.sh .

check-feature-equivalence:
	bash scripts/check-feature-equivalence.sh .

check-platform-targets:
	bash scripts/check-platform-targets.sh .

platform-targets-sync:
	bash scripts/check-platform-targets.sh . --sync

platform-targets-assert:
	bash scripts/check-platform-targets.sh . --assert-current

agent\:check: check-agent-drift check-feature-equivalence check-platform-targets

agent-polish-gate: platform-targets-sync platform-targets-assert agent\:check
