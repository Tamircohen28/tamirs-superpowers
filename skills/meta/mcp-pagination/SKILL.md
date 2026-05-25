---
name: mcp-pagination
description: When using MCP tools that support pagination (Jira, Slack, Google Calendar, Trino, GitHub, etc.), ALWAYS include pagination parameters. Use this skill whenever working with list/search MCP operations to enforce mandatory pagination.
---

# MCP Pagination - MANDATORY

**CRITICAL:** When calling ANY MCP tool that supports pagination, you MUST include pagination parameters. This is not optional or situational.

## Tools Requiring Pagination

| Tool | Parameter | Start Limit |
|------|-----------|------------|
| `mcp__jira__get-issues` | `maxResults` | 10-20 |
| `mcp__slack__slack_list_channels` | `limit` | 50-100 |
| `mcp__slack__slack_get_channel_history` | `limit` | 10-20 |
| `mcp__google-calendar__list-calendars` | `pageToken` | N/A (use for continuation) |
| `mcp__octocode__githubSearchCode` | `limit` | 5-10 (max 20) |
| `mcp__octocode__githubSearchRepositories` | `limit` | 5-10 (max 20) |
| `mcp__octocode__githubSearchPullRequests` | `limit` | 5-10 (max 10) |
| `mcp__trino__execute-trino-sql-query` | SQL `LIMIT` clause | Required |
| `mcp__gradual-feature-release__query-feature-toggles` | `limit` | 10-50 |
| `mcp__gradual-feature-release__list-releases` | `limit` | 10-50 |

## MANDATORY Pattern

Before making ANY MCP call from the table above, verify you're including pagination:

### ❌ Anti-Patterns (NEVER DO THIS)
```
mcp__jira__get-issues with projectKey="MY-PROJECT"
mcp__slack__slack_list_channels
mcp__octocode__githubSearchRepositories with keywordsToSearch=["auth"]
mcp__google-calendar__list-calendars with timeMin=... timeMax=...
```

### ✅ Correct Patterns (ALWAYS DO THIS)
```
mcp__jira__get-issues with projectKey="MY-PROJECT" maxResults=10
mcp__slack__slack_list_channels with limit=50
mcp__octocode__githubSearchRepositories with keywordsToSearch=["auth"] limit=10
mcp__google-calendar__list-calendars with pageToken="<token>" (if fetching next page)
mcp__trino__execute-trino-sql-query with sql="SELECT * FROM table LIMIT 100" description="..."
```

## Alternative Pagination Strategies

When official pagination parameters don't exist or aren't sufficient, use these filtering techniques to limit result sets:

### 1. Date/Time Filtering
Narrow results by time window instead of fetching everything:

```
# Jira - filter by date range
jql="project = MY-PROJECT AND created >= -7d"
jql="project = MY-PROJECT AND updated >= 2024-01-01 AND updated <= 2024-01-31"

# GitHub PRs - filter by date
created=">2024-01-01"
updated=">=2024-06-01"
merged-at="2024-01-01..2024-01-31"

# Slack - use oldest/latest timestamps
oldest="1704067200"  # Unix timestamp
latest="1706745600"

# Calendar - always use timeMin/timeMax
timeMin="2024-01-01T00:00:00Z"
timeMax="2024-01-31T23:59:59Z"
```

### 2. Owner/Author Filtering
Filter by specific users to reduce scope:

```
# Jira
jql="project = MY-PROJECT AND assignee = currentUser()"
jql="project = MY-PROJECT AND reporter = 'john.doe'"

# GitHub
author="username"
assignee="username"
involves="username"
reviewed-by="username"

# Slack
from="<@USER_ID>"
```

### 3. Status/State Filtering
Only fetch what's relevant:

```
# Jira
jql="project = MY-PROJECT AND status = 'In Progress'"
jql="project = MY-PROJECT AND resolution = Unresolved"

# GitHub PRs
state="open"        # or "closed"
merged=true         # only merged PRs
draft=false         # exclude drafts

# Feature toggles
status="ACTIVE"     # or "INACTIVE", "ARCHIVED"
```

### 4. Label/Category Filtering
Use labels or categories to narrow scope:

```
# Jira
jql="project = MY-PROJECT AND labels = 'bug'"
jql="project = MY-PROJECT AND component = 'backend'"

# GitHub
label="bug"
label=["bug", "priority-high"]  # multiple labels
```

### 5. Path/Scope Filtering
Limit to specific areas:

```
# GitHub code search
path="src/api"
extension="ts"
filename="config"

# Repository search
owner="wix"
repo="specific-repo"
```

### 6. Sorting + Limit Combo
Sort to get most relevant first, then limit:

```
# GitHub - most recent first
sort="updated"
order="desc"
limit=10

# Jira
jql="project = MY-PROJECT ORDER BY updated DESC"
maxResults=10

# Feature toggles
sortField="modifiedDate"
sortOrder="desc"
limit=10
```

## Combining Strategies

For best results, combine multiple filtering strategies:

```
# Example: Recent bugs assigned to me
mcp__jira__get-issues
  jql="project = MY-PROJECT AND assignee = currentUser() AND type = Bug AND updated >= -30d ORDER BY updated DESC"
  maxResults=20

# Example: Recent merged PRs in specific path
mcp__octocode__githubSearchPullRequests
  owner="wix"
  repo="my-repo"
  state="closed"
  merged=true
  merged-at=">=2024-01-01"
  limit=10
```

## Enforcement Rules

1. **BEFORE calling any list/search MCP tool**: Check if it's in the table above
2. **IF it's in the table**: ALWAYS add the pagination parameter
3. **IF official pagination doesn't exist**: Use date/owner/status filtering to limit scope
4. **IF you need more results**: Only fetch additional pages after examining the first page
5. **NEVER**: Call a paginated MCP tool without any limiting strategy

## Why This Matters

- **Token efficiency**: Large result sets can consume 10-100x more tokens
- **Performance**: Smaller queries return faster
- **Relevance**: Filtered results are more likely to be useful
- **Cost**: Fewer tokens = lower API costs

## Default Starting Limits

When in doubt, use these:
- **Search APIs** (GitHub, code search): Start with 5-10
- **Jira/Trino queries**: Start with 10-20
- **Slack channels/events**: Start with 50-100
- **Calendar/Feature toggles**: Start with 10-50

Never exceed the "max" values listed in the tools table above.
