# org-drift

Both canonical rulesets already exist at organization level.

* `Default Branch - Safety` (40000001) is exactly what the renderer produces —
  the up-to-date case, so "no-op" is proven by content rather than asserted.
* `Default Branch - PR & CI` (40000002) drifts in the two dimensions that only
  exist at org level and in one that does not:
  `enforcement: evaluate` (not enforcing), and
  `repository_name.include: ["ppfa-*"]` instead of `~ALL` — coverage narrowed,
  which is invisible in a rules diff because the rules are identical and only
  the set of repositories they apply to changed.
