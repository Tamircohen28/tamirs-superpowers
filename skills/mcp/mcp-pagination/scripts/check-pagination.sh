#!/usr/bin/env bash
# check-pagination.sh — scan an MCP tool definition (JSON or text) for missing pagination params
#
# Usage:
#   ./check-pagination.sh <file>            # check a JSON file with tool definitions
#   echo '{"name":"list_issues",...}' | ./check-pagination.sh -  # pipe a single tool definition
#
# Exit codes:
#   0 — all tools pass
#   1 — one or more tools fail the guardrail

set -euo pipefail

PASS_MARK="PASS"
FAIL_MARK="FAIL"
ISSUES=0

# Pagination-related keywords to look for (case-insensitive)
LIMIT_KEYWORDS="limit|max_results|per_page|page_size|count|first|top"
CURSOR_KEYWORDS="cursor|page_token|next_token|start_cursor|after|page|offset|start_at|startAt"
DATE_KEYWORDS="since|before|after|from|to|created_after|updated_before|start_date|end_date"
SQL_KEYWORDS="sql|query|statement"

# Tool name patterns that require pagination
LIST_PATTERN="^(list_|search_|find_|get_all_|fetch_all_)"

# Tool name patterns that return single items and are exempt
SINGLE_ITEM_PATTERN="^(get_|fetch_|read_|describe_)[a-z_]*(by_id|_by_id|_by_[a-z]+)?$"

check_tool() {
    local tool_json="$1"
    local name
    name=$(echo "$tool_json" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')

    if [[ -z "$name" ]]; then
        return 0  # skip unnamed entries
    fi

    # Check if this is a list/search tool
    if ! echo "$name" | grep -qiE "$LIST_PATTERN"; then
        echo "  SKIP  $name (not a list/search operation)"
        return 0
    fi

    # Check for SQL tools — need LIMIT enforcement, not pagination params
    if echo "$name" | grep -qiE "execute|run_query|sql|query"; then
        if echo "$tool_json" | grep -qiE "limit|validate|enforce"; then
            echo "  $PASS_MARK   $name (SQL tool has limit/validate reference)"
        else
            echo "  $FAIL_MARK   $name (SQL tool — no LIMIT enforcement found in schema)"
            ISSUES=$((ISSUES + 1))
        fi
        return 0
    fi

    # Check for any limiting parameter
    local has_limit=false
    local has_cursor=false
    local has_date=false

    if echo "$tool_json" | grep -qiE "$LIMIT_KEYWORDS"; then
        has_limit=true
    fi
    if echo "$tool_json" | grep -qiE "$CURSOR_KEYWORDS"; then
        has_cursor=true
    fi
    if echo "$tool_json" | grep -qiE "$DATE_KEYWORDS"; then
        has_date=true
    fi

    if $has_limit || $has_cursor || $has_date; then
        echo "  $PASS_MARK   $name"
    else
        echo "  $FAIL_MARK   $name (no limit/cursor/date-filter parameter found)"
        ISSUES=$((ISSUES + 1))
    fi
}

main() {
    local input_file="${1:--}"
    local content

    if [[ "$input_file" == "-" ]]; then
        content=$(cat)
    else
        if [[ ! -f "$input_file" ]]; then
            echo "Error: file not found: $input_file" >&2
            exit 1
        fi
        content=$(cat "$input_file")
    fi

    echo "=== MCP Pagination Guardrail Check ==="
    echo ""

    # Use process substitution instead of a pipe to avoid a subshell for the while loop.
    # A pipe creates a subshell where mutations to ISSUES are invisible to the parent shell,
    # so the exit-code logic below would always see ISSUES=0 even on failures.
    while IFS= read -r tool_json; do
        check_tool "$tool_json"
    done < <(python3 -c "
import sys, json, re

raw = sys.stdin.read().strip()

# Try to parse as JSON
try:
    data = json.loads(raw)
    if isinstance(data, list):
        tools = data
    elif isinstance(data, dict) and 'tools' in data:
        tools = data['tools']
    elif isinstance(data, dict) and 'name' in data:
        tools = [data]
    else:
        tools = [data]
except json.JSONDecodeError:
    # Fall back: extract JSON objects with 'name' field via regex
    tools = []
    for match in re.finditer(r'\{[^{}]*\"name\"[^{}]*\}', raw, re.DOTALL):
        try:
            tools.append(json.loads(match.group()))
        except Exception:
            pass

for tool in tools:
    print(json.dumps(tool))
" <<< "$content")

    echo ""
    if [[ "$ISSUES" -eq 0 ]]; then
        echo "Result: ALL TOOLS PASS"
        exit 0
    else
        echo "Result: $ISSUES TOOL(S) FAILED — add limit/cursor/date params before approving design"
        exit 1
    fi
}

main "$@"
