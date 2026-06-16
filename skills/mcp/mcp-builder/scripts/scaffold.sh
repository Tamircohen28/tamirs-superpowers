#!/usr/bin/env bash
# scaffold.sh — Bootstrap an MCP server project skeleton
#
# Usage:
#   bash scaffold.sh <project-name> [ts|py] [service-prefix]
#
# Examples:
#   bash scaffold.sh github-mcp ts github
#   bash scaffold.sh stripe-mcp ts stripe
#   bash scaffold.sh db-mcp py db
#
# Output: creates ./<project-name>/ with a working skeleton

set -euo pipefail

PROJECT="${1:-my-mcp-server}"
LANG="${2:-ts}"
PREFIX="${3:-${PROJECT//-/_}}"
PREFIX="${PREFIX//-/_}"  # replace any remaining dashes

echo "Scaffolding MCP server: $PROJECT (lang=$LANG, prefix=$PREFIX)"

mkdir -p "$PROJECT"

if [[ "$LANG" == "ts" ]]; then
  # --- TypeScript skeleton ---
  mkdir -p "$PROJECT/src"

  cat > "$PROJECT/package.json" <<PKGJSON
{
  "name": "$PROJECT",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "@types/node": "^20.0.0",
    "ts-node": "^10.9.0"
  }
}
PKGJSON

  cat > "$PROJECT/tsconfig.json" <<TSCJSON
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true
  },
  "include": ["src"]
}
TSCJSON

  TOKEN_VAR="${PREFIX^^}_TOKEN"

  cat > "$PROJECT/README.md" <<README
# $PROJECT MCP Server

An MCP server that exposes $PROJECT as Claude tools.

## Required environment variables

