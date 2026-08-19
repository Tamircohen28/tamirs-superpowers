# `unprocessable` — the create request is rejected 422

**Represents:** GitHub accepting the request shape but rejecting its content —
an unknown rule type, a malformed `conditions` block, or a required status check
naming an `integration_id` the repo cannot use.

**Covers:**
- **The 422 envelope is structured.** Unlike the other statuses it carries an
  `errors` array (`{"resource":"Ruleset","code":"invalid","field":"rules"}`).
  Error reporting that prints only `.message` gives the user "Validation Failed"
  and nothing else; the useful part is in `.errors`.
- **A malformed canonical policy is caught at apply time.** This is the fixture
  that proves the tool reports *which field* GitHub objected to.

**Contents:** `errors.txt` scoped to `POST repos/*/*/rulesets` over an otherwise
greenfield repo (`rulesets.json` is `[]`), so the failing call is the create.
