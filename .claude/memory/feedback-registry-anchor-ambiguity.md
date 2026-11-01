---
name: feedback-registry-anchor-ambiguity
description: "In platforms.json a platform name and a validation string each appear many times — anchor string edits on something provably unique, then check a neighbour was untouched"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a35855d6-d668-42fb-af0b-d574c2b896ae
  modified: 2026-09-23T11:29:00.921Z
---

`core/capabilities/platforms.json` reuses strings that look like unique anchors and are not:

- a platform name is **both** an array element (`"codex",` in the platforms list) **and** an
  object key (`"codex": {`)
- a capability id like `"slash_commands"` exists once **per platform** — five times
- `"validation": "...check-manifest-declares.sh .cursor-plugin/plugin.json skills"` appears in
  **three different rows**

So `s.index(needle)` reliably finds the wrong occurrence. This bit three times in one session.

**Why it matters more than an ordinary typo:** `str.replace()` on a non-matching anchor is a
**silent no-op**. The file is rewritten unchanged, the success message prints, and the edit is
reported as done. That is indistinguishable from success unless something checks.

**How to apply:**
1. Anchor on something provably unique — an object key with its brace (`'"codex": {'`), or the
   row's own long `notes` text — then walk backwards with `rindex` to the short field.
2. `assert s.count(old) == 1` **before** every replace, and assert the expected old value is
   present. This caught all three occurrences with zero damage.
3. Afterwards, print a **neighbour** that should NOT have changed (e.g. the `skills` row's
   validation when editing `slash_commands`'). Hitting the wrong one of three identical strings
   otherwise looks exactly like success.
4. Never `json.dump` the file — see [[feedback-json-manifest-edits]]; it un-escapes all 27
   `—` sequences and rewrites untouched lines.
5. Remember the file has 36 rendered copies: run
   `bash skills/repo/_contract/scripts/sync-contract-scripts.sh` after any edit, or the contract
   gate fails. See [[feedback-probe-narrow-before-full-gate]].
