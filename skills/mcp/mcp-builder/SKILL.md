---
name: mcp-builder
description: "Use when building an MCP (Model Context Protocol) server to expose an external API or service as Claude tools. Covers TypeScript SDK and Python FastMCP, tool design, pagination, error handling, and evaluation. Trigger phrases: 'build an MCP server', 'create MCP tools', 'integrate X with Claude via MCP', 'write an MCP server for', 'add MCP support', 'make Claude able to call', 'expose API via MCP'."
license: MIT
model: claude-sonnet-4-6
when_to_use: "User wants to build or scaffold an MCP server to integrate an external API or service with Claude. Trigger phrases: 'build an MCP server', 'create MCP tools', 'integrate X with Claude via MCP', 'write an MCP server for', 'mcp-builder', 'add MCP support', 'expose API as tools'."
argument-hint: "[service or API to integrate — e.g. 'GitHub REST API', 'Stripe', 'internal Postgres DB']"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - WebFetch
  - Skill
metadata:
  capability: mcp-development
  tags:
    - mcp
    - server
    - integration
    - developer-tools
  updated-date: "2026-06-13"
---

# MCP Server Development Guide

## Why this skill exists

Wrapping an external API in an MCP server sounds simple, but naive implementations fail Claude in practice: tools return walls of JSON that exhaust context, list operations return unbounded results that time out, error messages say "400 Bad Request" without guidance, and tool names are so generic (`get`, `list`) that the model picks wrong ones. This guide enforces the patterns — pagination-first, structured output, actionable errors, consistent naming — that make the difference between a server Claude can use reliably and one it struggles with.

---

## Language selection

| Criterion | TypeScript | Python |
|---|---|---|
| Recommended default | Yes | If team is Python-only |
| SDK maturity | High (first-party) | High (FastMCP) |
| Remote HTTP servers | `@modelcontextprotocol/sdk` | FastMCP |
| Local stdio servers | Same SDK | Same SDK |
| Type safety | Static (Zod + tsc) | Pydantic v2 |
| Compilation check | `npm run build` | `python -m py_compile` |

---

## Phase 1 — Research and planning

### 1.1 Load MCP specification

```bash
# Fetch the MCP spec sitemap to find relevant pages
curl -s https://modelcontextprotocol.io/sitemap.xml | grep -o '<loc>[^<]*</loc>' | sed 's/<[^>]*>//g'
```

Then fetch key pages with WebFetch, appending `.md` for Markdown format:

```
WebFetch("https://modelcontextprotocol.io/specification/draft.md")
WebFetch("https://modelcontextprotocol.io/docs/concepts/tools.md")
```

### 1.2 Load SDK documentation

**TypeScript (recommended):**
```
WebFetch("https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/main/README.md")
```

**Python:**
```
WebFetch("https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/main/README.md")
```

### 1.3 Understand the target API

Review authentication method, rate limits, pagination strategy (cursor vs. offset), and which endpoints map to the most common user tasks. Deprioritize rarely-used admin endpoints.

### 1.4 Invoke the mcp-pagination skill

Before implementing any list or search tool, run the pagination guardrail skill:

```
Skill("mcp-pagination")
```

This enforces mandatory pagination parameter conventions (`cursor`, `limit`, `next_cursor`) across all list/search tools.

---

## Phase 2 — Project setup

### TypeScript

```bash
mkdir my-mcp-server && cd my-mcp-server
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node ts-node
npx tsc --init --target ES2022 --module NodeNext --moduleResolution NodeNext --outDir dist --rootDir src --strict
mkdir src
```

`package.json` scripts:
```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts"
  }
}
```

### Python

```bash
mkdir my-mcp-server && cd my-mcp-server
python -m venv .venv && source .venv/bin/activate
pip install fastmcp pydantic httpx
```

---

## Phase 3 — Implement tools

### Naming convention

Use `{service}_{verb}_{noun}` — always action-oriented and unambiguous:

| Good | Bad |
|---|---|
| `github_list_issues` | `get`, `list`, `issues` |
| `stripe_create_payment_intent` | `payment`, `do_payment` |
| `db_query_users` | `query`, `fetch` |

### TypeScript tool template

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const server = new McpServer({ name: "my-service", version: "1.0.0" });

