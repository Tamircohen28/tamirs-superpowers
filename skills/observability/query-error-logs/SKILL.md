---
name: query-error-logs
description: Query and analyze application errors with aggregations. Invokes error-logs-agent.
---

# Query Error Logs

Invoke the `error-logs-agent` for error analysis with aggregations, groupings, and pattern analysis.

## Usage

```
/query-error-logs artifact: <artifact_id> [error: <pattern>] [type: <type>] [transaction: <name>] [time: <range>] [group: <field>]
```

## When to Use

- Identify error hotspots and top offenders
- Analyze errors by tenant (meta_site_id)
- Compare error rates across endpoints
- Track error trends over time

**NOT for general log browsing** - use `/query-app-logs` instead
**NOT for request-specific tracing** - use `/investigate-logs` instead

## Parameters

| Parameter | Required | Example |
|-----------|----------|---------|
| artifact | Yes | com.wixpress.bookings.bookings-service |
| error | No | FeatureLimitExceeded, EntityNotFound |
| type | No | runtime (default), business, infra, unknown, all |
| transaction | No | CreateBooking, Query |
| time | No | 1h, 6h, 24h (default), 3d, 7d |
| group | No | error_class (default), meta_site_id, transaction_name, caller |

## Error Types

| Type | Description |
|------|-------------|
| `runtime` | Application runtime errors (DEFAULT) |
| `business` | Business logic errors |
| `infra` | Infrastructure errors |
| `unknown` | Unclassified errors |
| `all` | All error types |

## Examples

### Runtime errors by type (default)
```
/query-error-logs artifact: com.wixpress.bookings.bookings-service
```

### Errors by endpoint
```
/query-error-logs artifact: com.wixpress.bookings.bookings-service group: transaction_name
```

### Specific error by tenant
```
/query-error-logs artifact: com.wixpress.bookings.bookings-service error: FeatureLimitExceeded group: meta_site_id time: 3d
```

### Business errors
```
/query-error-logs artifact: com.wixpress.bookings.bookings-service type: business
```

### Errors on specific endpoint
```
/query-error-logs artifact: com.wixpress.bookings.bookings-service transaction: CreateBooking
```

The agent handles aggregation queries and presents results with insights about top offenders.
