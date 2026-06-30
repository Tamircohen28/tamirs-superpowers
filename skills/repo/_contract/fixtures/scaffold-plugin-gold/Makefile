.PHONY: help install update uninstall test lint agent:check build validate

help:
	@echo "install update uninstall build validate test lint agent:check"

install:
	npm ci
	npm run build

update:
	npm update
	npm run build

uninstall:
	rm -rf node_modules dist

build:
	npm run build

validate:
	npm run validate

test:
	npm test

lint:
	npm run lint

agent:check:
	npm run agent:check
