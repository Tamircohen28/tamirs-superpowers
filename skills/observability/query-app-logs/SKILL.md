---
name: query-app-logs
description: Query application logs. Invokes app-logs-agent.
allowed-tools:
  - Task
---

# Query App Logs

Invoke the `app-logs-agent` for application log queries.

## Usage

```
/query-app-logs artifact: <artifact_id> [level: ERROR] [search: pattern] [time: 1h]
```

## When to Use

- General log browsing and pattern search
- Error analysis and aggregations
- SDL operation tracing
- Domain event publishing logs

**NOT for request-specific tracing** - use `/query-request` instead
**NOT for error aggregations by tenant** - use `/query-error-logs` instead

## Parameters

| Parameter | Required | Example |
|-----------|----------|---------|
| artifact | Yes | com.wixpress.bookings.bookings-service |
| level | No | ERROR, WARN, INFO, DEBUG |
| search | No | timeout, EntityNotFound |
| time | No | 1h, 6h, 24h (default: 1h) |
| caller | No | SDL, grpc-handler |

## Examples

### Recent errors
```
/query-app-logs artifact: com.wixpress.bookings.bookings-service level: ERROR
```

### Search for timeouts
```
/query-app-logs artifact: com.wixpress.bookings.bookings-service search: timeout time: 6h
```

### SDL operations
```
/query-app-logs artifact: com.wixpress.bookings.bookings-service caller: SDL
```

The agent handles all query execution and follows strict query behavior rules.
