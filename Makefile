.PHONY: validate lint test plugin-validate help

SKILLS_DIR := skills
HOOKS_DIR  := hooks

help:
	@echo "Available targets:"
	@echo "  validate        — shellcheck + JSON validation + SKILL.md frontmatter + orphan check"
	@echo "  lint            — shellcheck .sh files only"
	@echo "  plugin-validate — run 'claude plugin validate' (primary validator, requires Claude Code CLI)"
	@echo "  test            — alias for validate"

validate: lint
	@echo "--- Validating JSON files ---"
	@find . -name '*.json' -not -path '*/.git/*' | while read f; do \
	  jq empty "$$f" 2>&1 && echo "  OK  $$f" || { echo "  FAIL $$f"; exit 1; }; \
	done
	@echo "--- Validating SKILL.md frontmatter (all official Claude Code fields) ---"
	@python3 -c "import yaml" 2>/dev/null || python3 -m pip install -q -r scripts/requirements-validate.txt
	@python3 scripts/validate-skill-frontmatter.py
	@echo "--- Checking for orphan hook scripts (not referenced in hooks.json) ---"
	@find $(HOOKS_DIR) -maxdepth 1 -name '*.sh' | while read f; do \
	  base=$$(basename "$$f"); \
	  grep -q "$$base" $(HOOKS_DIR)/hooks.json || { echo "  WARN  $$f not referenced in hooks.json"; }; \
	done
	@echo "All local checks passed. Run 'make plugin-validate' for full Claude Code validation."

lint:
	@echo "--- shellcheck ---"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  find $(HOOKS_DIR) scripts -maxdepth 1 -name '*.sh' 2>/dev/null | xargs shellcheck -S warning --exclude SC2034 && echo "  shellcheck passed"; \
	else \
	  echo "  shellcheck not installed — skipping (brew install shellcheck)"; \
	fi

plugin-validate:
	@echo "--- claude plugin validate (primary validator) ---"
	@if command -v claude >/dev/null 2>&1; then \
	  claude plugin validate . && echo "  plugin validate passed"; \
	else \
	  echo "  claude CLI not found — install from claude.ai/code"; \
	  exit 1; \
	fi

test: validate
