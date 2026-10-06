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
# MIN = how many REQUIRED checks must be registered before "all settled" means anything: the
# number of required checks from resolve-merge-policy.sh (`required_checks | length`), or 0 if none.
# The exit status is NOT the signal: gh exits 8 while checks are pending (and non-zero when one
# failed), with valid JSON on stdout. Only output that is not a JSON array is an API error.
MIN=<min-checks>; prev=""; errs=0; while true; do
  s=$(gh pr checks <PR> --repo <owner>/<repo> --json name,bucket 2>/dev/null)
  if ! jq -e 'type=="array"' <<<"$s" >/dev/null 2>&1; then
    errs=$((errs+1)); [ "$errs" -eq 3 ] && echo "API-ERROR: gh pr checks returned no state 3 times in a row; unknown, still waiting"
    sleep 30; continue
  fi
  errs=0
  cur=$(jq -r '.[] | select(.bucket!="pending") | "\(.name): \(.bucket)"' <<<"$s" 2>/dev/null | sort)
  comm -13 <(echo "$prev") <(echo "$cur")
  prev=$cur
  # Settled = the REQUIRED checks are all registered and none is pending, and nothing at all is pending.
  r=$(gh pr checks <PR> --repo <owner>/<repo> --required --json name,bucket 2>/dev/null)
  jq -e 'type=="array"' <<<"$r" >/dev/null 2>&1 || r='[]'
  if jq -e --argjson min "$MIN" 'length>=$min' <<<"$r" >/dev/null 2>&1 \
     && jq -e 'length>0 and all(.bucket!="pending")' <<<"$s" >/dev/null 2>&1; then
    echo "ALL-DONE: $(jq -r 'group_by(.bucket)|map("\(.[0].bucket)=\(length)")|join(" ")' <<<"$s")"
    break
  fi
  sleep 30
done
```

Each iteration:

1. Queries `gh pr checks` for the current name/bucket of every check. **The exit status is not the signal**: `gh` exits 8 while checks are pending and non-zero when one failed, with valid JSON either way. Only output that is not a JSON array (a GitHub 5xx, a network error) is **unknown, never done**: it is retried, and three in a row print one `API-ERROR` line so a long outage is visible instead of silent.
2. Computes the set of `(name: bucket)` pairs for checks that have *left* `pending` and prints any line that wasn't in the previous iteration's set — so you see exactly which check just completed and with what verdict.
3. If at least `MIN` **required** checks are registered (`--required`) and no check is pending, prints an `ALL-DONE: <bucket counts>` line and exits. Counting required checks by identity matters right after a push: GitHub registers checks over the first seconds, and a few optional checks that already passed would otherwise satisfy a plain total-count floor before any required check exists.
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
    MIN=<min-checks>; prev=""; errs=0; while true; do
      s=$(gh pr checks <PR> --repo <owner>/<repo> --json name,bucket 2>/dev/null)
      if ! jq -e 'type=="array"' <<<"$s" >/dev/null 2>&1; then
        errs=$((errs+1)); [ "$errs" -eq 3 ] && echo "API-ERROR: gh pr checks returned no state 3 times in a row; unknown, still waiting"
        sleep 30; continue
      fi
      errs=0
      cur=$(jq -r '.[] | select(.bucket!="pending") | "\\(.name): \\(.bucket)"' <<<"$s" 2>/dev/null | sort)
      comm -13 <(echo "$prev") <(echo "$cur")
      prev=$cur
      r=$(gh pr checks <PR> --repo <owner>/<repo> --required --json name,bucket 2>/dev/null)
      jq -e 'type=="array"' <<<"$r" >/dev/null 2>&1 || r='[]'
      if jq -e --argjson min "$MIN" 'length>=$min' <<<"$r" >/dev/null 2>&1 \\
         && jq -e 'length>0 and all(.bucket!="pending")' <<<"$s" >/dev/null 2>&1; then
        echo "ALL-DONE: $(jq -r 'group_by(.bucket)|map("\\(.[0].bucket)=\\(length)")|join(" ")' <<<"$s")"
        break
      fi
      sleep 30
    done
  `
})
```

Monitor emits a notification per stdout line — so each check transition arrives as a separate notification, and the final `ALL-DONE: pass=10 fail=0` settles the wait. Backslash-escape the `\(...)` jq interpolations and the inner double-quotes inside the JS template literal as shown.

`timeout_ms: 1800000` (30 minutes) is a safe ceiling for slow CI matrices; raise only if you have evidence a specific pipeline runs longer.

A Monitor that reaches its timeout with no output tells you nothing: was CI slow, or hung? When the watch expires, read the state once (`gh pr checks`, or the run's job list) before re-arming, and say which it was. For a watch over a *local* gate log rather than CI, add a no-progress clause: if the log file has not been written for 5 minutes, print `STALLED` with its last line and exit, so a hang surfaces instead of a silent expiry.

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

**Automated reviewers lag the checks.** A bot reviewer (for example the Codex connector) often posts 5-10 minutes *after* CI is green. While it is working it shows a 👀 reaction on the PR (match it by the `[bot]` login suffix: the API reports such app users as `type: "User"`, so a `type=="Bot"` filter finds nothing); once it posts its review the 👀 is removed, so read the review and its threads; a 👍 with no review means it found nothing. Before merging, read **all pages** of the reactions (the endpoint returns 30 per page, so a later 👀 can sit on page 2) and wait (bounded) while one is 👀, then re-read unresolved threads:

```bash
gh api --paginate repos/<owner>/<repo>/issues/<PR>/reactions \
  | jq -rs 'add // [] | [.[] | select(.user.login | endswith("[bot]")) | "\(.user.login): \(.content)"] | join(", ")'
```

Merging while it is still 👀 is how a valid finding lands on an already-merged PR and needs a follow-up.

**A reviewer may not re-review on push.** The Codex connector reviews when a PR is opened, marked ready, or someone comments `@codex review` — not when you push. After pushing fixes for its findings there is no 👀 and no new review, so "no 👀" would pass the gate with the fix itself unreviewed. Comment `@codex review` after a fix push, then wait (bounded) until its summary comment shows a completed review for the new head commit.
