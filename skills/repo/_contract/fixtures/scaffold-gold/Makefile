.PHONY: help install test lint agent:check

help:
	@echo "install test lint agent:check"

install:
	npm ci

test:
	npm test

lint:
	npm run lint

agent:check:
	bash scripts/check-agent-drift.sh .
