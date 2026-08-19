# Capturing a hand-edit back into the repo

`scripts/setup.sh` renders the repo onto your machine. `scripts/capture-config.sh`
is the inverse: it proposes what you changed by hand back into the repo, as a
reviewed pull request.

It answers one question: **"I tuned something by hand — make it permanent, and
available on every platform and every machine."**

```bash
make capture                              # review this machine's differences
bash scripts/capture-config.sh detect     # look, change nothing
bash scripts/capture-config.sh deliver    # branch + commits + a PR body
```

---

## Why this is a separate command

Rendering only ever writes files this repo authored, so it needs no judgement.
Capture reads files **a person edited** — which means it can pick up a
credential, a path that exists only on your laptop, or another tool's wiring.
So every value that crosses the boundary is classified, scanned, and shown
before it can land, and it lands as a PR you review. Capture never commits
silently and never merges.

---

## The three verbs

| Verb | What it does | Writes? |
|---|---|---|
| `detect` | diffs your machine against what the repo would render, prints a classified change set | never |
| `review` | `detect`, then asks about each offerable hunk, stages the ones you accept into the **canonical source**, and shows what they render to on every other platform | the repo working tree only |
| `deliver` | runs `make validate`, creates `capture/<date>-<slug>`, one commit per platform touched, writes a PR body | git, locally |

`detect` is the default. `deliver` does **not** push and does **not** open the
PR — it prints the `gh pr create` command and hands off to `/pr-dev`.

---

## Classification

Every difference carries exactly one class. This is the part worth reading
before you trust the tool.

| Class | Meaning | What happens |
|---|---|---|
| `portable` | policy that should be true on every machine — a permission rule, a model choice | **offered** |
| `machine-local` | true here only — absolute paths, trusted-project lists, onboarding state | skipped |
| `secret` | credentials, tokens, anything token-shaped | **refused** — never offered, and the value is never printed, not in the table, not in the diff, not in `--json` |
| `third-party` | wiring another tool owns | skipped, with the owner named |
| `unknown` | no rule covers this key path | **asked** |

Only `portable` and `unknown` are ever put to you. Everything else is reported
and skipped without a question, which is what keeps the review short enough to
actually read.

Which key paths are portable and which are machine state is declared per
platform in `platforms/<target>/capture.conf` — data, not code. Adding a
platform to capture is adding that file.

---

## The review loop

Each offerable hunk is shown as a diff, then:

```
Adopt into the repo? [y/N/a/q/s]
```

- `y` adopt this one
- `N` **skip — the default**, including on a bare return
- `a` adopt this and everything remaining
- `q` stop here, keeping what you already adopted
- `s` show more context (the surrounding object or lines), then ask again

Prompts read `/dev/tty`, never stdin, so capture is safe to invoke from a hook
or a script. **With no terminal it prints the change set and adopts nothing.**
To adopt without a terminal you must name the hunks explicitly:

```bash
bash scripts/capture-config.sh review --adopt 3,7
```

An explicit list is a decision. There is no `--yes`.

---

## Where an adopted hunk goes

Never into a platform file. Always into the **canonical source** the renderers
read, so one adoption reaches all five targets:

| Captured from | Lands in | Then renders to |
|---|---|---|
| a rule in `~/.claude/CLAUDE.md` | `core/global-rules.md` | Claude Code, Codex `AGENTS.md`, Gemini `GEMINI.md`, Cursor `.mdc`, OpenCode `AGENTS.md` |
| a permission in `~/.claude/settings.json` | `platforms/claude/settings.d/permissions-allow.json` | Claude Code `settings.json` |
| `model`, `effortLevel`, `theme` | `platforms/claude/settings.d/defaults.json` | Claude Code `settings.json` |
| a Gemini or OpenCode setting | `platforms/<t>/templates/` | that platform |

`review` runs the renderers again after staging and prints the downstream diff,
so you see the full blast radius before you agree to anything. A platform whose
render does not move is named too, with the capability registry's word for why —
silence would be indistinguishable from "we forgot".

---

## The safety gates

All blocking, all per hunk. A hit blocks **that hunk**, not the run.

1. **The IP scan.** The repo's own `skills/repo/_contract/scripts/ip-scan.sh`
   runs over every hunk. Its built-in patterns are shape-based; the
   employer/internal-hostname half is site-specific, so you supply it:

   ```bash
   # one-off
   TAMIRS_EMPLOYER_PATTERN='\bmycorp-internal\b' make capture

   # permanent
   ~/.config/tamirs-superpowers/scan-patterns.txt   # one extended regex per line
   ```

2. **Secrets are refused, not skipped.** A token-shaped value never reaches the
   offer list and is never printed. An env var *reference* — `${GITHUB_TOKEN}` —
   is portable and is captured as the name, which is exactly what belongs in
   the repo.

3. **Absolute paths are demoted.** `/Users/<you>/...` in a value reclassifies
   the hunk as `machine-local` no matter which key it sits under. This is the
   route by which a foreign path would otherwise arrive in a public repo.

4. **`_`-prefixed keys are stripped** from the machine side. The repo's own JSON
   fragments carry `_comment` to explain themselves; that documentation must
   never round-trip back in as data.

5. **`make validate` must pass** before `deliver` creates anything.

You can add your own owner list for the `third-party` class:

```
~/.config/tamirs-superpowers/third-party-owners.txt
# <extended regex>	<owner name>      (tab separated)
```

---

## Machine-readable output

```bash
bash scripts/capture-config.sh detect --json | jq '.summary'
```

`--json` puts the document on stdout and the human report on stderr. A `secret`
hunk appears in it with `machine_value: null` — a machine-readable refusal that
still carried the credential would not be a refusal.

---

## Flags

| Flag | Effect |
|---|---|
| `--targets a,b` | restrict to these targets |
| `--only <module>` | restrict to one module; matches `x` and `x-*` |
| `--adopt <ids>` | adopt these hunk ids without prompting (`all` for every offerable one) |
| `--json` | machine-readable change set on stdout |
| `--verbose`, `-v` | detailed logging to stderr |

---

## See also

- [setup.md](setup.md) — the other direction
- [configuration.md](configuration.md) — what lives where in the repo
- `platforms/<target>/capture.conf` — the classification data for one platform
- `tests/test-capture.sh` — every gate above, pinned
