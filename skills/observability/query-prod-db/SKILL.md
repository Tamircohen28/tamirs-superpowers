---
name: query-prod-db
description: Query production databases via SDL configuration
allowed-tools:
  - Read
  - Glob
  - Grep
  - mcp__MCP-S__db-core__execute_sql_query
  - mcp__MCP-S__db-core__get_schema_analysis
  - mcp__MCP-S__db-core__list_bindings
  - ToolSearch
---

# Query Database Skill

Query production databases by extracting SDL configuration from service BUILD files and using the db-core MCP tools.

## Usage
```
/query-db [service-path] [query or "describe"]
```

## Arguments
- `$ARGUMENTS` - Can be:
  - A service path + SQL query: `bookings-service "SELECT * FROM bookings WHERE tenant_id = UNHEX(REPLACE('uuid', '-', '')) LIMIT 100"`
  - A service path + "describe": `bookings-service describe` (shows table structure)
  - A service path + table + "describe": `bookings-service bookings describe`
  - Just a query if already connected: `"SELECT * FROM schedules WHERE tenant_id = UNHEX(REPLACE('uuid', '-', '')) LIMIT 100"`

## Limitations

**PII/CA clusters are NOT supported** by the MCP tool. If the cluster name contains `pii` or `ca`, inform the user and provide the manual query commands instead.

## Instructions

When this skill is invoked, follow these steps:

### Step 1: Load MCP Tools
First, load the required MCP tools:
```
ToolSearch: select:mcp__MCP-S__db-core__execute_sql_query
ToolSearch: select:mcp__MCP-S__db-core__get_schema_analysis
```

### Step 2: Parse Arguments
Extract from `$ARGUMENTS`:
- Service path (e.g., `bookingsV2/bookings-service`, `calendar-3/schedules`)
- Query or action (`describe`, SQL query)
- Optional: specific table name

### Step 3: Find SDL Configuration
If a service path is provided:
1. Locate the BUILD.bazel file at `bookings-backend/{service-path}/BUILD.bazel`
2. Extract the `sdl = { ... }` configuration block
3. Parse to get:
   - **Cluster name** (e.g., `pii_calendar_platform`, `bookings_server`)
   - **Database name** (e.g., `schedules_3`, `bookings_2`)
   - **Table name(s)** and their entity types

Example SDL structure:
```python
sdl = {
    "cluster_name": {
        "database_name": {
            "table_name": {
                "entity": "com.wixpress.package.EntityDomain",
                "trash_bin": False,
            },
        },
    },
},
```

### Step 4: Check for PII/CA Cluster
If the cluster name contains `pii` or `ca`:
1. Inform the user: "This is a PII/CA cluster which is not supported by the MCP tool."
2. Provide manual query instructions using the local script:
   ```bash
   ~/DbAccess/non-interactive-db-connect.sh -t mysql -c {CLUSTER} -d {DATABASE} -a query -q "{SQL_QUERY}"
   ```
3. Stop here - do not attempt MCP query.

### Step 5: Verify with User (if multiple options)
If the SDL contains multiple databases or tables:
- List all available options
- Ask user to confirm which one to query
- Or auto-select if the query/table name makes it obvious

### Step 6: MANDATORY Query Requirements (for SELECT queries)

**⚠️ CRITICAL - NON-NEGOTIABLE REQUIREMENTS ⚠️**

**ALL SELECT queries MUST have BOTH of these. NO EXCEPTIONS:**

#### 6a. LIMIT 100 - MANDATORY

1. **EVERY** SELECT query MUST have `LIMIT 100`
2. If `LIMIT` is missing → **REFUSE TO EXECUTE** until `LIMIT 100` is added
3. If `LIMIT` is present but greater than 100 → **REFUSE TO EXECUTE** and replace with `LIMIT 100`
4. **NEVER** execute a SELECT query without `LIMIT 100`

#### 6b. tenant_id - MANDATORY

1. **EVERY** SELECT query MUST include a `tenant_id` predicate in the WHERE clause
2. If `tenant_id` is missing → **REFUSE TO EXECUTE** until tenant_id is provided
3. Ask the user: "This query requires a tenant_id. Please provide the tenant UUID:"
4. Once provided, add the predicate:
   ```sql
   WHERE tenant_id = UNHEX(REPLACE('{tenant_uuid}', '-', ''))
   ```

**BOTH requirements must be met before executing ANY SELECT query.**

### Step 7: Get Schema (for "describe" action)

Use the schema analysis tool:
```
mcp__MCP-S__db-core__get_schema_analysis
  clusterName: "{CLUSTER}"
  dbName: "{DATABASE}"
  tableNames: ["{TABLE}"]  # optional - omit to get all tables
```

### Step 8: Execute Query

Use the SQL execution tool:
```
mcp__MCP-S__db-core__execute_sql_query
  clusterName: "{CLUSTER}"
  dbName: "{DATABASE}"
  query: "{SQL_QUERY}"
```

### Step 9: Format and Present Results
- Format query results in a readable table
- For large results, summarize or paginate
- Include relevant metadata (row count, execution info)

## Common Tables Reference

| Service | Cluster | Database | Table | PII? |
|---------|---------|----------|-------|------|
| calendar-3/schedules | pii_calendar_platform | schedules_3 | schedules | Yes |
| calendar-3/events | pii_calendar_platform | events_3 | events | Yes |
| services-2 | pii_public_services | bookings_services_v2 | service, services_platform | Yes |
| bookingsV2/bookings-service | (check BUILD) | bookings_2 | bookings | Yes |

## Query Tips

- **LIMIT 100 is mandatory** - All SELECT queries must use `LIMIT 100`
- **tenant_id** is usually `varbinary(16)` - use: `UNHEX(REPLACE('uuid-here', '-', ''))`
- **entity** column contains JSON data - use `JSON_EXTRACT(entity, '$.field')` for specific fields
- Most tables have virtual generated columns for common fields
- **PII clusters** require manual access via `~/DbAccess/non-interactive-db-connect.sh`

## Examples

```
/query-db calendar-3/schedules describe
/query-db calendar-3/schedules "SELECT entity_id, externalId FROM schedules LIMIT 100"
/query-db calendar-3/schedules "SELECT * FROM schedules WHERE tenant_id = UNHEX(REPLACE('a0e7fcb4-ca82-4ccc-b7ee-ba1d7ad52dde', '-', '')) LIMIT 100"
/query-db bookingsV2/bookings-service bookings describe
```

## Fallback for PII Clusters

When MCP fails for PII clusters, provide these manual commands:

```bash
# Start tunnel (run in background)
~/DbAccess/non-interactive-db-connect.sh -t mysql -c {CLUSTER} -d {DATABASE}

# Check status
~/DbAccess/non-interactive-db-connect.sh -t mysql -c {CLUSTER} -d {DATABASE} -a status

# Execute query
~/DbAccess/non-interactive-db-connect.sh -t mysql -c {CLUSTER} -d {DATABASE} -a query -q "{SQL_QUERY}"

# Stop tunnel
~/DbAccess/non-interactive-db-connect.sh -t mysql -c {CLUSTER} -d {DATABASE} -a stop
```