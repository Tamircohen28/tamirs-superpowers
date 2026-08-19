# `conflict` — the read succeeds, the write returns 409

**Represents:** a drifted repo (identical to `drifted`) where someone else
changed the ruleset between our read and our write, so the update collides.

**Covers:** the write-side failure path, which no read-only fixture reaches.
`plan` succeeds and promises an update; `apply` issues the `PUT` and it fails.
The run must report that repo as `blocked` with the 409 reason and carry on to
the next one — a fleet run must not abort on repo 3 of 19 — and the final exit
status must still be non-zero so the failure is not silently absorbed.

**Contents:** identical to `drifted`, plus an `errors.txt` scoped to
`PUT repos/*/*/rulesets/*` so reads stay green and only the mutation fails.
