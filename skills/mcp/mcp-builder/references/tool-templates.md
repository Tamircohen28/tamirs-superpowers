# Tool templates

Starting points for Phase 3 — one paginated list tool per language. Both follow the naming convention, the pagination gate (3.0) and the error-message pattern in `SKILL.md`.

## TypeScript tool template

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
      headers: { Authorization: `Bearer ${process.env.MYSERVICE_ACCESS}` },
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`MyService API error ${res.status}: ${body}. Check MYSERVICE_ACCESS env var and API quota.`);
    }

    const data = await res.json();
    return {
      content: [{ type: "text", text: JSON.stringify(data.items, null, 2) }],
      structuredContent: { items: data.items, next_cursor: data.next_cursor ?? null },
    };
  }
);
```

## Python tool template (FastMCP)

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
            headers={"Authorization": f"Bearer {os.environ['MYSERVICE_ACCESS']}"},
        )
    if res.is_error:
        raise ValueError(f"MyService API error {res.status_code}: {res.text}. Check MYSERVICE_ACCESS env var.")
    data = res.json()
    return {"items": data["items"], "next_cursor": data.get("next_cursor")}
```
