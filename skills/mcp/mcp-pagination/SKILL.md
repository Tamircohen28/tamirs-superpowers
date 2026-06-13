---
name: mcp-pagination
disable-model-invocation: true
user-invocable: false
description: "Internal: pagination and result-limiting guardrails for MCP tool calls. Used by mcp-builder when designing MCP servers or auditing MCP tool usage. Not for direct user invocation — run mcp-builder instead."
allowed-tools:
  - Read
  - Bash
model: claude-sonnet-4-6
when_to_use: >
  Invoked automatically by mcp-builder when generating or reviewing MCP server
  designs that include list/search operations. Not called directly by users.
metadata:
  capability: mcp-guardrail
  tags:
    - mcp
    - pagination
    - guardrail
  updated-date: "2026-06-13"
---

# MCP Pagination Guardrails (Internal)

## Why this skill exists

MCP tools that return lists or search results have no built-in safety net against unbounded responses. Calling `list_issues`, `search_code`, or any similar tool without a limit parameter can return hundreds or thousands of items, consuming 10-100x more tokens than needed, slowing responses, and inflating API costs. Naive implementations skip pagination because the tool "works" without it — this guardrail enforces limits before that mistake reaches production.

This skill is injected by `mcp-builder` when it detects list or search operations in a server design. It is not a user-facing guide.

## Workflow (invoked by mcp-builder)

When `mcp-builder` invokes this skill, apply the following steps in order:

**Step 1 — Identify list/search operations in the MCP server design.**

Any tool whose name matches these patterns needs a limit strategy:
- `list_*` — always paginated
- `search_*` — always paginated
- `get_*` that returns an array at the top level — treat as paginated
- SQL-executing tools — require `LIMIT` clause enforcement

**Step 2 — Verify each operation has a limiting mechanism.**

For each identified operation, confirm one of the following is present:

| Mechanism | When to use | Example parameter |
|-----------|-------------|-------------------|
| `limit` / `max_results` / `per_page` | Primary list endpoints | `limit=20` |
| `page` + `per_page` | Cursor-style or offset pagination | `page=1, per_page=10` |
| `cursor` / `page_token` | Token-based continuation | `cursor="<token>"` |
| SQL `LIMIT` clause | Any tool that executes raw SQL | `SELECT ... LIMIT 50` |
| Date/time filter | When no explicit limit param exists | `since="2024-06-01T00:00:00Z"` |

**Step 3 — Set safe starting limits.**

Use these defaults unless the tool's documentation specifies lower maximums:

| Operation type | Safe starting limit | Rationale |
|----------------|--------------------|-|
| Code search | 5-10 | Results are large; 10 is usually enough to find the target |
| Issue / PR search | 10-20 | Each item has metadata; 20 fits comfortably in context |
| Channel / message list | 50-100 | Lightweight items; higher limit reduces round-trips |
| SQL queries | 50-100 | Depends on row width — prefer lower for wide schemas |
| Generic list | 20 | Safe default when no guidance exists |

**Step 4 — Add alternative filters when no limit param exists.**

If a tool has no pagination parameter, narrow scope with filters before fetching:

```bash
# Date filtering — prefer ISO 8601 with timezone
since="2024-06-01T00:00:00Z"
before="2024-07-01T00:00:00Z"

# State filtering — exclude irrelevant items
state="open"       # or "closed", "merged"
status="active"    # or "inactive", "archived"

# Owner/author filtering
author="username"
assignee="username"

# Path/extension filtering (code search)
path="src/api"
extension="ts"
```

**Step 5 — Enforce incremental fetching.**

The server design must not auto-paginate through all results. The correct pattern:

```
1. Fetch first page with safe limit
2. Return results to caller
3. Only fetch next page if caller explicitly requests more
```

Do NOT pre-fetch all pages and merge results — this defeats the guardrail entirely.

## Hard Rules

1. **Never generate or approve a list/search MCP tool that has no limiting strategy** — every such tool must expose at least one of: `limit`, `max_results`, `per_page`, `cursor`, or a date filter parameter.
2. **Never set a default limit above 100** — even if the tool supports higher values; the caller can increase it explicitly.
3. **Never auto-paginate** — fetching page 2+ without an explicit caller request is forbidden; it silently multiplies token consumption.
4. **Always start at the low end of the safe range** — prefer 10 over 50 when context size is unknown.
5. **SQL-executing tools must reject queries without a `LIMIT` clause** — validate the SQL string server-side before executing.
6. **Do not hardcode absolute paths or employer-specific tool names** in server designs — keep examples generic (`owner="my-org"`, not a real org name).

## Anti-patterns

**Missing limit entirely:**
```
# BAD — no limit; can return thousands of items
list_issues(repo="my-repo", state="open")

# GOOD
list_issues(repo="my-repo", state="open", limit=20)
```

**Auto-paginating all results:**
```
# BAD — fetches every page and returns merged array
results = []
page = 1
while True:
    batch = list_issues(repo="my-repo", page=page, per_page=100)
    if not batch: break
    results.extend(batch)
    page += 1
return results

# GOOD — return page 1 and expose a cursor for the caller to continue
return list_issues(repo="my-repo", page=1, per_page=20, cursor=None)
```

**Unbounded SQL:**
```sql
-- BAD
SELECT * FROM events WHERE user_id = $1

-- GOOD
SELECT * FROM events WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50
```

**Overly broad search without filters:**
```
# BAD — searches entire GitHub with no scope
search_code(query="auth")

# GOOD
search_code(query="auth", repo="my-org/my-repo", path="src/auth", limit=10)
```

## Quick-reference checklist

Before approving any MCP server design that includes list or search tools, verify:

- [ ] Every `list_*` tool has `limit` or `per_page` with a documented default <= 100
- [ ] Every `search_*` tool has `limit` or `max_results` with a documented default <= 20
- [ ] SQL-executing tools validate for a `LIMIT` clause before running
- [ ] No tool auto-paginates; pagination is always caller-driven
- [ ] Date/state/author filters are available as fallback when no limit param exists
- [ ] Default limits are at the conservative end of the safe range for the operation type
