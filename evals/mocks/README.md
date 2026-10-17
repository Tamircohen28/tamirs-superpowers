# MCP mocks for the eval suite

Stand-ins for the plugin's one MCP server, `github` (declared in `.mcp.json`, started by
`scripts/github-mcp.sh`), so the dev-workflow cases can read an issue, a pull request's
checks and a failed job's log without a token, a network, or a real repository. Layout and
semantics are the ones [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals#mock-mcp-servers)
defines: one file per tool under `mocks/<server>/<tool>.md`, the body is what the tool
returns, `{{input.<field>}}` echoes a call argument.

## What is here

| File | Answers | Used by |
|---|---|---|
| `github/get_me.md` | The authenticated user | any case; the server's own guidance says to call it first |
| `github/issue_read.md` | Issue `acme/webapp#42` — "Add rate limiting to the /login endpoint" | `10-start-dev-from-issue` |
| `github/pull_request_read.md` | PR `acme/webapp#87` at head `9f3c2d1`: `lint` and `test (macos-latest)` green, **`test (ubuntu-latest)` failing**, zero unresolved threads | `12-pr-dev-drive-to-green` |
| `github/get_job_logs.md` | The failed job's tail: `test_burst_over_limit` expected 429, got 200 | `12-pr-dev-drive-to-green` |
| `github/merge_pull_request.md` | `error: true` — 405, required check failing | `12` grades that this is **never called** |
| `github/create_pull_request.md` | `error: true` — 403, not available in this suite | `10`/`11` grade that this is **never called** |

Every mock is `type: fixed`, so the answer is deterministic, costs no model call, and needs no
`.replay/` recording. `pull_request_read` takes a `method` argument that selects what the real
server returns; a fixed mock cannot branch on it, so its body carries the whole snapshot with
one section per method and tells the caller to read the matching one.

The mock tools are exposed to the agent under test as
`mcp__plugin_tamirs-superpowers_github__<tool>`, which is the name the `tool_used` graders
in cases 10–12 match. They need no `--allow-tools` grant.

## What is deliberately not here

- **`expect:` guards.** They would let a case assert what the skill asked the server for, but
  a violated guard aborts the run with score 0, and without `_tools.json` (below) the agent
  sees only placeholder schemas, so a mis-guessed argument name would read as a plugin failure.
  The graders check behaviour (which tools were called, what the reply says) instead.
- **`_tools.json`.** The real server's `tools/list` response, which would give the mocked tools
  their real descriptions and input schemas. Not captured yet. To capture it, start the real
  server once with a token and save the `result` object of a `tools/list` request:

  ```bash
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"capture","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)" bash scripts/github-mcp.sh \
  | jq -c 'select(.id == 2) | .result' > evals/mocks/github/_tools.json
  ```

  Commit the result beside the tool files. Mocked tools then carry the real `owner`/`repo`/
  `pullNumber`/`method` schemas, and `expect:` guards become safe to add.
- **`.replay/` recordings.** Only `type: agent` mocks produce them (the judge model answers as
  the server, and the answer is saved under `results/<timestamp>/mock-recordings/` for
  adoption). This suite has none. If one is ever added — for example a `_server.md` that
  answers `pull_request_read` per `method` instead of the fixed snapshot — record it with a
  keyed run, then copy the recording the run's `ADOPT.txt` names into
  `evals/mocks/.replay/github/` and commit it, so CI answers the identical call without a
  model call:

  ```bash
  claude plugin eval . --case 12-pr-dev-drive-to-green --runs 1 --ablation none \
    --mocks record --allow-tools Write
  cat evals/results/<timestamp>/mock-recordings/ADOPT.txt
  ```

  `--allow-real-servers` on top of `--mocks record` starts the real `github` server for any
  tool that has no mock file (as you, outside the sandbox — it needs the token and a
  `--allow-tools "mcp__plugin_tamirs-superpowers_github__*"` grant); use it only to compare
  a mock's shape against the real answer, never in CI.

## The "server unavailable" path

Two situations put the agent in front of no GitHub at all, and the cases are written so that
both are graded on behaviour rather than failing outright:

1. **The without-plugin arm.** The `github` server belongs to the plugin, so the no-plugin
   baseline has neither the server nor its mocks. Every grader that can only pass with the
   mocked data (`reads-issue`, `reads-checks`, the `tool_used: Skill` indicators) is marked
   `arm: with-only`, which the harness reports as a plugin-fired indicator and leaves out of
   the score in both arms. The scored graders in cases 10–12 accept an honest "I could not
   read X from here; this is what I would read" and fail a fabricated issue, check name,
   merge or push.
2. **`--mocks off` without a token**, or a tool with no mock file. The tool is absent or the
   real server refuses to start, which is the same path as (1) from the agent's point of view.

So a negative Δ on cases 10–12 means the plugin made the agent *less* honest or *more* likely
to merge/open a PR on a red or unvalidated change — a real finding — while a Δ near zero with
the indicators passing means the flow ran and the baseline was honest too. See the suite
[`README`](../README.md#github-dependent-cases-and-mocks).
