# MCP Builder Quick Reference

Loaded on demand during Phase 1 and Phase 3. This is a condensed cheatsheet — fetch the authoritative SDK docs during Phase 1.

## URLs

| Resource | URL |
|----------|-----|
| MCP spec (Markdown) | https://modelcontextprotocol.io/specification/draft.md |
| TS SDK README | https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/main/README.md |
| Python SDK README | https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/main/README.md |
| FastMCP docs | https://gofastmcp.com/getting-started/welcome |
| MCP Inspector | npx @modelcontextprotocol/inspector |

---

## Tool annotation hints (TypeScript)

```typescript
annotations: {
  readOnlyHint: true,        // no side effects (GET endpoints)
  destructiveHint: true,     // irreversible (DELETE, permanent actions)
  idempotentHint: true,      // safe to retry (PUT/PATCH with same params)
  openWorldHint: false,       // closed scope (DB queries with known schema)
}
```

---

## Zod schemas for common patterns

```typescript
// Pagination
limit: z.number().int().min(1).max(100).default(20)
cursor: z.string().optional()

// Enum filter
status: z.enum(["active", "archived", "all"]).default("active")

// Date range
since: z.string().datetime().optional().describe("ISO 8601 start date")
until: z.string().datetime().optional().describe("ISO 8601 end date")
```

---

## FastMCP tool signature variants

```python
# Variant 1: Pydantic BaseModel (recommended for complex inputs)
class MyInput(BaseModel):
    limit: int = Field(20, ge=1, le=100)

@mcp.tool()
async def my_tool(params: MyInput) -> dict: ...

# Variant 2: Individual typed parameters (simple tools)
@mcp.tool()
async def my_tool(item_id: str, include_deleted: bool = False) -> dict: ...
```

---

## Return shape (TypeScript)

```typescript
// Text output (Claude reads this)
return {
  content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
};

// With structured output (machine-readable)
return {
  content: [{ type: "text", text: JSON.stringify(data.items, null, 2) }],
  structuredContent: { items: data.items, next_cursor: data.next_cursor ?? null },
};
```

---

## Environment variable pattern

```typescript
// TypeScript
const token = process.env.MY_SERVICE_TOKEN;
if (!token) throw new Error("MY_SERVICE_TOKEN is required. Set it in your MCP client config.");
```

```python
# Python
token = os.environ.get("MY_SERVICE_TOKEN")
if not token:
    raise ValueError("MY_SERVICE_TOKEN is required. Set it in your MCP client config.")
```

---

## Naming convention cheatsheet

| Operation type | Name pattern | Example |
|---------------|--------------|---------|
| List collection | `{svc}_list_{noun}s` | `stripe_list_customers` |
| Search/filter | `{svc}_search_{noun}s` | `github_search_issues` |
| Get single item | `{svc}_get_{noun}` | `stripe_get_customer` |
| Create | `{svc}_create_{noun}` | `stripe_create_payment_intent` |
| Update | `{svc}_update_{noun}` | `github_update_issue` |
| Delete | `{svc}_delete_{noun}` | `stripe_delete_customer` |
| Action | `{svc}_{verb}_{noun}` | `github_merge_pull_request` |

---

## Error message template

```
{Service} API error {status_code}: {body_snippet_200_chars}.
{Concrete fix — e.g. "Check {TOKEN_ENV} env var" or "Use a valid {noun} ID like 'cus_ABC123'".}
```

---

## MCP Claude config entry (stdio)

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["dist/index.js"],
      "env": {
        "MY_SERVICE_TOKEN": "your-token-here"
      }
    }
  }
}
```

---

## Scaffold script

Bootstrap a project skeleton in one command:

```bash
# TypeScript
bash $CLAUDE_SKILL_DIR/scripts/scaffold.sh my-mcp-server ts myservice

# Python (FastMCP)
bash $CLAUDE_SKILL_DIR/scripts/scaffold.sh my-mcp-server py myservice
```

This creates: `package.json` / `requirements.txt`, entry file with two example tools, `README.md` with env var table, and `tsconfig.json` (TS only).
