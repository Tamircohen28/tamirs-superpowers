---
name: run-bazel-tests
description: Run specific Bazel test classes or methods with filtering. Use when running targeted tests instead of full test suites.
allowed-tools:
  - Bash(bazel:*)
  - Bash(/usr/local/bin/bazel:*)
---

# Run Specific Bazel Tests

Use this skill to run specific test classes or methods in Bazel.

## Usage
```
/run-bazel-test <test-path> [class-name] [method-name]
```

## Arguments
- `test-path` - Path to the test package (e.g., `bookings-backend/services-2`)
- `class-name` - Optional test class name filter (e.g., `DuplicateSlugsFixerTest`)
- `method-name` - Optional test method description filter (e.g., `fix duplicate slugs`)

## Instructions

When the user wants to run a specific test:

1. **Find the correct test target** by querying available test runners:
   ```bash
   /usr/local/bin/bazel query "kind('.*_test', //path/to/package/...)" 2>/dev/null | grep test_runner
   ```

   Common target naming patterns:
   - `<package>_prime_it_test_runner` - Integration tests (in `it/` directory)
   - `<package>_prime_generated_tests_test_runner` - Unit tests (in `test/` directory)

2. **Derive the fully qualified class name (FQCN)** from the test target path:
   - The target path contains the package structure after `it/` (for integration tests) or `test/` (for unit tests)
   - Replace `/` with `.` in the path portion after `it/` or `test/`
   - Append the class name
   - Example: target `//module/it/com/wixpress/bookings/v2/create:create_test_runner` → FQCN: `com.wixpress.bookings.v2.create.ClassName`

3. **Run with test filter** using FQCN format:
   ```bash
   /usr/local/bin/bazel test //path:target_test_runner \
     --test_filter=com.wixpress.package.ClassName# \
     --test_timeout=30000
   ```

4. **For a specific test method**, append the method name after `#`:
   ```bash
   /usr/local/bin/bazel test //path:target_test_runner \
     --test_filter=com.wixpress.package.ClassName#methodName \
     --test_timeout=30000
   ```

## Useful Flags

| Flag | Description |
|------|-------------|
| `--test_output=all` | Show all test output |
| `--test_output=errors` | Show only failed test output (default) |
| `--nocache_test_results` | Force re-run, skip cache |
| `--runs_per_test=N` | Run test N times (flakiness check) |
| `--test_timeout=30000` | Set timeout in seconds |

## Examples

```bash
# Run all tests in a specific class
/usr/local/bin/bazel test //bookings-backend/services-2/it/com/wixpress/bookings/services2:services2_test_runner \
  --test_filter=com.wixpress.bookings.services2.DuplicateSlugsFixerTest# \
  --test_timeout=30000

# Run a specific test method
/usr/local/bin/bazel test //bookings-backend/services-2/it/com/wixpress/bookings/services2:services2_test_runner \
  --test_filter=com.wixpress.bookings.services2.DuplicateSlugsFixerTest#fixDuplicateSlugs \
  --test_timeout=30000

# Run with full output and skip cache
/usr/local/bin/bazel test //bookings-backend/bookingsV2/bookings-service/it/com/wixpress/bookings/bookings/v2/create:create_test_runner \
  --test_filter=com.wixpress.bookings.bookings.v2.create.CreateCourseBookingTest# \
  --test_timeout=30000 \
  --test_output=all \
  --nocache_test_results
```

## Important Notes

- Always use the fully qualified class name (FQCN) with `#` suffix for the test filter
- Use `ClassName#` to run all tests in a class, `ClassName#methodName` for a specific method
- Always include `--test_timeout=30000` for integration tests
- Derive the FQCN from the test target path: replace `/` with `.` in the path after `it/` or `test/`