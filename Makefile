.PHONY: validate lint test help

SKILLS_DIR := skills
HOOKS_DIR  := hooks

help:
	@echo "Available targets:"
	@echo "  validate  — shellcheck all .sh files + validate all .json files"
	@echo "  lint      — shellcheck .sh files only"
	@echo "  test      — alias for validate"

validate: lint
	@echo "--- Validating JSON files ---"
	@find . -name '*.json' -not -path '*/.git/*' | while read f; do \
	  jq empty "$$f" 2>&1 && echo "  OK  $$f" || { echo "  FAIL $$f"; exit 1; }; \
	done
	@echo "--- Validating SKILL.md frontmatter (name + description fields) ---"
	@find $(SKILLS_DIR) -name 'SKILL.md' | while read f; do \
	  grep -q '^name:' "$$f" || { echo "  MISSING name: $$f"; exit 1; }; \
	  grep -q '^description:' "$$f" || { echo "  MISSING description: $$f"; exit 1; }; \
	  echo "  OK  $$f"; \
	done
	@echo "All checks passed."

lint:
	@echo "--- shellcheck ---"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  find $(HOOKS_DIR) -name '*.sh' | xargs shellcheck -S warning --exclude SC2034 && echo "  shellcheck passed"; \
	else \
	  echo "  shellcheck not installed — skipping (brew install shellcheck)"; \
	fi

test: validate
