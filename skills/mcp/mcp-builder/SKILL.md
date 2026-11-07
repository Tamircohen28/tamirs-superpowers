---
name: mcp-builder
description: 'Use when building or scaffolding an MCP (Model Context Protocol) server wrapping a REST API, database, or service as tools for an MCP client. Triggers on: ''build an MCP server'', ''create MCP tools'', ''expose API via MCP'', ''make Claude able to call X'', ''MCP server for Stripe/GitHub/Postgres'', ''wrap this API in MCP'', ''FastMCP server'', ''TypeScript MCP'', ''MCP server for Cursor/Codex/Gemini/OpenCode''. Not for inspecting an existing MCP server, or client config only.'
when_to_use: '''create MCP tools for our Postgres DB'', ''add MCP support for OpenWeatherMap'', ''wire this MCP server into Cursor and Codex too''.'
argument-hint: '[service or API to integrate — e.g. ''GitHub REST API'', ''Stripe'', ''internal Postgres DB'', ''OpenWeatherMap'']'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Read
- Glob
- Grep
- Skill(tamirs-superpowers:mcp-pagination)
- Skill(tamirs-superpowers:platform-sync)
disallowed-tools: []
model: sonnet
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
license: MIT
metadata:
  tamirs:
    visibility: public
    category: mcp
    role: implementer
    validation-tier: 1
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
        - shell
      optional:
        - mcp
    tags:
      - mcp
      - server
      - integration
      - developer-tools
      - portable
  capability: mcp-development
  updated-date: '2026-08-19'
---

# MCP Server Development Guide

## Why this skill exists

Wrapping an external API in an MCP server sounds simple, but naive implementations fail in practice: tools return walls of JSON that exhaust context, list operations return unbounded results that time out, error messages say "400 Bad Request" without guidance, and tool names are so generic (`get`, `list`) that the model picks wrong ones. This guide enforces the patterns — pagination-first, structured output, actionable errors, consistent naming — that make the difference between a server a model can use reliably and one it struggles with.

**MCP is a protocol, not a Claude feature.** The server you build here is host-neutral: the
same stdio or HTTP server is consumed by Claude Code, Claude Desktop, Cursor, Codex CLI,
Gemini CLI, OpenCode and anything else speaking MCP. Nothing in the server implementation
may assume a particular host. What *does* differ per host is the **client config file** that
registers the server — that difference is confined to Phase 6, where it is generated and
validated per target, and it never leaks into the server code.

Throughout this guide, "the client" or "the host" means whichever agent runtime is calling
your tools. Where a passage says Claude, it is naming one client among several, not a
requirement.

## Supporting files

| File | When to use |
|------|-------------|
| `scripts/scaffold.sh` | Run at the start of Phase 2 to generate a project skeleton. Usage: `bash <skill-dir>/scripts/scaffold.sh <name> [ts\|py] [prefix]` (`$CLAUDE_SKILL_DIR` on Claude Code; substitute the skill directory on other hosts) |
| `scripts/gate.sh` | Run before every gated step below (installs, inspector runs, config outside the project). Usage: `bash <skill-dir>/scripts/gate.sh <action-id> '<exact target>'`. See [Permission gates](#permission-gates). |
| `references/permission-gates.md` | Which step maps to which gate action id, headless behaviour, fail-closed rules. |
| `references/tool-templates.md` | Read at the start of Phase 3: the TypeScript and Python tool templates. |
| `references/quick-reference.md` | Read during Phase 1 and Phase 3 for SDK URLs, Zod patterns, annotation hints, return shapes, naming examples, and error message templates. |

At the start of **Phase 2**, run the scaffold script to bootstrap the project, then replace the placeholder tools in Phase 3.

---

## Internal skills

Pagination guardrails live in a companion skill — **do not duplicate or guess limits inline**:

```
Skill("mcp-pagination")
```

`mcp-pagination` is internal-only (`user-invocable: false`). Invoke it with the **Skill tool** whenever this workflow touches list/search operations. It owns limit defaults, cursor conventions, SQL `LIMIT` enforcement, and the pre-ship checklist.

**Invoke `mcp-pagination` when any of these apply:**

| Trigger | Phase |
|---------|-------|
| Planning tool inventory and any endpoint returns a collection | Phase 1 |
| Before writing each `list_*`, `search_*`, or array-returning tool | Phase 3 |
| Before adding or changing SQL-executing tools | Phase 3 |
| After implementing list/search tools — audit against checklist | Phase 4 |
| Eval questions require multi-page fetches — verify caller-driven pagination | Phase 5 |

Skip invocation only when the server has **zero** list, search, or bulk-read operations (e.g. a single `create_*` write tool).

---

## Permission gates

Package installs (`pkg.install.network`), the Inspector (`pkg.exec.network`) and any client config outside the
project (`config.global.write`, R4) are catalog actions ([ADR 004](../../../docs/engineering/decisions/004-permission-levels.md));
the permission resolver, not this guide, decides whether they run. Ask it immediately before the step, with the exact
file or command as the target:

```bash
bash <skill-dir>/scripts/gate.sh <action-id> '<exact target>'     # add --headless when no human is in the chat
```

Act on the exit code, never on your own reading of the situation:

| Exit | Meaning | What you do |
|---|---|---|
| `0` | allow | Run the step exactly as gated. |
| `10` | ask | Show the user the action and the target exactly as the script printed them and wait for an explicit "yes" in chat. Anything else — silence, "sure, whatever you think", a yes to a different command — is a no. |
| `3` | blocked | Do not run it, and do not reach the same effect another way (a different installer, writing the file by hand). Tell the user the printed reason and the setting that would allow it, and give them the command to run themselves. |
| `2` | usage error | Fix the call; never treat it as a pass. |

Running as a subagent, inside a workflow, under `claude -p` or in CI, pass `--headless`: no one can answer an ask
there, so it becomes a block. Which step maps to which action id, and why an earlier "go ahead with everything" never
answers a later ask: [`references/permission-gates.md`](references/permission-gates.md).

---

## Language selection

| Criterion | TypeScript | Python |
|---|---|---|
| Recommended default | Yes | If team is Python-only |
| SDK maturity | High (first-party) | High (FastMCP) |
| Remote HTTP servers | `@modelcontextprotocol/sdk` | FastMCP |
| Local stdio servers | Same SDK | Same SDK |
| Type safety | Static (Zod + tsc) | Pydantic v2 |
| Compilation check | `npm run build` | `python -m py_compile` |

---

## Phase 1 — Research and planning

### 1.1 Load MCP specification and quick reference

Read the bundled quick reference first (URLs, patterns, naming cheat sheet):

```
Read("<skill-dir>/references/quick-reference.md")   # $CLAUDE_SKILL_DIR on Claude Code
```

Then fetch authoritative SDK docs with WebFetch:

```
WebFetch("https://modelcontextprotocol.io/specification/draft.md")
WebFetch("https://modelcontextprotocol.io/docs/concepts/tools.md")
```

**TypeScript SDK:**
```
WebFetch("https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/main/README.md")
```

**Python (FastMCP):**
```
WebFetch("https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/main/README.md")
```

### 1.2 Understand the target API

Review authentication method, rate limits, pagination strategy (cursor vs. offset), and which endpoints map to the most common user tasks. Deprioritize rarely-used admin endpoints.

Catalog every endpoint that returns a collection or supports search — these become list/search tools in Phase 3.

### 1.3 Apply pagination guardrails (mcp-pagination)

If the catalog from 1.2 includes **any** list, search, or bulk-read operation, invoke the internal skill **before** writing tool schemas:

```
Skill("mcp-pagination")
```

Pass the planned tool names and the target API's native pagination params. Apply its Step 1–3 output to your tool design (limit defaults, cursor/offset mapping, safe starting limits). Do not proceed to Phase 3 implementation until pagination strategy is set for every collection endpoint.

---

## Phase 2 — Project setup

### Use the scaffold script

The fastest way to start is the bundled scaffold:

```bash
# TypeScript
bash <skill-dir>/scripts/scaffold.sh my-mcp-server ts myservice

# Python (FastMCP)
bash <skill-dir>/scripts/scaffold.sh my-mcp-server py myservice
```

This generates `package.json` / `requirements.txt`, entry file with two example tools, `README.md` with env var table, and `tsconfig.json` (TS only). The scaffold itself installs nothing. Install dependencies only through the gate below, then replace the placeholder tools in Phase 3.

### Install dependencies — gated, lifecycle scripts off

An install runs its packages' lifecycle scripts or source builds with the user's credentials; default to none:

```bash
# TypeScript — inside the project directory
bash <skill-dir>/scripts/gate.sh pkg.install.network 'npm install --ignore-scripts'
npm install --ignore-scripts          # only after exit 0, or exit 10 and the user's explicit yes

# Python — inside an activated venv
bash <skill-dir>/scripts/gate.sh pkg.install.network 'pip install --only-binary=:all: -r requirements.txt'
pip install --only-binary=:all: -r requirements.txt
```

This stack needs no install scripts, and `--only-binary=:all:` refuses source builds. If a package genuinely needs
its scripts or a build, stop and say which; the run with scripts on is a separate gated step with its own target.

### Manual setup (if scaffold doesn't fit)

**TypeScript:**

```bash
mkdir my-mcp-server && cd my-mcp-server
npm init -y
# gate each install first: bash <skill-dir>/scripts/gate.sh pkg.install.network '<the exact command>'
npm install --ignore-scripts @modelcontextprotocol/sdk zod
npm install --ignore-scripts -D typescript @types/node ts-node
./node_modules/.bin/tsc --init --target ES2022 --module NodeNext --moduleResolution NodeNext --outDir dist --rootDir src --strict
mkdir src
```

**Python:**

```bash
mkdir my-mcp-server && cd my-mcp-server
python -m venv .venv && source .venv/bin/activate
# gate first: bash <skill-dir>/scripts/gate.sh pkg.install.network 'pip install --only-binary=:all: fastmcp pydantic httpx'
pip install --only-binary=:all: fastmcp pydantic httpx
```

---

## Phase 3 — Implement tools

### 3.0 Pagination gate (before each list/search tool)

For **every** tool matching `list_*`, `search_*`, top-level array results, or SQL execution:

1. Invoke `Skill("mcp-pagination")` if not already applied this session for this tool.
2. Implement the limit/cursor/filter params and defaults from its workflow — do not invent your own.
3. Return `next_cursor` (or equivalent) when results are truncated; never auto-fetch page 2+.

The templates below show the expected shape; numeric defaults must match `mcp-pagination` safe ranges for the operation type.

### Naming convention

Use `{service}_{verb}_{noun}` — always action-oriented and unambiguous:

| Good | Bad |
|---|---|
| `github_list_issues` | `get`, `list`, `issues` |
| `stripe_create_payment_intent` | `payment`, `do_payment` |
| `db_query_users` | `query`, `fetch` |

### Tool templates

Start each tool from the TypeScript (`McpServer.registerTool` + Zod) or Python (FastMCP + Pydantic) template in [`references/tool-templates.md`](references/tool-templates.md): a paginated `list` tool with `limit`/`cursor`, `readOnlyHint`, credentials from env, and an actionable error message. Read it before writing the first tool.

---

## Phase 4 — Build and test

```bash
# TypeScript
npm run build          # must pass with zero errors
bash <skill-dir>/scripts/gate.sh pkg.exec.network 'npx @modelcontextprotocol/inspector@2.12.0 dist/index.js'
npx @modelcontextprotocol/inspector@2.12.0 dist/index.js

# Python
python -m py_compile my_server.py
bash <skill-dir>/scripts/gate.sh pkg.exec.network 'fastmcp dev my_server.py'
fastmcp dev my_server.py   # opens Inspector UI (fetches and runs the Inspector)
```

The build and compile checks need no gate. The Inspector runs only after the gate allows it or the user says yes; if
it is blocked, report the build result and say the Inspector check is the user's to run, with the command.

Test each tool in the MCP Inspector before declaring done. The Inspector is host-neutral — it speaks the protocol directly, so a server that passes there works for every client. Check:
- `list_*` tools return `next_cursor` when truncated
- Error messages include the HTTP status, response body snippet, and a suggested fix
- Tool descriptions are concise (under 120 chars for the summary line)

### 4.1 Pagination audit (mcp-pagination)

If the server includes any list/search/SQL tools, invoke:

```
Skill("mcp-pagination")
```

Run its **Quick-reference checklist** against the implemented tool set. Fix every failing item before shipping. Typical failures: missing `limit`, default above 100, auto-pagination in server code, SQL without `LIMIT`.

---

## Phase 5 — Evaluations

Create 10 read-only evaluation questions that require 3+ tool calls to answer. These test the server through the protocol, so they are valid for every host. Format:

```xml
<evaluation>
  <qa_pair>
    <question>How many open issues are labeled 'bug' in the myservice/core repo as of today?</question>
    <answer>42</answer>
  </qa_pair>
</evaluation>
```

Each question must be: independent, read-only, complex (multi-step), realistic, and produce a stable verifiable answer.

If eval scenarios require paginated tools, confirm with `Skill("mcp-pagination")` that evals use explicit limits and caller-driven continuation — not server-side full scans.

---

## Phase 6 — Register the server with each target host

The server is host-neutral. **Registration is not.** Each host reads a different config file
with a different shape, and a server that works perfectly is still unreachable if the config
it is registered in is wrong. Generate config only for the targets the user names. If they
named none, list the candidates (the markers `platform-sync` reads, see
`skills/documentation/platform-sync/references/detection.md`, are a hint for the list, not a
decision) and ask which ones; a detected marker is never consent to write a config.

### 6.0 Project scope by default; anything else goes through the gate

A registered server is a command the host runs on every start, so the entry's location decides who it runs for.

- **Default: project scope** (`.mcp.json`, `.cursor/mcp.json`, `.gemini/settings.json`, `opencode.json`, a project
  `.codex/config.toml`): an ordinary repo edit the user sees in their diff.
- **Outside the project only when the user asks for it** (user-level Claude Code config,
  `claude_desktop_config.json`, anything under the home directory). That is `config.global.write`, R4:

  ```bash
  bash <skill-dir>/scripts/gate.sh config.global.write '<absolute path of the file>'
  ```

  On exit 10, show the file path and the exact entry (name, command, args, env placeholders) and
  write only after an explicit yes. Headless it is always blocked: give the user the entry and the
  file to add themselves.

### 6.1 Check the capability first

Read the `mcp` capability for each target in `core/capabilities/platforms.json`. If a target
marks `mcp` as `unsupported` or `unknown`, do **not** emit a config file for it. Say so:

```
<target>: MCP is <unsupported|not verified> per the capability registry — no config emitted.
```

Never write a config file on the assumption a host supports MCP.

### 6.2 Config shape per target

| Target | Config path | Shape |
|---|---|---|
| Claude Code (project) | `.mcp.json` | `{"mcpServers": {"<name>": {"command", "args", "env"}}}` |
| Claude Code (user) | the user-level config file in the home directory | same `mcpServers` object |
| Claude Desktop | `claude_desktop_config.json` (OS-specific dir) | same `mcpServers` object |
| Cursor | `.cursor/mcp.json` | `{"mcpServers": {...}}` |
| Codex CLI | `.codex/config.toml` (or the path the fetched Codex docs name) | TOML `[mcp_servers.<name>]` table |
| Gemini CLI | `.gemini/settings.json` | `mcpServers` object |
| OpenCode | `opencode.json` | `mcp` object, entries typed `local` (command array) or `remote` (url) |

Shapes drift between releases. **Verify the current shape against the target's live docs**
before writing — the URL lists live in
`skills/documentation/platform-sync/references/platforms/<id>.md`. If you cannot fetch them,
emit the config and label it unverified; do not present a remembered shape as current.

### 6.3 Secrets

Config files carry `${ENV_VAR}` placeholders and nothing else. Never write a literal token
into a config file, in any host's format, even in an example. Document the required
variables in the server README.

### 6.4 Validate what you generated

Per target, run a check that actually parses the file:

```bash
jq empty .mcp.json                 # Claude Code / Cursor / Gemini / Claude Desktop
jq empty .cursor/mcp.json
jq empty .gemini/settings.json
jq empty opencode.json
python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' .codex/config.toml
```

Then confirm the server actually starts under the command the config names:

```bash
# the exact command string from the config's "command" + "args"
node dist/index.js < /dev/null    # stdio server should start and wait, not crash
```

A config that parses but names a wrong path is the most common failure — check that the
command path resolves from the directory the host will launch it in (usually the project
root, not the server directory).

### 6.5 Report honestly

State per target: config written, validated how, and anything unverified. "Works with
Cursor" is a claim that needs the parse check plus the start check behind it — evidence
over declarations.

---

## Hard rules

1. **Never return unbounded lists.** Delegate limit/cursor/filter rules to `mcp-pagination` — invoke it at every trigger in the table above; do not skip for "simple" APIs.
2. **Error messages must be actionable.** Include the HTTP status, a snippet of the response body, and a concrete next step (e.g., "Check the service's auth env var" or "Use a valid repo slug").
3. **Tool names must be unambiguous.** Always use `{service}_{verb}_{noun}` — never single-word names like `list` or `get`.
4. **Never hardcode credentials.** Read tokens from environment variables (`process.env.X` / `os.environ["X"]`) only.
5. **Never auto-paginate server-side.** Fetch one page per tool call; expose cursor/token for the caller to continue (`mcp-pagination` Step 5).
6. **Compilation must pass before shipping.** `npm run build` (TypeScript) or `python -m py_compile` (Python) must exit 0.
7. **Tool descriptions must state what the tool returns**, not just what it does. Bad: "Gets issues." Good: "Returns a paginated list of open GitHub issues with title, labels, and assignee."
8. **Phase 4 pagination audit must pass** before marking the server done.
9. **Never assume a host.** The server implementation must not branch on which client is
   calling it. Host differences belong in Phase 6 config generation only.
10. **Never emit a client config for a target whose `mcp` capability is `unsupported` or
   `unknown`** in `core/capabilities/platforms.json`. Report the gap instead.
11. **Every generated config must be validated** by a parse check and a server-start check
   before you claim the target works.
12. **Gate before you reach outside the project.** Package installs, Inspector runs and any
   client config outside the project directory run only after `scripts/gate.sh` exits 0 or the
   user gives an explicit yes to its exit-10 ask; exit 3 is a stop, not an obstacle to route
   around. Installs default to `--ignore-scripts` / `--only-binary=:all:`.
13. **The server's README and docs follow `rules/dev/documentation-standards.md`.** Every
   human-facing doc ends with the canonical footer (`bash scripts/check-doc-standards.sh --fix`
   when the repo ships it), every diagram is a Mermaid block opening with the canonical init
   line from `config/docs/mermaid-init.txt` — never box-drawing.

---

## What NOT to do

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| Return raw API response JSON as-is | The client reads 50KB of nested objects, wasting context | Filter to the 5–10 fields actually needed |
| Single `api_call(endpoint, method, body)` catch-all tool | The client can't discover what the API supports | Implement explicit tools per operation |
| No pagination — return all results | Times out on large datasets; floods context | Invoke `Skill("mcp-pagination")`; add `limit` + cursor per its checklist |
| `throw new Error("Error")` on API failure | The client retries blindly with no fix | Include status code, body snippet, env var hint |
| Put auth tokens in the source code | Security leak | Use env vars; document required vars in README |
| Skip MCP Inspector testing | Broken tools ship silently | Always run Inspector before marking done |
