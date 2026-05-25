---
name: query-captains-log
description: Query Captain's Log for production change events (deployments, migrations, fleet operations, rollbacks)
allowed-tools:
  - Task
---

# Query Captain's Log

## Usage

```
/query-captains-log [artifact: <name>] [origin: <source>] [action: <type>] [company: <name>] [ownershipTag: <tag>] [search: <text>] [user: <name>] [time: <range>]
```

## Instructions

Parse the user's parameters, then delegate to the `captains-log-agent`:

```
Task tool:
  subagent_type: "captains-log-agent"
  description: "Query Captain's Log"
  prompt: "Query Captain's Log with these filters:\n- <param>: <value>\n..."
```

Parameters (all optional, default time: 1h):

| Parameter | Example values |
|-----------|---------------|
| artifact | com.wixpress.bookings.bookings-service |
| origin | Fryingpan, Immigrator, Lifecycle, FeatureToggle, dbCore |
| action | DEPLOY, ROLLBACK, FLEET_CREATED, COMPLETED, updated |
| company | Bookings, Wix Blocks |
| ownershipTag | bookings-service |
| search | free text in description |
| tag | exclude events with this tag |
| user | username |
| time | 1h, 6h, 24h, 7d |

If no parameters provided, pass: "No filters — return all recent events (default 1h)".

Relay the agent's output to the user verbatim.