server.registerTool(
  "myservice_list_items",
  {
    description: "List items from MyService. Supports cursor-based pagination.",
    inputSchema: {
      limit: z.number().int().min(1).max(100).default(20).describe("Max items to return (1–100)."),
      cursor: z.string().optional().describe("Pagination cursor from a previous response."),
      filter: z.string().optional().describe("Filter by status: 'active' | 'archived'"),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ limit, cursor, filter }) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    if (filter) params.set("status", filter);

    const res = await fetch(`https://api.myservice.com/items?${params}`, {
      headers: { Authorization: `Bearer ${process.env.MYSERVICE_TOKEN}` },
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`MyService API error ${res.status}: ${body}. Check MYSERVICE_TOKEN env var and API quota.`);
    }

    const data = await res.json();
    return {
      content: [{ type: "text", text: JSON.stringify(data.items, null, 2) }],
      structuredContent: { items: data.items, next_cursor: data.next_cursor ?? null },
    };
  }
);
```

### Python tool template (FastMCP)

```python
from fastmcp import FastMCP
from pydantic import BaseModel, Field
import httpx, os

mcp = FastMCP("my-service")

class ListItemsInput(BaseModel):
    limit: int = Field(20, ge=1, le=100, description="Max items to return (1–100).")
    cursor: str | None = Field(None, description="Pagination cursor from a previous response.")

@mcp.tool()
async def myservice_list_items(params: ListItemsInput) -> dict:
    """List items from MyService. Supports cursor-based pagination."""
    async with httpx.AsyncClient() as client:
        res = await client.get(
            "https://api.myservice.com/items",
            params={"limit": params.limit, **({"cursor": params.cursor} if params.cursor else {})},
            headers={"Authorization": f"Bearer {os.environ['MYSERVICE_TOKEN']}"},
        )
    if res.is_error:
        raise ValueError(f"MyService API error {res.status_code}: {res.text}. Check MYSERVICE_TOKEN env var.")
    data = res.json()
    return {"items": data["items"], "next_cursor": data.get("next_cursor")}
```

---

## Phase 4 — Build and test

```bash
# TypeScript
npm run build          # must pass with zero errors
npx @modelcontextprotocol/inspector dist/index.js

# Python
python -m py_compile my_server.py
fastmcp dev my_server.py   # opens Inspector UI
```

Test each tool in the MCP Inspector before declaring done. Check:
- `list_*` tools return `next_cursor` when truncated
- Error messages include the HTTP status, response body snippet, and a suggested fix
- Tool descriptions are concise (under 120 chars for the summary line)

---

## Phase 5 — Evaluations

Create 10 read-only evaluation questions that require 3+ tool calls to answer. Format:

```xml
<evaluation>
  <qa_pair>
    <question>How many open issues are labeled 'bug' in the myservice/core repo as of today?</question>
    <answer>42</answer>
  </qa_pair>
</evaluation>
```

Each question must be: independent, read-only, complex (multi-step), realistic, and produce a stable verifiable answer.

---

## Hard rules

1. **Never return unbounded lists.** Every list/search tool must have a `limit` parameter (default ≤ 25, max ≤ 100) and return a `next_cursor` field when results are truncated.
2. **Error messages must be actionable.** Include the HTTP status, a snippet of the response body, and a concrete next step (e.g., "Check the X_TOKEN env var" or "Use a valid repo slug").
3. **Tool names must be unambiguous.** Always use `{service}_{verb}_{noun}` — never single-word names like `list` or `get`.
4. **Never hardcode credentials.** Read tokens from environment variables (`process.env.X` / `os.environ["X"]`) only.
5. **Always run `mcp-pagination` before implementing list/search tools.** Do not skip this step even for simple APIs.
6. **Compilation must pass before shipping.** `npm run build` (TypeScript) or `python -m py_compile` (Python) must exit 0.
7. **Tool descriptions must state what the tool returns**, not just what it does. Bad: "Gets issues." Good: "Returns a paginated list of open GitHub issues with title, labels, and assignee."

---

## What NOT to do

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| Return raw API response JSON as-is | Claude reads 50KB of nested objects, wastes context | Filter to the 5–10 fields actually needed |
| Single `api_call(endpoint, method, body)` catch-all tool | Claude can't discover what the API supports | Implement explicit tools per operation |
| No pagination — return all results | Times out on large datasets; floods context | Add `limit` + `cursor` to every list tool |
| `throw new Error("Error")` on API failure | Claude retries blindly with no fix | Include status code, body snippet, env var hint |
| Put auth tokens in the source code | Security leak | Use env vars; document required vars in README |
| Skip MCP Inspector testing | Broken tools ship silently | Always run Inspector before marking done |
