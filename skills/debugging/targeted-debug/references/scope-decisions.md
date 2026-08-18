# Scope Decisions — In-Scope vs. Out-of-Scope

Examples of how to apply the targeted-debug hard rules in real situations.

## Example 1 — Java NullPointerException

**User input:**
> "Why is this failing? `at com.example.scheduler.BookingService.confirm(BookingService.java:142)` — caused by NullPointerException"

**In scope (read these):**
- `BookingService.java` — the file in the trace, around line 142

**Out of scope (do NOT read):**
- Other services in the scheduler package
- Tests for BookingService
- Callers of `confirm()` elsewhere in the repo

**Out-of-scope follow-ups (note in report):**
- "If the null came from a caller, we'd need to read that caller. Suggest the user paste the surrounding stack frames."

## Example 2 — Python AttributeError with module path

**User input:**
> "AttributeError: 'NoneType' object has no attribute 'split'  
>   File "/repo/src/parser.py", line 87, in parse  
>   File "/repo/src/cli.py", line 23, in main"

**In scope:**
- `/repo/src/parser.py` line 87
- `/repo/src/cli.py` line 23

**Out of scope:**
- Other modules under `/repo/src/`
- Tests

## Example 3 — User-named files

**User input:**
> "Look at `tooling/release/release.sh` — why does it fail when VERSION is empty?"

**In scope:**
- `tooling/release/release.sh` — the file the user named

**Out of scope:**
- Other scripts under `tooling/`
- Files that `release.sh` sources or calls (unless the user adds them)

If reading `release.sh` reveals that the failure is in a sourced helper, the
hypothesis section should say so and the report's "Out-of-scope follow-ups"
should name the helper file the user could add to scope.

## Example 4 — Empty / vague input ("debug this")

**User input:**
> "Something's broken with bookings, can you look?"

**Action:** Stop. Ask the user for an error message, stack trace, or specific
file. This skill cannot operate without concrete evidence — that's the point.

If the user replies "no, just figure it out," say that a broad-exploration
session is the right tool and hand the request back, instead of stretching
this skill's scope. There is no `/investigate` skill in this plugin — do not
name one; describe the kind of session that is needed and let the user or the
orchestrator choose the tool.

## Example 5 — Stack trace that crosses a service boundary

**User input:**
> "Booking confirms fail with HTTP 500. Logs say:  
>   `at PaymentClient.charge(PaymentClient.java:88)`  
>   `at BookingService.confirm(BookingService.java:142)`"

**In scope:**
- `PaymentClient.java` line 88
- `BookingService.java` line 142

**Out of scope:**
- The actual payment-service code (different repo / artifact)
- Logs beyond what the user pasted

The right move is to read the two in-scope files, hypothesize, and note in
"Out-of-scope follow-ups": "If the root cause is in payment-service, the user
needs a broad-exploration session with access to that repo for cross-service
evidence." Don't try to hop to another repo silently, and don't name a
command that does not exist.

## Decision rule (when in doubt)

Ask: **did the user explicitly name this file or did the stack trace
literally print this path?** If yes → in scope. If no → out of scope. If
borderline → ask the user before reading.
