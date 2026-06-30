# OpenAI Codex CLI — URL Master List

All URLs this skill is permitted to use as sources. Every response MUST be grounded
exclusively in content fetched from these URLs. No hallucination. No prior knowledge.

---

## Changelog & Releases

| Priority | Topic | URL |
|---|---|---|
| P0 | GitHub Releases (versioned changelog) | https://github.com/openai/codex/releases |
| P0 | Raw README (canonical feature list) | https://raw.githubusercontent.com/openai/codex/main/README.md |

---

## Documentation

| Priority | Topic | URL |
|---|---|---|
| P1 | Main Repository (rendered README) | https://github.com/openai/codex |
| P1 | AGENTS.md specification | https://github.com/openai/codex/blob/main/AGENTS.md |
| P2 | Contributing / Architecture | https://github.com/openai/codex/blob/main/CONTRIBUTING.md |

---

## Priority Legend

- **P0** — Always fetch for version/changelog-aware responses
- **P1** — Fetch when topic is directly relevant to the query
- **P2** — Fetch only when specifically asked or when P1 sources are insufficient

## Notes

The OpenAI Codex CLI is open-source on GitHub. All authoritative documentation lives in
the repository itself (README, AGENTS.md, releases). There is no separate hosted docs site.
If a fetch returns a 404, the file may not exist yet — report this rather than guessing.
