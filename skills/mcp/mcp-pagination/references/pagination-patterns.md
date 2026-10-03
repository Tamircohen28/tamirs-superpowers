# Pagination Patterns Reference

Quick-reference for common API pagination styles encountered in MCP server designs.
Load this file when mcp-builder passes tool names or API names that appear in the table below.

---

## GitHub REST API

| Operation | Param style | Default | Max |
|-----------|-------------|---------|-----|
| List repos | `per_page`, `page` | 30 | 100 |
| Search issues/PRs | `per_page`, `page` | 30 | 100 |
| List comments | `per_page`, `page` | 30 | 100 |
| List commits | `per_page`, `page` | 30 | 100 |

**Recommended MCP defaults:** `per_page=20`, `page=1`
**Pattern:** offset-based; expose `page` + `per_page` to caller.

---

## Supabase / PostgREST

| Operation | Param style | Default | Notes |
|-----------|-------------|---------|-------|
| Any table query | `limit`, `offset` | no default | Must be set |
| SQL via RPC | SQL `LIMIT` clause | none | Validate before execute |
| Full-text search | `limit`, `offset` | no default | Same as table |

**Recommended MCP defaults:** `limit=20`, `offset=0`
**Pattern:** inject `LIMIT` + `OFFSET` into PostgREST headers or SQL string.
**SQL guard:** reject queries that don't contain `LIMIT \d+` (case-insensitive regex).

---

## Slack Web API

| Operation | Param style | Default | Max |
|-----------|-------------|---------|-----|
| conversations.list | `limit`, `cursor` | 100 | 1000 |
| conversations.history | `limit`, `cursor` | 100 | 999 |
| search.messages | `count`, `page` | 20 | 100 |
| users.list | `limit`, `cursor` | 200 | 1000 |

**Recommended MCP defaults:** `limit=50` for lists, `count=10` for search
**Pattern:** cursor-based; return `next_cursor` to caller, never auto-follow.

---

## Linear API (GraphQL — Relay cursor pagination)

| Operation | Param style | Notes |
|-----------|-------------|-------|
| issues | `first` (default 50, max 250) | Always set `first` |
| projects | `first` | Same |
| cursor | `after: String` | Return `pageInfo.endCursor` |

**Recommended MCP defaults:** `first=20`
**Pattern:** Relay-style cursor pagination; expose `after` param to caller.

**What to return to the MCP caller:**
```json
{
  "items": [...],
  "pageInfo": {
    "endCursor": "eyJpZCI6MTIzfQ==",
    "hasNextPage": true
  }
}
```

**Anti-pattern — auto-following cursors (forbidden):**
```python
# BAD — fetches all pages before returning
cursor = None
all_items = []
while True:
    page = client.issues(first=100, after=cursor)
    all_items.extend(page.nodes)
    if not page.pageInfo.hasNextPage:
        break
    cursor = page.pageInfo.endCursor
return all_items  # could be thousands of items
```

---

## Notion API

| Operation | Param style | Default | Max |
|-----------|-------------|---------|-----|
| Search | `page_size` | 100 | 100 |
| Database query | `page_size` | 100 | 100 |
| List blocks | `page_size` | 100 | 100 |

**Recommended MCP defaults:** `page_size=20`
**Pattern:** cursor-based (`start_cursor`); Notion docs call it "cursor" but the param is `start_cursor`.

---

## Jira REST API v3

| Operation | Param style | Default | Max |
|-----------|-------------|---------|-----|
| Search issues (JQL) | `maxResults`, `startAt` | 50 | 100 |
| Get projects | `maxResults`, `startAt` | 50 | 50 |

**Recommended MCP defaults:** `maxResults=20`, `startAt=0`
**Pattern:** offset-based; total count in `total` field enables offset calculation.

---

## Streaming / Generative APIs (NOT subject to pagination guardrails)

Streaming responses are **generative**, not collection-listing — pagination guardrails do not apply.

| API type | Example | Guardrail needed? |
|----------|---------|-------------------|
| LLM token stream | OpenAI chat completions (stream=true), Anthropic Messages streaming | No — single generated response |
| Server-Sent Events | Any SSE endpoint | No — continuous push, not a paginated list |
| WebSocket feeds | Real-time market data, live chat | No |
| File upload/download | S3 streaming, multipart | No |

**Collection tools from the same provider still need guardrails:**

```
OpenAI streaming completions → NO guardrail needed
OpenAI list_fine_tunes       → YES guardrail needed (returns array of jobs)
Anthropic streaming messages → NO guardrail needed
Anthropic list_models        → YES guardrail needed (returns array of models)
```

The distinction: does the tool return a **fixed collection of discrete items** (paginate) or **push generated/live data** (no guardrail)?

---

## Generic / Unknown API

When the API type is unknown, apply these safe defaults:
- Expose a `limit` param with default `20` and maximum `100`
- Expose a `cursor` or `page` param for continuation
- Document: "caller must explicitly request subsequent pages"
- If no pagination param exists, require at least one date filter (`since` / `before`)

---

## Anti-patterns (API-agnostic)

```python
# NEVER — merges all pages before returning
def list_all_issues(repo):
    results, page = [], 1
    while True:
        batch = github.list_issues(repo, page=page, per_page=100)
        if not batch: break
        results.extend(batch)
        page += 1
    return results  # could be thousands of items

# CORRECT — return first page, expose cursor
def list_issues(repo, per_page=20, page=1):
    return github.list_issues(repo, page=page, per_page=per_page)
```

```sql
-- NEVER
SELECT * FROM events WHERE user_id = $1

-- CORRECT
SELECT * FROM events WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50
```
