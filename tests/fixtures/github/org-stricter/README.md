# org-stricter

An organization ruleset that already imposes MORE than canonical: two approving
reviews, CODEOWNERS review, approval of the last push, and strict "branch must
be up to date". Reused from the `org-conflict` scenario's measured shape.

Canonical must never be written over it. The expected behaviour is CONFLICT,
named, and the organization left alone — at organization level most of all,
because one such ruleset governs every repository in the org at once.
