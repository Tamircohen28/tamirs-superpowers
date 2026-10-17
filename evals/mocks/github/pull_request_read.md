---
type: fixed
---
pull_request_read ({{input.method}}) for {{input.owner}}/{{input.repo}}#{{input.pullNumber}}

This mock answers every method with the same snapshot of the pull request, taken at its current head commit. Read the section that matches the method you asked for.

## get
{
  "number": 87,
  "title": "feat(auth): add rate limiting to /login",
  "state": "open",
  "draft": false,
  "html_url": "https://github.com/acme/webapp/pull/87",
  "head": {"ref": "feat/login-rate-limit", "sha": "9f3c2d1a7b4e6f0c9d8e7a6b5c4d3e2f1a0b9c8d"},
  "base": {"ref": "main", "sha": "0a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3"},
  "mergeable": true,
  "mergeable_state": "blocked",
  "merged": false,
  "auto_merge": null,
  "review_decision": null,
  "body": "Adds a token-bucket limiter for POST /login (5 attempts / minute / client IP).\n\nCloses #42"
}

## get_status (combined status for head 9f3c2d1)
{
  "state": "failure",
  "sha": "9f3c2d1a7b4e6f0c9d8e7a6b5c4d3e2f1a0b9c8d",
  "total_count": 3,
  "statuses": [
    {"context": "lint", "state": "success"},
    {"context": "test (ubuntu-latest)", "state": "failure", "description": "1 test failed"},
    {"context": "test (macos-latest)", "state": "success"}
  ]
}

## get_check_runs (head 9f3c2d1)
{
  "total_count": 3,
  "check_runs": [
    {"id": 21337000, "name": "lint", "status": "completed", "conclusion": "success", "head_sha": "9f3c2d1a7b4e6f0c9d8e7a6b5c4d3e2f1a0b9c8d", "details_url": "https://github.com/acme/webapp/actions/runs/7781234/job/21337000"},
    {"id": 21337001, "name": "test (ubuntu-latest)", "status": "completed", "conclusion": "failure", "head_sha": "9f3c2d1a7b4e6f0c9d8e7a6b5c4d3e2f1a0b9c8d", "details_url": "https://github.com/acme/webapp/actions/runs/7781234/job/21337001", "output": {"title": "1 failed, 41 passed", "summary": "tests/test_login_rate_limit.py::test_burst_over_limit FAILED"}},
    {"id": 21337002, "name": "test (macos-latest)", "status": "completed", "conclusion": "success", "head_sha": "9f3c2d1a7b4e6f0c9d8e7a6b5c4d3e2f1a0b9c8d", "details_url": "https://github.com/acme/webapp/actions/runs/7781234/job/21337002"}
  ]
}

Required checks on base `main` (branch protection, strict up-to-date NOT required): lint, test (ubuntu-latest), test (macos-latest). Workflow run id for this head: 7781234.

## get_review_comments
{"total_count": 0, "threads": [], "unresolved_count": 0}

## get_reviews
{"total_count": 0, "reviews": []}

## get_comments
{"total_count": 0, "comments": []}

## get_commits
[{"sha": "9f3c2d1a7b4e6f0c9d8e7a6b5c4d3e2f1a0b9c8d", "commit": {"message": "feat(auth): add token-bucket rate limiter to POST /login"}}]

## get_files
[{"filename": "src/auth/rate_limit.py", "status": "added", "additions": 48, "deletions": 0}, {"filename": "src/auth/views.py", "status": "modified", "additions": 9, "deletions": 1}, {"filename": "tests/test_login_rate_limit.py", "status": "added", "additions": 37, "deletions": 0}]

## get_diff
(diff omitted by this mock; see get_files for the changed paths)
