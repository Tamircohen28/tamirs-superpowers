# Configuring find-skill's search sources

find-skill's source list is **data**, not a list written into the skill. Adding a registry,
removing one you do not trust, or pointing the skill at a private catalogue is a config
change — it must never require editing `SKILL.md`.

## Resolution order

find-skill loads the **first** of these that exists and parses, and uses it alone (later
files are not merged into earlier ones — a full override is easier to reason about than a
partial one):

1. `$FIND_SKILL_SOURCES` — path to a JSON file, when the environment variable is set.
2. `.find-skill/sources.json` in the current repo — project-scoped source list, checked in.
3. `~/.config/find-skill/sources.json` — the user's personal list, applied to every repo.
4. `<skill-dir>/references/sources.json` — the bundled default, shipped with this skill.

Report which file answered, in the run's opening line:

```
Searching 7 sources from ~/.config/find-skill/sources.json for "python code review" —
returning top 5 ranked by match + quality.
```

A user who has overridden the sources needs to see that their override took effect. A user
who has not needs to see which defaults they got.

## File shape

See `references/sources.json` for the canonical example. Each entry:

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Stable slug, used in the failed-source footnotes |
| `name` | yes | Human-readable name shown in output |
| `kind` | yes | `registry`, `catalog`, or `search` |
| `enabled` | yes | `false` skips the source without deleting the entry |
| `covers` | yes | Any of `skills`, `plugins`, `mcp`, `agents` — used to prioritise per query |
| `query` | yes | `{ "tool": "WebFetch" \| "WebSearch", "url" \| "query": "…{query}…" }` |
| `fallback` | no | Used when the primary returns an empty or client-rendered shell |
| `notes` | no | Shown in the caveats section when the source lands in the top 3 |

`{query}` is substituted with the user's parsed intent, URL-encoded for `WebFetch`.

`defaults.min_sources` is the floor for a trustworthy answer. If fewer than that many
sources are enabled **or** reachable, the result is labelled degraded — the number is
configurable, the honesty about falling below it is not.

## Adding a private or internal registry

Add an entry to a project or user-scoped file, never to the bundled default:

```json
{
  "id": "internal-registry",
  "name": "Internal skill registry",
  "kind": "registry",
  "enabled": true,
  "covers": ["skills", "mcp"],
  "query": { "tool": "WebFetch", "url": "https://registry.internal.example/search?q={query}" }
}
```

**Never put a credential in this file.** If a source needs auth, it belongs behind a proxy
or a fetch tool that supplies the credential from the environment — the source list is
checked into repos and shared.

## Removing a source

Set `"enabled": false` rather than deleting the entry, so the reason stays visible in the
diff and the source can be restored. If disabling drops the enabled count below
`defaults.min_sources`, find-skill still runs and still labels the result degraded.
