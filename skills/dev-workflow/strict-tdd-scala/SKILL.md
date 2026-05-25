---
name: strict-tdd-scala
description: STRICT Test-Driven Development for Scala/Loom Prime. Forces Red-Green-Refactor cycle. Will NOT write implementation code before a failing test exists.
allowed-tools:
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Bash(bazel:*)
  - Bash(/usr/local/bin/bazel:*)
  - TaskCreate
  - TaskUpdate
---

# Scala TDD Skill (Strict)

STRICT Test-Driven Development workflow for Scala services using Specs2, Mockito, and Loom Prime. This skill enforces the Red-Green-Refactor cycle without exceptions.

## Usage
```
/tdd-scala <feature-or-bug-description>
```

## Arguments
- `$ARGUMENTS` - Description of the feature to implement or bug to fix

## STRICT ENFORCEMENT RULES

**These rules are NON-NEGOTIABLE:**

1. **NO IMPLEMENTATION WITHOUT A FAILING TEST** - You MUST write a test first and see it fail before writing ANY implementation code
2. **RED PHASE IS MANDATORY** - Every test MUST be run and MUST fail before proceeding
3. **ONE TEST AT A TIME** - Write one test, see it fail, implement, see it pass, repeat
4. **NO SHORTCUTS** - Do not skip the Red phase even for "obvious" implementations
5. **TRACK EVERY STEP** - Use TaskCreate/TaskUpdate to track the TDD cycle meticulously

## Instructions

### Step 1: Understand & Plan

1. Parse `$ARGUMENTS` to understand the requirement
2. If unclear, ask clarifying questions - DO NOT PROCEED with assumptions
3. Create a task list with test cases to implement (use TaskCreate):
   ```
   - [ ] Write test: [test case 1 description]
   - [ ] Run test (must fail - RED)
   - [ ] Implement minimal code (GREEN)
   - [ ] Refactor if needed
   - [ ] Write test: [test case 2 description]
   - ... repeat for all cases
   ```

### Step 2: Locate Test Infrastructure

Find existing test files and patterns:
```scala
// Look for TestContextBuilder
*TestContextBuilder.scala

// Test directories (both hold unit tests for prime_app)
src/test/scala/...  // Unit tests (shorter timeout)
it/scala/...        // Unit tests (extended timeout for slower tests)
// Note: Difference is only test timeout configuration, not test type
```

### Step 3: Write the Failing Test (RED)

Create or update the test file using this structure:

```scala
import org.specs2.execute.AsResult
import org.specs2.mock.Mockito
import org.specs2.mutable.SpecWithJUnit
import org.specs2.specification.Scope
import scala.concurrent.{ExecutionContext, Future}

class MyFeatureTest(implicit ee: ExecutionEnv) extends SpecWithJUnit with Mockito {

  "MyFeature" should {
    "expected behavior description" in new Ctx {
      // Given - setup preconditions
      val input = SomeRequest(id = "test-id")
      givenDependencyReturns(expectedData)

      // When - execute the action
      val result = service.doSomething(input)

      // Then - verify outcome
      result must beEqualTo(expectedOutput)
    }
  }

  trait Ctx extends Scope {
    implicit val callScope: CallScope = TestCallScope()
    val contextBuilder = MyServiceTestContextBuilder()
    val service = contextBuilder.blockingPlatformized(services.myService)

    // Mock helpers - ALWAYS use given* prefix for readability
    // Prefer givenXxxExists pattern for entity setup
    def givenBookingExists(id: String, booking: Booking) =
      contextBuilder.rpc.bookings.get(any)(any) returns Future.successful(booking)

    def givenDependencyReturns(data: Data) =
      contextBuilder.rpc.dependency.method(any)(any) returns Future.successful(data)

    def givenFeatureToggleEnabled() =
      contextBuilder.featureToggle.mock.toggleName() returns true
  }
}
```

**Test Writing Rules:**
- Use descriptive test names that explain the behavior
- Follow Given-When-Then pattern strictly
- One assertion per test when practical
- Use `given*` prefix for mock setup methods (prefer `givenXxxExists` pattern)
- Mock external dependencies via `contextBuilder.rpc`
- Use `blockingPlatformized` - it automatically awaits async results (no need for `Await`)
- Use Mockito matchers (`any`, `anyString`, etc.) for flexible argument matching

