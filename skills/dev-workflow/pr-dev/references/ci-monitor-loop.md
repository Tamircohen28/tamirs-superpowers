# PR CI Monitor Loop

`gh pr checks <N> --watch` blocks until every check finishes, then returns a single result batch. That is fine for a quick wait, but it doesn't emit incremental notifications and it holds the parent agent's turn. For longer CI cycles (10+ minute runs, multiple iterations), prefer the Monitor `until`-loop pattern below: it emits one notification per check as that check leaves `pending`, plus an `ALL-DONE` summary when every check has settled, and the parent stays free to work on other items in parallel.

---

## When to use which

| Situation | Use |
|---|---|
| Quick sanity check, ~1 minute, no other work pending | `gh pr checks <N> --watch` |
| Long CI cycle (5+ min), or you have other work to advance in parallel | The Monitor loop below |
| You want to know *which* check finished and *when* (not just "all done") | The Monitor loop below |

---

## The loop

```bash
prev=""; while true; do
  s=$(gh pr checks <PR> --repo <owner>/<repo> --json name,bucket 2>/dev/null || echo "[]")
  cur=$(jq -r '.[] | select(.bucket!="pending") | "\(.name): \(.bucket)"' <<<"$s" 2>/dev/null | sort)
  comm -13 <(echo "$prev") <(echo "$cur")
  prev=$cur
  jq -e 'length>0 and all(.bucket!="pending")' <<<"$s" >/dev/null 2>&1 && {
    echo "ALL-DONE: $(jq -r 'group_by(.bucket)|map("\(.[0].bucket)=\(length)")|join(" ")' <<<"$s")"
    break
  }
  sleep 30
done
```

Each iteration:

1. Queries `gh pr checks` for the current name/bucket of every check.
2. Computes the set of `(name: bucket)` pairs for checks that have *left* `pending` and prints any line that wasn't in the previous iteration's set — so you see exactly which check just completed and with what verdict.
3. If every check has settled (`bucket != "pending"` for all), prints an `ALL-DONE: <bucket counts>` line and exits.
4. Otherwise sleeps 30 s.

`comm -13 <(echo "$prev") <(echo "$cur")` is "lines present in `cur` but not in `prev`" — the new-since-last-tick deltas.

`bucket` values returned by `gh`: `pending`, `pass`, `fail`, `skipping`, `cancel`. Only `pending` is treated as "still running."

---

## Wrap in Monitor (preferred)

```javascript
Monitor({
  description: "PR #<PR> CI rollup state changes",
  timeout_ms: 1800000,
  command: `
    prev=""; while true; do
      s=$(gh pr checks <PR> --repo <owner>/<repo> --json name,bucket 2>/dev/null || echo "[]")
      cur=$(jq -r '.[] | select(.bucket!="pending") | "\\(.name): \\(.bucket)"' <<<"$s" 2>/dev/null | sort)
      comm -13 <(echo "$prev") <(echo "$cur")
      prev=$cur
      jq -e 'length>0 and all(.bucket!="pending")' <<<"$s" >/dev/null 2>&1 && {
        echo "ALL-DONE: $(jq -r 'group_by(.bucket)|map("\\(.[0].bucket)=\\(length)")|join(" ")' <<<"$s")"
        break
      }
      sleep 30
    done
  `
})
```

Monitor emits a notification per stdout line — so each check transition arrives as a separate notification, and the final `ALL-DONE: pass=10 fail=0` settles the wait. Backslash-escape the `\(...)` jq interpolations and the inner double-quotes inside the JS template literal as shown.

`timeout_ms: 1800000` (30 minutes) is a safe ceiling for slow CI matrices; raise only if you have evidence a specific pipeline runs longer.

---

## After ALL-DONE

```bash
gh pr view <PR> --repo <owner>/<repo> \
  --json mergeable,mergeStateStatus,reviewDecision \
  --jq '{mergeable, mergeStateStatus, reviewDecision}'
```

- `mergeable=MERGEABLE` + `reviewDecision=APPROVED` → ready to merge.
- `reviewDecision=REVIEW_REQUIRED` with green CI → the only blocker is human approval; investigation is done.
- `mergeStateStatus=BEHIND` → rebase needed.
