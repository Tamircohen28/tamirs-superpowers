# `default-master` — repository whose default branch is `master`

**Represents:** the minority case in the measured fleet — 4 of 19 repos, this
plugin's own repository among them.

**Covers:** the same requirement as `default-main` from the other side. A test
that runs a scenario against both directories and gets byte-identical request
bodies has proven the policy is branch-name agnostic; a test that runs only one
of them has proven nothing, because a hardcoded default would still pass.

**Contents:** identical to `default-main` except `default_branch: master`.