| Variable | Description |
|----------|-------------|
| \`$TOKEN_VAR\` | API token for $PROJECT |

## Setup

\`\`\`bash
npm install
npm run build
\`\`\`

## Run (stdio)

\`\`\`bash
$TOKEN_VAR=your-token node dist/index.js
\`\`\`

## Test with MCP Inspector

\`\`\`bash
npx @modelcontextprotocol/inspector dist/index.js
\`\`\`
README

  cat > "$PROJECT/src/index.ts" <<'TSEOF'
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "PROJECT_NAME",
  version: "1.0.0",
});

// TODO: Replace with real API base URL
const API_BASE = "https://api.example.com";
const TOKEN_ENV = "PREFIX_TOKEN";

function getToken(): string {
  const token = process.env[TOKEN_ENV];
  if (!token) {
    throw new Error(`${TOKEN_ENV} environment variable is required. Add it to your MCP client config.`);
  }
  return token;
}

// --- List tool: replace with real implementation ---
server.registerTool(
  "PREFIX_list_items",
  {
    description:
      "Returns a paginated list of items. Supply cursor from a previous response to fetch the next page.",
    inputSchema: {
      limit: z
        .number()
        .int()
        .min(1)
        .max(100)
        .default(20)
        .describe("Max items to return (1–100). Default 20."),
      cursor: z
        .string()
        .optional()
        .describe("Pagination cursor from a previous response."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ limit, cursor }) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);

    const res = await fetch(`${API_BASE}/items?${params}`, {
      headers: { Authorization: `Bearer ${getToken()}` },
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(
        `PROJECT_NAME API error ${res.status}: ${body.slice(0, 200)}. ` +
          `Check the ${TOKEN_ENV} env var and verify permissions.`
      );
    }

    const data = (await res.json()) as { items: unknown[]; next_cursor?: string };
    return {
      content: [{ type: "text", text: JSON.stringify(data.items, null, 2) }],
      structuredContent: {
        items: data.items,
        next_cursor: data.next_cursor ?? null,
      },
    };
  }
);

// --- Get-by-ID tool: replace with real implementation ---
server.registerTool(
  "PREFIX_get_item",
  {
    description: "Returns a single item by ID.",
    inputSchema: {
      id: z.string().describe("The item ID to retrieve."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ id }) => {
    const res = await fetch(`${API_BASE}/items/${encodeURIComponent(id)}`, {
      headers: { Authorization: `Bearer ${getToken()}` },
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(
        `PROJECT_NAME API error ${res.status}: ${body.slice(0, 200)}. ` +
          `Verify item ID '${id}' exists and check ${TOKEN_ENV}.`
      );
    }

    const item = await res.json();
    return {
      content: [{ type: "text", text: JSON.stringify(item, null, 2) }],
      structuredContent: { item },
    };
  }
);

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
TSEOF

  # Replace placeholders
  TOKEN_VAR="${PREFIX^^}_TOKEN"
  sed -i '' \
    -e "s/PROJECT_NAME/$PROJECT/g" \
    -e "s/PREFIX_TOKEN/$TOKEN_VAR/g" \
    -e "s/PREFIX_/$PREFIX_/g" \
    "$PROJECT/src/index.ts" 2>/dev/null || \
  sed -i \
    -e "s/PROJECT_NAME/$PROJECT/g" \
    -e "s/PREFIX_TOKEN/$TOKEN_VAR/g" \
    -e "s/PREFIX_/$PREFIX_/g" \
    "$PROJECT/src/index.ts"

  echo "TypeScript skeleton created in ./$PROJECT/"
  echo "Next steps:"
  echo "  1. Replace API_BASE and implement real tools in src/index.ts"
  echo "  2. Run: cd $PROJECT && npm install && npm run build"
  echo "  3. Test: npx @modelcontextprotocol/inspector dist/index.js"

elif [[ "$LANG" == "py" ]]; then
  # --- Python skeleton ---
  TOKEN_VAR="${PREFIX^^}_TOKEN"

  cat > "$PROJECT/server.py" <<PYEOF
"""$PROJECT MCP server (FastMCP)"""
from __future__ import annotations

import os
import httpx
from fastmcp import FastMCP
from pydantic import BaseModel, Field

mcp = FastMCP("$PROJECT")

# TODO: Replace with real API base URL
API_BASE = "https://api.example.com"
TOKEN_ENV = "$TOKEN_VAR"


def get_token() -> str:
    token = os.environ.get(TOKEN_ENV)
    if not token:
        raise ValueError(f"{TOKEN_ENV} environment variable is required. Add it to your MCP client config.")
    return token


# --- List tool: replace with real implementation ---
class ListItemsInput(BaseModel):
    limit: int = Field(20, ge=1, le=100, description="Max items to return (1-100). Default 20.")
    cursor: str | None = Field(None, description="Pagination cursor from a previous response.")


@mcp.tool()
async def ${PREFIX}_list_items(params: ListItemsInput) -> dict:
    """Returns a paginated list of items. Supply cursor from a previous response for the next page."""
    query: dict[str, str] = {"limit": str(params.limit)}
    if params.cursor:
        query["cursor"] = params.cursor

    async with httpx.AsyncClient() as client:
        res = await client.get(
            f"{API_BASE}/items",
            params=query,
            headers={"Authorization": f"Bearer {get_token()}"},
        )
    if res.is_error:
        raise ValueError(
            f"$PROJECT API error {res.status_code}: {res.text[:200]}. "
            f"Check the {TOKEN_ENV} env var and verify permissions."
        )
    data = res.json()
    return {"items": data.get("items", []), "next_cursor": data.get("next_cursor")}


# --- Get-by-ID tool: replace with real implementation ---
class GetItemInput(BaseModel):
    id: str = Field(..., description="The item ID to retrieve.")


@mcp.tool()
async def ${PREFIX}_get_item(params: GetItemInput) -> dict:
    """Returns a single item by ID."""
    async with httpx.AsyncClient() as client:
        res = await client.get(
            f"{API_BASE}/items/{params.id}",
            headers={"Authorization": f"Bearer {get_token()}"},
        )
    if res.is_error:
        raise ValueError(
            f"$PROJECT API error {res.status_code}: {res.text[:200]}. "
            f"Verify item ID '{params.id}' exists and check {TOKEN_ENV}."
        )
    return res.json()


if __name__ == "__main__":
    mcp.run()
PYEOF

  cat > "$PROJECT/requirements.txt" <<REQS
fastmcp>=2.0.0
pydantic>=2.0.0
httpx>=0.27.0
REQS

  cat > "$PROJECT/README.md" <<README
# $PROJECT MCP Server

An MCP server that exposes $PROJECT as Claude tools.

## Required environment variables

| Variable | Description |
|----------|-------------|
| \`$TOKEN_VAR\` | API token for $PROJECT |

## Setup

\`\`\`bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
\`\`\`

## Run (stdio)

\`\`\`bash
$TOKEN_VAR=your-token python server.py
\`\`\`

## Test with MCP Inspector

\`\`\`bash
fastmcp dev server.py
\`\`\`
README

  echo "Python skeleton created in ./$PROJECT/"
  echo "Next steps:"
  echo "  1. Replace API_BASE and implement real tools in server.py"
  echo "  2. Run: cd $PROJECT && pip install -r requirements.txt"
  echo "  3. Test: fastmcp dev server.py"

else
  echo "Unknown language: $LANG (use 'ts' or 'py')" >&2
  exit 1
fi
