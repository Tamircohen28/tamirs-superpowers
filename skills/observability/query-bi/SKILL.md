---
name: query-bi
description: Query BI data warehouse. Invokes bi-query-agent.
allowed-tools:
  - Task
---

# Query BI

Spawn the `bi-query-agent` to handle BI data warehouse queries.

## How to Invoke

Use the **Task tool** with:
- `subagent_type`: `"bi-query-agent"`
- `description`: `"Query BI data warehouse"`
- `prompt`: Pass the user's arguments (search term, table name, action, SQL)

Example Task invocation:
```
Task(
  subagent_type="bi-query-agent",
  description="Query BI data warehouse",
  prompt="Search for tables related to: bookings"
)
```

## Usage

```
/query-bi [search-term | table-name] [action]
```

## Arguments

| Argument | Example |
|----------|---------|
| search-term | `bookings` (searches for tables) |
| table + sample | `prod.bookings.booking_dim sample` |
| table + schema | `prod.bookings.booking_dim schema` |
| table + SQL | `prod.bookings.booking_dim "SELECT booking_id FROM prod.bookings.booking_dim LIMIT 10"` |
| owner:name | `owner:bookings-data` (filter by data owner) |

## Common Catalogs

| Catalog | Description |
|---------|-------------|
| `prod` | Production DWH tables |
| `domain_events` | Raw Kafka domain events |
| `events` | DBI events |

## Examples

### Search for booking tables
```
/query-bi bookings
→ Task(subagent_type="bi-query-agent", prompt="Search for tables related to: bookings")
```

### Get table schema
```
/query-bi prod.bookings.booking_dim schema
→ Task(subagent_type="bi-query-agent", prompt="Get schema for table: prod.bookings.booking_dim")
```

### Execute SQL query
```
/query-bi domain_events.bookings.v2_booking_crud "SELECT _entity_id, _event_time FROM domain_events.bookings.v2_booking_crud WHERE _msid = 'xxx' LIMIT 20"
→ Task(subagent_type="bi-query-agent", prompt="Execute SQL on domain_events.bookings.v2_booking_crud: SELECT ...")
```

The agent handles all discovery and query execution with strict pagination and safety rules.
