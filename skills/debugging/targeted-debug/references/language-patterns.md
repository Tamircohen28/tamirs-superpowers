# Language-Specific Stack Trace Patterns

Quick reference for applying targeted-debug scope rules to traces from each language/runtime.

## Rust

**Panic format:**
```
thread 'main' panicked at 'reason', src/module/file.rs:42:10
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: myapp::module::function
             at src/module/file.rs:42:10
   3: myapp::main
             at src/main.rs:15:5
```

**In-scope:** Lines with `at src/...` pointing into the project source tree.
**Out-of-scope:** Frames from `core::`, `std::`, `tokio::`, and paths under `~/.cargo/registry/`. These are runtime internals — do not read them.

**Common panics and their in-scope evidence:**
| Panic message | What to look for in the file |
|---|---|
| `called \`Option::unwrap()\` on a \`None\` value` | The `.unwrap()` call on the named line — what returns Option? |
| `called \`Result::unwrap()\` on an \`Err\` value` | Same pattern — the `.unwrap()` call site, what error was produced |
| `index out of bounds: the len is N but the index is M` | Array/Vec indexing on the named line |
| `attempt to subtract with overflow` | Arithmetic on the named line — was the subtraction checked? |
| `explicit panic` / `unreachable!()` | The `panic!`/`unreachable!` macro call — what branch triggered it? |

**Path extractor behavior:** Rust frames look like `at src/module/file.rs:42:10` — the extractor's vim-style pattern (`path:line`) will match these correctly. Cargo registry paths (`/root/.cargo/registry/...`) will also be extracted but should be filtered out as they are vendor code.

---

## Go

**Panic format:**
```
goroutine 1 [running]:
panic: runtime error: invalid memory address or nil pointer dereference

goroutine 1 [running]:
main.(*MyStruct).MethodName(0xc0000b4000, ...)
        /app/pkg/service.go:114 +0x1c2
main.handlerFunc(...)
        /app/handlers/handler.go:52 +0x8f
```

**In-scope:** Lines with tab-indented absolute paths inside the project source tree (e.g., `/app/pkg/service.go`).
**Out-of-scope:** Go stdlib paths (`/usr/local/go/src/...`), goroutine scheduler frames (`runtime/...`), and frames from `/home/<user>/go/pkg/mod/` (vendor cache).

**Common panics and their in-scope evidence:**
| Panic message | What to look for |
|---|---|
| `invalid memory address or nil pointer dereference` | On the named line — which pointer/interface/map is being dereferenced? Was it initialized? |
| `assignment to entry in nil map` | Map literal or map returned from a function — was it initialized with `make()`? |
| `slice bounds out of range` | Slice index or slice expression on the named line — is the length checked before access? |
| `interface conversion: interface is nil, not T` | Type assertion on the named line — is the interface guaranteed non-nil? |
| `send on closed channel` | Channel write on named line — trace who closes the channel and whether it races |

**Path format:** Go frames are tab-indented below the goroutine function line: `\t/absolute/path.go:line +0xoffset`. The `+0xoffset` is the PC offset and should be ignored.

**Goroutine context:** The goroutine header (`goroutine N [running]:`) is metadata — it tells you *which goroutine* panicked (e.g., HTTP handler goroutine vs. background worker). Note this in the hypothesis if it's informative (e.g., "panic in a request-handling goroutine suggests this is triggered by a specific request pattern").

---

## Rust vs. Go disambiguation

Both Rust and Go use absolute paths in traces. If unsure which you're reading:
- Rust frames: `at path/to/file.rs:line:col` — always has column number
- Go frames: `\tpath/to/file.go:line +0xaddr` — tab-indented, has hex offset

---

## Bash / Shell

**Error format:**
```
script.sh: line 42: VARNAME: unbound variable
/path/to/deploy.sh: line 17: command not found
```

**Common errors and their causes:**
| Error pattern | Mechanism |
|---|---|
| `VARNAME: unbound variable` | `set -u` (nounset) — variable referenced without being set |
| `command not found` | PATH issue, missing dependency, or typo in command name |
| `syntax error near unexpected token` | Unmatched quote, brace, or parenthesis in the named file |
| `exit status 1` (with no message) | Command failed silently — check the line before `exit 1` for the actual failure |

**Scope rule:** The filename in `script.sh: line N` is always in scope. Sourced files (`source helper.sh`, `. lib.sh`) are out of scope unless the trace explicitly names them.

---

## Reading the extractor output for these languages

After running `extract-error-paths.sh`, you may see vendor/stdlib paths mixed in. Apply this filter before building your in-scope file set:

**Always exclude:**
- Paths starting with `/root/.cargo/` or `~/.cargo/` (Rust vendor cache)
- Paths starting with `/home/<user>/go/pkg/mod/` (Go module cache)
- Paths starting with `/usr/local/go/src/` (Go stdlib)
- Paths containing `node_modules/` (JS/TS)
- Paths ending in `.class` or `.jar` (JVM bytecode — unreadable)

**Keep everything else** — project source paths, relative paths, and absolute paths inside the repo.
