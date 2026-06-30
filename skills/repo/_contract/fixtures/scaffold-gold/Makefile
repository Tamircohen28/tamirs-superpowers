.PHONY: help install update uninstall test lint agent:check

help:
	@echo "install update uninstall test lint agent:check"

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

agent:check:
	bash scripts/check-agent-drift.sh .
