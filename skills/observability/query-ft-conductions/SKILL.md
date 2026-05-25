---
name: query-ft-conductions
description: Query feature toggle conduction timeseries data from Grafana Timestream. Shows which target groups are conducting and their traffic volumes.
allowed-tools:
  - mcp__Webrix__grafana-datasource__grafana_query
  - ToolSearch
---

# Query Feature Toggle Conductions

Query the feature toggle conduction reporter (Amazon Timestream) to see traffic volumes per target group over time.

## Usage

```
/query-ft-conductions <toggleId> [time: <range>] [group: <targetGroupKey>]
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| toggleId | Yes | - | Feature toggle ID (e.g., `fixPriceUndeterminedWithPaidAddOns`) |
| time | No | 24h | Time range: `1h`, `6h`, `24h`, `7d`, `30d`, or explicit ISO dates |
| group | No | all | Filter to specific targetGroupKey (e.g., `VIP Metasites`) |

## Instructions

1. Parse the user's parameters to extract `toggleId`, optional time range, and optional group filter.

2. Calculate the `from` and `to` ISO timestamps:
   - Default: last 24 hours
   - Supported shorthands: `1h`, `6h`, `24h`, `7d`, `30d`
   - Explicit dates: use as-is in ISO 8601 format

3. Build and execute the Timestream query using `mcp__Webrix__grafana-datasource__grafana_query`:

   **If no group filter:**
   ```
   datasource: "build-up-feature-toggle"
   queryType: "timestream"
   query: SELECT targetGroupKey, BIN(time, <interval>) as time, sum(measure_value::bigint) as measure_value FROM "conductor-reporter"."report" WHERE $__timeFilter AND experimentId = '<toggleId>' AND measure_name = 'conductor-reporter' GROUP BY targetGroupKey, BIN(time, <interval>) ORDER BY time DESC LIMIT 100
   ```

   **If group filter specified:**
   ```
   Add: AND targetGroupKey = '<group>'
   ```

   **Interval selection based on time range:**
   - <= 6h: `10m`
   - <= 24h: `1h`
   - <= 7d: `6h`
   - <= 30d: `1d`

4. **Important query details:**
   - Datasource: `build-up-feature-toggle`
   - queryType: `timestream`
   - Database/table must be quoted: `"conductor-reporter"."report"`
   - Time macro: `$__timeFilter` (no column parameter for Timestream)
   - measure_name is always `'conductor-reporter'`

5. Present results as a summary table:
   - Group by `targetGroupKey`
   - Show total conductions per group
   - Show latest hourly rate
   - Note any groups with `deactivated` key (indicates toggle was turned off)

6. If the query returns 404 or empty results, the toggle may have been deleted or never existed.

## Examples

```
/query-ft-conductions fixPriceUndeterminedWithPaidAddOns
/query-ft-conductions fixPriceUndeterminedWithPaidAddOns time:7d
/query-ft-conductions setPriceUndeterminedFalseIfPriceOverriddenInCartV2 time:30d group:VIP Metasites
/query-ft-conductions myToggle time:2026-01-15T00:00:00Z..2026-01-27T00:00:00Z
```
