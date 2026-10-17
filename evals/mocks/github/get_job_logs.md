---
type: fixed
---
Logs for failed job 21337001 "test (ubuntu-latest)" (workflow run 7781234, head 9f3c2d1), last lines:

============================= test session starts ==============================
collected 42 items

tests/test_login_rate_limit.py::test_allows_under_limit PASSED
tests/test_login_rate_limit.py::test_burst_over_limit FAILED
tests/test_login_rate_limit.py::test_window_resets PASSED

=================================== FAILURES ===================================
____________________________ test_burst_over_limit _____________________________
    def test_burst_over_limit(client):
        for _ in range(5):
            assert client.post("/login", json=BAD_CREDS).status_code == 401
        resp = client.post("/login", json=BAD_CREDS)
>       assert resp.status_code == 429
E       AssertionError: expected 429, got 200
tests/test_login_rate_limit.py:29: AssertionError
========================= 1 failed, 41 passed in 3.18s =========================
##[error]Process completed with exit code 1.
