# Code review findings — payments service

1. `src/payments/charge.ts:88` — unhandled promise rejection when the provider times out.
2. `src/payments/charge.ts:120` — retry loop has no cap; can spin forever on a 5xx.
3. `src/payments/refund.ts:42` — refund amount is not validated against the original charge.
4. `src/api/routes/payments.ts:15` — missing auth check on `POST /payments/refund`.
5. `src/api/routes/payments.ts:60` — error responses leak the provider's raw message to the client.
6. `src/db/models/payment.ts` — `amount` stored as float; should be integer minor units.
7. `src/db/models/payment.ts` — no index on `(customer_id, created_at)`; the ledger query is a full scan.
8. `src/payments/**` — the whole module mixes provider SDK calls with business logic; needs a gateway interface extracted.
9. `tests/payments/` — no test covers a declined card.
10. `tests/payments/` — no test covers a duplicate webhook delivery.
11. `docs/payments.md` — documents the old `chargeCard()` signature.
12. `.github/workflows/ci.yml` — the payments test suite is excluded from CI.
