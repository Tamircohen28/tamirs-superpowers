---
name: fix-flaky-test
description: Fix flaky tests by analyzing errors, removing flaky tags from BUILD files, and fixing test code. Use when tests are marked flaky or failing intermittently.
allowed-tools:
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Bash(bazel:*)
  - Bash(/usr/local/bin/bazel:*)
  - Bash(buildozer:*)
  - Bash(git:*)
  - Bash(wt-*:*)
  - Bash(MAIN_REPO=*:*)
  - Bash(cd:*)
  - Bash(pwd:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Task
  - TaskCreate
  - TaskUpdate
  - TaskList
  - TaskGet
  - Skill
---

# Fix Flaky Test Skill

Fix flaky tests by analyzing test errors, removing flaky tags from BUILD files, and fixing the test code itself.

## Usage
```
/fix-flaky-test <test-error-or-test-path>
```

## Arguments

`$ARGUMENTS` can be:
- Test error output (stack trace, assertion failure)
- Test class path (e.g., `//bookings-backend/service:MyTestSpec`)
- Multiple test errors separated by `---`

## Workflow Overview

1. **Create worktree FIRST** - Use `/wt new` for isolated work (MANDATORY)
2. **Parse input** - Extract test class name(s) and error details
3. **Use subagent to research** - ALWAYS spawn an Explore agent to investigate the root cause
4. **Create tasks** - Track progress when fixing multiple tests
5. **For each test:**
   - Find the BUILD file
   - Remove `flaky = True` tag if present
   - Fix the test code (NOT implementation code)
6. **Verify fix** - Run the test to confirm it passes
7. **Commit changes** - Use `/commit` to push the fix

## Instructions

### Step 1: Create Worktree Session (MANDATORY FIRST STEP)

**CRITICAL**: You MUST create a worktree BEFORE doing any research or making any changes. This is NON-NEGOTIABLE.

Use the `/wt` skill to create a new worktree session:

```
Skill(skill="wt", args="new fix-flaky-<test-name> \"Fix flaky test <test-name>\"")
```

**DO NOT proceed with any other steps until the worktree is created and you have changed to it.**

### Step 2: Parse Test Errors

Extract from `$ARGUMENTS`:
- Test class name (e.g., `MyServiceSpec`, `BookingServiceTest`)
- Test method name if available
- Error type (assertion failure, timeout, null pointer, etc.)
- Package/path information

**Pattern recognition:**
```
# Scala test path
//path/to/package:TestClassSpec

# Java test path
//path/to/package:TestClassTest

# Stack trace
at com.wixpress.bookings.MyServiceSpec.should handle request(MyServiceSpec.scala:45)

# Assertion failure
Expected: 5
     but: was 3
```

### Step 3: Research Root Cause with Subagent (MANDATORY)

**CRITICAL**: You MUST use a Task subagent to research the problem. Do NOT read files directly yourself for investigation.

Spawn an Explore agent to investigate:

```
Task(subagent_type="Explore", prompt="Investigate the flaky test failure:

Error: <paste error details here>

Research tasks:
1. Find the test file based on the stack trace
2. Find the BUILD.bazel file for the test
3. Check if there's a flaky tag
4. Read the test code and understand what it's testing
5. Identify the code paths involved in the failure
6. Look for common flaky patterns:
   - Random data generation
   - Timezone/DST handling
   - Async timing issues
   - Shared mutable state
   - Order-dependent tests

Report back:
- Test file location
- BUILD file location
- Whether flaky tag exists
- Root cause analysis
- Recommended fix approach")
```

Wait for the subagent to complete its research before proceeding.

### Step 4: Create Tasks for Multiple Tests

If multiple tests are being fixed, create a task for each:

```
TaskCreate: Fix flaky test MyServiceSpec
TaskCreate: Fix flaky test BookingServiceTest
```

Mark each task as `in_progress` when starting work on it.

### Step 5: Remove Flaky Tag

Based on the subagent's findings, remove the flaky tag if present:

```bash
buildozer 'remove flaky' //package:target_name
```

Or if the test uses `tags = ["flaky"]`:

```bash
buildozer 'remove tags flaky' //package:target_name
```

### Step 6: Fix the Test Code

**CRITICAL**: Only modify test code, NOT implementation code.

Common fixes for flaky tests:

#### Timing Issues
```scala
// Bad: Fixed timing
Thread.sleep(100)
result must beEqualTo(expected)

// Good: Eventually matcher
eventually {
  result must beEqualTo(expected)
}
```

#### Async Code
```scala
// Bad: Immediate assertion
service.doAsync()
verify(mock).wasCalled()

// Good: Await completion
service.doAsync().await
verify(mock).wasCalled()
```

#### Order-Dependent Tests
```scala
// Bad: Relies on execution order
"test 1" should { sharedState = "a" }
"test 2" should { sharedState must beEqualTo("a") }

// Good: Independent setup
"test 2" should {
  val state = setupFreshState()
  state must beEqualTo("a")
}
```

#### Random/Non-Deterministic Data
```scala
// Bad: Random data can hit edge cases
val id = UUID.randomUUID().toString
service.process(id) // May fail for certain UUID patterns

// Good: Controlled test data
val id = "test-id-12345"
service.process(id)
```

#### Timezone/DST Issues
```scala
// Bad: Random timezone can hit DST gaps
val timezone = aRandomTimezone
val time = dateTime.withZone(zone).toLocalDateTime

// Good: Use safe hours (noon) or fixed timezone
val safeTime = dateTime.withHourOfDay(12).withMinuteOfHour(0)
// Or use UTC
val timezone = "UTC"
```

#### Shared State
```scala
// Bad: Tests share state
class TestSpec {
  val service = new Service() // Shared across tests
}

// Good: Fresh state per test
class TestSpec {
  trait Ctx {
    val service = new Service() // Fresh per test
  }
  "test" in new Ctx { ... }
}
```

### Step 7: Run the Test

Verify the fix by running the test multiple times:

```bash
# Run test once
/usr/local/bin/bazel test //package:target_test_runner --test_timeout=30000

# Run multiple times to verify no flakiness (optional)
for i in {1..3}; do /usr/local/bin/bazel test //package:target_test_runner --test_timeout=30000 || exit 1; done
```

### Step 8: Mark Task Complete

If using tasks, update the task status:

```
TaskUpdate: taskId=X, status=completed
```

### Step 9: Commit Changes

Use the commit skill:

```
/commit fix-flaky-<test-name>
```

The commit message should include:
- Which test was fixed
- What the flakiness cause was
- What was changed to fix it

Example:
```
fix flaky MyServiceSpec test

The test was flaky due to timing-dependent assertions.
Changed to use eventually matcher for async result verification.

#automerge
```

## Common Flaky Test Patterns

| Pattern | Symptom | Fix |
|---------|---------|-----|
| Timing | Works sometimes | Use `eventually`, increase timeouts |
| Async | Race conditions | Properly await futures |
| Order | Fails when run alone | Make tests independent |
| Random | Certain inputs fail | Use deterministic test data |
| State | Fails on re-run | Fresh context per test |
| External | Network-dependent | Mock external services |
| Timezone | DST transitions | Use safe hours (noon) or UTC |

## Examples

### Single Test Fix
```
/fix-flaky-test //bookings-backend/service:BookingServiceSpec - test fails with timeout
```

### Multiple Tests
```
/fix-flaky-test
Test 1: BookingServiceSpec.should handle concurrent requests - timeout after 5s
---
Test 2: CalendarSyncSpec.should sync events - assertion failed: expected 3 but got 2
```

### From Stack Trace
```
/fix-flaky-test
java.lang.AssertionError:
Expected: is <true>
     but: was <false>
	at com.wixpress.bookings.MyServiceSpec.should validate input(MyServiceSpec.scala:127)
```

## Important Rules

1. **ALWAYS create worktree FIRST** - This is mandatory before any research
2. **ALWAYS use subagent for research** - Do not read/grep files directly for investigation
3. **Only modify test code** - Never change implementation to fix a flaky test
4. **Remove flaky tag** - If present in BUILD file
5. **Verify the fix** - Run test after changes
6. **Use tasks for multiple tests** - Track progress
7. **Commit with context** - Explain what was flaky and how it was fixed

## Anti-Patterns (DO NOT DO)

```
❌ Research the problem without creating a worktree first
❌ Read test files directly instead of using a subagent
❌ Modify implementation code to make test pass
❌ Add Thread.sleep() to "fix" timing issues
❌ Skip the test or mark it as ignored
❌ Increase flaky retry count instead of fixing
❌ Work directly in main repo without worktree
```

## Correct Pattern

```
✅ Create worktree FIRST (mandatory)
✅ Use Explore subagent to research root cause
✅ Find and remove flaky tag from BUILD
✅ Fix test code with proper patterns
✅ Run test to verify fix
✅ Commit with descriptive message
```
