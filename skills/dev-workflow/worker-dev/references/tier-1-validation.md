# Tier 1 — worker validation

Read in Step 4 of `worker-dev`, when choosing what to run.

Tier definitions: [`core/policies/validation.md`](../../../../core/policies/validation.md).
Tier 1's goal is narrow and specific: **prove this contribution is sane.** It is
not "prove the repository is healthy" — that is Tier 2 at integration, and
Tier 3 in CI.

## Why not just run everything

Running the full suite in every worker is the failure this tier exists to
prevent. It costs minutes per worker, multiplied by the number of workers; it
fails for reasons unrelated to the task (another worker's in-flight change, a
pre-existing red test) and burns retries on noise; and it makes the *real*
signal — did my change break my area — harder to see. The full run happens once,
where it can actually be interpreted: on the integrated branch.

## Choosing the command

Work down this list and stop at the first that applies to your changed files.

| Change | Run |
|---|---|
| Source file with a sibling test | That test file / that directory's tests |
| New behaviour | The test you just wrote, plus its module's tests |
| Typed language | Typecheck scoped to the package/project you touched |
| Shell script | `shellcheck` on that script, plus executing it |
| JSON/YAML | Parse it (`jq empty`, `yq`, or the repo's schema validator) |
| Markdown/docs only | The repo's docs/link check for those files, if one exists |
| Config that gates the build | The build, once |
| Generated file | The generator, and confirm the diff matches |

Common scoped invocations:

```bash
npm test -- src/auth                    # jest/vitest path filter
npx tsc --noEmit -p packages/auth       # project-scoped typecheck
pytest tests/auth -q                    # directory-scoped
go test ./internal/auth/...             # package-scoped
cargo test -p auth                      # crate-scoped
shellcheck -S warning path/to/script.sh
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
```

## When the repo cannot scope its tests

Some repositories only offer `make test`. Then:

1. run the narrowest thing that exists;
2. if even that is expensive (minutes, network, containers), **skip it** and
   record the skip honestly:

```bash
--validation 'make test|worker|skipped|full suite only; no path filter available — deferred to Tier 2'
```

A recorded skip is fine. A silent skip, or a claimed pass, is not.

## Recording results

Every entry in the handoff's `validation[]` is a command that actually ran, with
its actual result:

```bash
--validation '<command>|worker|pass|<short excerpt>'
--validation '<command>|worker|fail|<the error>'
--validation '<command>|worker|skipped|<why>'
```

A `fail` does not have to mean the task failed — a known-failing test that
belongs to another task's scope can be recorded as `fail` with the explanation
in `summary`. What is never acceptable is omitting it.

## Executable artifacts

For a script, Makefile target, or generated config: type-checking and linting
are not evidence. **Run it** and record its real output. A script that was never
executed has not been validated.

## What Tier 1 never includes

- the full repository suite (unless the task's policy explicitly demands it);
- cross-platform / matrix runs;
- CI workflows executed locally;
- release, publish, or deploy checks;
- performance benchmarks, unless the task *is* a performance task.