### Step 4: Run the Test (VERIFY RED)

**THIS STEP IS MANDATORY - DO NOT SKIP**

```bash
/usr/local/bin/bazel test //path/to:target_test_runner --test_timeout=30000
```

**The test MUST fail.** Report to the user:
- The test name
- The failure reason
- Confirmation this is the expected failure

If the test passes unexpectedly:
- STOP and investigate
- Either the feature exists or the test is wrong
- DO NOT proceed to implementation

### Step 5: Implement Minimal Code (GREEN)

**ONLY AFTER CONFIRMING THE TEST FAILS:**

1. Write the MINIMUM code to make the test pass
2. NO extra features, NO optimizations, NO "while I'm here" additions
3. Follow existing patterns in the codebase

**Scala Guidelines:**
- Use `Future` for async operations - NEVER use `Await.result` or `Thread.sleep`
- Use `Option` instead of null
- Use pattern matching where appropriate
- For parallel execution:
  ```scala
  import com.wix.bookings.common.futures.FutureUtil

  val futureA = fetchA()
  val futureB = fetchB()
  for { a <- futureA; b <- futureB } yield (a, b)

  // Or
  FutureUtil.inParallel(futureA, futureB)
  ```
- Use AutoMapper for entity conversions:
  ```scala
  import com.wixpress.automapper.dsl.v2.all._
  domain.mapTo[EntityApi]
  ```
- Use appropriate exceptions:
  - `WixValidationRuntimeException` - input validation
  - `WixApplicationRuntimeException` - business logic errors

### Step 6: Run the Test (VERIFY GREEN)

```bash
/usr/local/bin/bazel test //path/to:target_test_runner --test_timeout=30000
```

**The test MUST pass now.**

If it fails:
- Analyze the failure
- Fix the implementation (NOT the test, unless the test is genuinely wrong)
- DO NOT move to the next test until this one passes

Report to the user:
- Confirmation the test passes
- Mark the task as completed (use TaskUpdate)

### Step 7: Refactor (Optional)

ONLY refactor if:
- There's obvious code duplication
- Names can be more descriptive
- Logic can be simplified without changing behavior

After refactoring, run the test again:
```bash
/usr/local/bin/bazel test //path/to:target_test_runner --test_timeout=30000
```

### Step 8: Repeat

For each additional test case:
1. Create task for next test case
2. Go back to Step 3 (Write the Failing Test)
3. Continue the cycle

### Step 9: Final Verification

Run ALL related tests:
```bash
/usr/local/bin/bazel test //path/to/package:..._test_runner --test_timeout=30000
```

Ensure no regressions.

## Mocking Hierarchy (Preferred to Least Preferred)

1. **ContextBuilder RPC Mocks** (PREFERRED):
   ```scala
   contextBuilder.rpc.serviceName.method(any)(any) returns Future.successful(response)
   ```

2. **Feature Toggle Mocks**:
   ```scala
   contextBuilder.featureToggle.mock.toggleName() returns true
   ```

3. **Mockito Mocks** (when no RPC mock exists):
   ```scala
   val mockDep = mock[Dependency]
   mockDep.method(any) returns result
   ```

## Common Test Matchers

```scala
result must beEqualTo(expected)           // Exact match
result must beEntity(expected)            // Entity comparison
result must beSuccessful(expected)        // Success with value
result must throwA[ExceptionType]         // Exception expected
result must beSome(expected)              // Option contains value
result must beNone                        // Option is empty
result must contain(element)              // Collection contains
result must haveSize(n)                   // Collection size
```

## VIOLATIONS - DO NOT DO THESE

- Writing implementation before a failing test
- Skipping the Red phase for "simple" changes
- Writing multiple tests before running any
- Implementing more than needed to pass the current test
- Modifying tests to pass instead of fixing implementation
- Using `Await.result`, `Await.ready`, or `Thread.sleep`
- Adding features not covered by tests

## Examples

```
/tdd-scala Add validation that booking names cannot be empty
/tdd-scala Fix: Booking creation fails when schedule timezone is null
/tdd-scala Implement rate limiting for calendar sync - max 100 per minute
```