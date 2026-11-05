# Reference

The skill catalog now lives in **[Skills](skills.md)** — every skill by domain, with the role
it plays and the validation tier it runs.

- Roles and specialist agents: [Agents](agents.md)
- What your platform supports: [Platform differences](platform-differences.md)
- Frontmatter contract: [engineering/architecture/skill-schema.md](../engineering/architecture/skill-schema.md)

## Documentation standards

Every human-facing page — `README.md` and everything under `docs/`, except the agent guidelines and
the changelogs — ends with the same centred footer: **Have a Question?** links to the maintainer's
profile and **Open an Issue** links to this repository's new-issue page. Every diagram is a Mermaid
block drawn in one dark theme: dark fills, white text, no per-node styling. Both are data in
`config/docs/` and checked by `make check-doc-standards`; `bash scripts/check-doc-standards.sh --fix`
appends a missing footer or inserts the theme line, so nobody types either by hand. The rule, with
the waiver for a different palette: [Documentation standards](../../rules/dev/documentation-standards.md).

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
