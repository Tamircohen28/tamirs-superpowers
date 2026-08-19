# `default-trunk` — repository whose default branch is neither `main` nor `master`

**Represents:** a third spelling that does not exist in the current fleet.

**Covers:** the failure mode the first two fixtures cannot catch — code that
handles the branch name by testing `main`/`master` and falling back, rather than
by never looking at it. Any such implementation passes `default-main` and
`default-master` and fails here.

**Contents:** identical to `default-main` except `default_branch: trunk`.
