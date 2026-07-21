---
name: feedback-json-manifest-edits
description: Bump a plugin.json version with a targeted string replace, not a json.dump/jq full rewrite
metadata:
  type: feedback
---

To change a single field (e.g. `version`) in `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, or `.cursor-plugin/plugin.json`, use a **targeted string replacement** on that one line — never a full round-trip through `json.dump` (or `jq '.version=...'` writing the whole file back).

**Why:** a `python json.dump` round-trip defaults to `ensure_ascii=True`, which rewrote the em-dash in the description as its 6-character ASCII escape (`—` becomes the literal text `\u2014`) and reformatted the whole file, turning a 1-line version bump into a noisy diff that had to be reverted and redone.

**How to apply:** replace only the version line, and do all three manifests together (the version-sync constraint fails CI if they disagree):

```python
for f in (".claude-plugin/plugin.json", ".codex-plugin/plugin.json", ".cursor-plugin/plugin.json"):
    with open(f, encoding="utf-8") as fh:
        s = fh.read()
    s = s.replace('"version": "1.8.0"', '"version": "1.8.1"', 1)
    with open(f, "w", encoding="utf-8") as fh:
        fh.write(s)
```

Then confirm the diff touches only the version lines (`git diff --stat`). Bumping the version at all is subject to [[reference-release-tag-alignment]] — don't bump on a docs-only change.
