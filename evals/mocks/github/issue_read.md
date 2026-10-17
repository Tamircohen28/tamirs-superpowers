---
type: fixed
---
issue_read ({{input.method}}) for {{input.owner}}/{{input.repo}}#{{input.issue_number}}

{
  "number": 42,
  "title": "Add rate limiting to the /login endpoint",
  "state": "open",
  "html_url": "https://github.com/acme/webapp/issues/42",
  "labels": [{"name": "enhancement"}, {"name": "security"}],
  "assignees": [],
  "milestone": null,
  "has_parent": false,
  "has_children": false,
  "closed_by_pull_requests": {"total_count": 0, "references": []},
  "comments": 0,
  "body": "Brute-force attempts against POST /login are not throttled.\n\n**Acceptance criteria**\n- At most 5 attempts per minute per client IP; the 6th within the window returns HTTP 429 with a Retry-After header.\n- In-memory token bucket is fine for now (single instance); no new dependencies.\n- Covered by tests in tests/test_rate_limit.py.\n\nNot blocked by anything. Branch from main."
}
