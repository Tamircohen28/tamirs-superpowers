---
name: query-request
description: Investigate application logs by request ID. Invokes request-tracer-agent.
allowed-tools:
  - Task
---

# Investigate Logs

Invoke the `request-tracer-agent` for tracing requests through application and access logs.

## Usage

```
/query-request <artifact_id> <request_id> [time_range] [level]
```

## When to Use

- Trace a specific request through the system
- Debug production issues with a request ID
- Analyze request flow and timing
- Find errors for a specific request

**NOT for general log browsing** - use `/query-app-logs` instead
**NOT for error aggregations** - use `/query-error-logs` instead

## Parameters

| Parameter | Required | Example |
|-----------|----------|---------|
| artifact_id | Yes | com.wixpress.bookings.bookings-service |
| request_id | Yes | abc-123-def-456 |
| time_range | No | 1h, 6h, 24h (default: 1h) |
| level | No | ERROR, WARN, INFO |

## Examples

### Basic request trace
```
/query-request com.wixpress.bookings.bookings-service abc-123-def-456
```

### Errors only in last hour
```
/query-request com.wixpress.bookings.bookings-service abc-123-def-456 1h ERROR
```

### Extended time range
```
/query-request com.wixpress.bookings.bookings-service abc-123-def-456 6h
```

## Output Includes

- Request flow timeline (chronological)
- HTTP request details (method, URI, status, duration)
- Errors and stack traces
- Domain events published
- SDL operations
- Feature toggle conductions

The agent queries both app logs and access logs, presenting a unified view of the request flow.

## Artifact Discovery

The agent first queries `logs_db.id_to_app_mv` to discover all artifacts (services) that handled the request. This is a fast, lightweight lookup that avoids scanning the full `app_logs` table. The discovered artifacts are then used for focused app_logs and access_logs queries.

```sql
SELECT DISTINCT nginx_artifact_name
FROM logs_db.id_to_app_mv
WHERE request_id = '<REQUEST_ID>'
  AND $__timeFilter(timestamp)
LIMIT 500
```
