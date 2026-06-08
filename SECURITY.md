# Security Policy

## Scope

This repository contains Markdown skill files, Bash hook scripts, and JSON configuration. It does not run a server, store user data, or handle authentication.

**In scope for reports:**
- Shell injection vulnerabilities in hook scripts (`hooks/*.sh`)
- Secrets accidentally committed to the repository
- Skills that instruct Claude to execute dangerous commands without user confirmation

**Out of scope:**
- Vulnerabilities in Claude Code itself (report to Anthropic)
- Vulnerabilities in MCP servers declared in `.mcp.json` (report to the respective npm package maintainer)

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Email: open a private [GitHub Security Advisory](https://github.com/Tamircohen28/tamirs-superpowers/security/advisories/new) instead.

Include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fix

I aim to acknowledge reports within 48 hours and resolve confirmed issues within 14 days.

## Hook script security model

The hook scripts run in your local shell with your user privileges. They:
- Never transmit data to external services
- Read/write only within `~/.claude/` and the current git repo
- Do not store credentials

The MCP server stubs in `.mcp.json` use `${ENV_VAR}` placeholders — actual tokens are never committed.
