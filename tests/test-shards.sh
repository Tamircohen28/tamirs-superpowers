#!/usr/bin/env bash
# test-shards.sh — the SHARD=i/n partition of `make test-hooks` is total, disjoint,
# deterministic, loud on a bad value, and the Makefile runs exactly what
# scripts/ci/shard-suites.sh lists.
#
# WHY A HERMETIC TREE
#   The Makefile agreement cases run the real `test-hooks` recipe, which would run
#   the real suites — including this one, recursively. So the recipe runs against a
#   copy of the Makefile and the shard script in a temp tree whose "suites" are stubs
#   that log their own name, and whose real-home witness is a stub that logs each
#   call. That proves the two things the partition on the real tree cannot: the
#   Makefile consumes the script's list rather than its own `find`, and the witness
#   still brackets every suite inside a shard.
#
# Usage: bash tests/test-shards.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require make awk find sort

SHARD_SH="$REPO_ROOT/scripts/ci/shard-suites.sh"
cd "$REPO_ROOT" || exit 1

# shards <n> [root] — concatenate shards 1..n, in shard order.
shards() {
  local n="$1" root="${2:-$REPO_ROOT}" i
  for i in $(seq 1 "$n"); do bash "$SHARD_SH" "$i/$n" "$root"; done
}

# ---------------------------------------------------------------------------
section "usage and bad values"

judge "-h exits 0" 0 "$(bash "$SHARD_SH" -h >/dev/null 2>&1; echo $?)"
judge "-h prints usage" yes "$(has "$(bash "$SHARD_SH" -h 2>&1)" "Usage:")"
judge "--help prints an example" yes "$(has "$(bash "$SHARD_SH" --help 2>&1)" "make test-hooks SHARD=")"
judge "no argument exits 2" 2 "$(bash "$SHARD_SH" >/dev/null 2>&1; echo $?)"
judge "unknown flag exits 2" 2 "$(bash "$SHARD_SH" --bogus 1/4 >/dev/null 2>&1; echo $?)"
judge "too many arguments exits 2" 2 "$(bash "$SHARD_SH" 1/4 . extra >/dev/null 2>&1; echo $?)"
judge "missing root exits 2" 2 "$(bash "$SHARD_SH" 1/4 /nonexistent/tree >/dev/null 2>&1; echo $?)"

for bad in 0/4 5/4 1/0 0/0 a/b 1 1/4/2 -1/4 1/ /4 ' 1/4' '1/4 ' 1.0/4; do
  out="$(bash "$SHARD_SH" "$bad" 2>&1 >/dev/null)"; rc=$?
  judge "SHARD='$bad' exits 2" 2 "$rc"
  # -1/4 is rejected by the unknown-flag branch, the rest by the shape check; both
  # are loud and both echo the offending value.
  judge "SHARD='$bad' names the value on stderr" yes "$(has "$out" "$bad")"
  judge "SHARD='$bad' prints no suites" "" "$(bash "$SHARD_SH" "$bad" 2>/dev/null)"
done

judge "leading zeros are the same shard (02/04 == 2/4)" "$(bash "$SHARD_SH" 2/4)" "$(bash "$SHARD_SH" 02/04)"
judge "-v reports the shard size on stderr" yes "$(has "$(bash "$SHARD_SH" -v 2/4 2>&1 >/dev/null)" "shard 2/4:")"
judge "-v writes nothing extra to stdout" "$(bash "$SHARD_SH" 2/4)" "$(bash "$SHARD_SH" -v 2/4 2>/dev/null)"

# ---------------------------------------------------------------------------
section "partition on the real tree"

FULL="$(find tests -maxdepth 2 -name 'test-*.sh' | LC_ALL=C sort)"
TOTAL="$(printf '%s\n' "$FULL" | grep -c .)"
judge "the real tree has suites to shard" yes "$([ "$TOTAL" -gt 1 ] && echo yes || echo no)"
judge "this suite is itself in the list" yes "$(has "$FULL" "tests/test-shards.sh")"
judge "1/1 equals today's list (find -maxdepth 2 | sort), same order" "$FULL" "$(bash "$SHARD_SH" 1/1)"
judge "paths are relative to the root (tests/...)" "" "$(bash "$SHARD_SH" 1/1 | grep -v '^tests/')"

for n in 2 3 4 7 "$TOTAL"; do
  union="$(shards "$n" | LC_ALL=C sort)"
  judge "n=$n: the union of 1..$n is the full sorted list" "$FULL" "$union"
  judge "n=$n: every suite lands in exactly one shard (no duplicates)" "$TOTAL" "$(shards "$n" | grep -c .)"
  judge "n=$n: no shard is empty" 0 "$(for i in $(seq 1 "$n"); do [ -n "$(bash "$SHARD_SH" "$i/$n")" ] || echo "$i"; done | grep -c .)"
done

# suite k (0-based) goes to shard (k mod n)+1 — checked with a plain counter, not awk,
# so the oracle is written differently from the implementation.
expected_shard() { # <i> <n>
  local k=0 line
  printf '%s\n' "$FULL" | while IFS= read -r line; do
    [ $(( (k % $2) + 1 )) -eq "$1" ] && printf '%s\n' "$line"
    k=$((k + 1))
  done
}
for i in 1 2 3 4; do
  judge "shard $i/4 is exactly the suites with k mod 4 == $((i - 1))" "$(expected_shard "$i" 4)" "$(bash "$SHARD_SH" "$i/4")"
done
judge "n larger than the suite count: shard $((TOTAL + 1))/$((TOTAL + 1)) is empty and exits 0" "0:" \
  "$(bash "$SHARD_SH" "$((TOTAL + 1))/$((TOTAL + 1))" >/dev/null; echo "$?:$(bash "$SHARD_SH" "$((TOTAL + 1))/$((TOTAL + 1))")")"

judge "the same shard twice is byte-identical" "$(bash "$SHARD_SH" 3/4)" "$(bash "$SHARD_SH" 3/4)"
judge "the partition does not depend on the caller's locale" "$(LC_ALL=C bash "$SHARD_SH" 2/4)" "$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash "$SHARD_SH" 2/4 2>/dev/null)"
judge "the partition does not depend on the caller's cwd" "$(bash "$SHARD_SH" 2/4)" "$(cd /tmp && bash "$SHARD_SH" 2/4)"
judge "an explicit root equals the default root" "$(bash "$SHARD_SH" 2/4)" "$(bash "$SHARD_SH" 2/4 "$REPO_ROOT")"

# ---------------------------------------------------------------------------
section "hermetic tree: the Makefile runs exactly the script's list"

TMP="$(harness_tmpdir)"
TREE="$TMP/tree"
mkdir -p "$TREE/scripts/ci" "$TREE/tests/hooks"
cp "$REPO_ROOT/Makefile" "$TREE/Makefile"
cp "$SHARD_SH" "$TREE/scripts/ci/shard-suites.sh"

RAN="$TMP/ran.log"
WITNESS="$TMP/witness.log"
cat > "$TREE/scripts/real-home-witness.sh" <<EOF
#!/usr/bin/env bash
printf 'call\n' >> "$WITNESS"
printf 'stable\n'
EOF
# Seven stubs, named so that sorted order interleaves the two depths and the
# hyphenated names (the locale-sensitive shape the real tree has).
for s in tests/test-alpha.sh tests/test-beta-two.sh tests/test-beta.sh tests/test-gamma.sh \
         tests/hooks/test-h1.sh tests/hooks/test-h2.sh tests/test-zeta.sh; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "%s"\n' "$RAN" > "$TREE/$s"
done
# One stub also records the shellcheck marker the recipe hands every suite.
MARKER="$TMP/marker.log"
printf 'printf "%%s\\n" "${SUPERPOWERS_SHELLCHECK_DONE:-unset}" > "%s"\n' "$MARKER" >> "$TREE/tests/test-alpha.sh"
# ...and reads its stdin, as a real suite may (the since-removed test-toolkit-gates.sh did). Fed the
# list on stdin, it swallowed every suite after it and the loop ended green (#400).
# A line it reads is logged, so the "every suite ran once" cases below catch both a
# list fed on stdin and a suite handed make's own stdin (run_make feeds make a line).
printf 'if IFS= read -r l; then printf "STDIN %%s\\n" "$l" >> "%s"; fi; cat > /dev/null\n' "$RAN" >> "$TREE/tests/test-alpha.sh"
# Decoys the find must not pick up: depth 3, and a non-test-*.sh name.
mkdir -p "$TREE/tests/hooks/deep"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TREE/tests/hooks/deep/test-too-deep.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TREE/tests/helper.sh"

STUB_FULL="$(cd "$TREE" && find tests -maxdepth 2 -name 'test-*.sh' | LC_ALL=C sort)"
judge "stub tree lists seven suites" 7 "$(printf '%s\n' "$STUB_FULL" | grep -c .)"
judge "script on the stub tree: 1/1 equals its full list" "$STUB_FULL" "$(bash "$SHARD_SH" 1/1 "$TREE")"

run_make() { # <args...> — runs make in the tree, resets the logs first
  : > "$RAN"; : > "$WITNESS"
  # env -u: under `make test-hooks SHARD=i/n` the outer make exports SHARD and
  # MAKEFLAGS to every suite, so a nested make would inherit the shard and the
  # "no SHARD" cases would test the wrong thing (CI shard 2/4, 2026-11-05).
  printf 'not-a-suite\n' | env -u SHARD -u MAKEFLAGS -u MAKEOVERRIDES -u MFLAGS -u MAKELEVEL \
    make -C "$TREE" --no-print-directory "$@" 2>&1
}

out="$(run_make test-hooks)"; rc=$?
judge "no SHARD: make test-hooks exits 0" 0 "$rc"
judge "no SHARD: header is unchanged" yes "$(has "$out" "--- Hook behavior tests ---")"
judge "no SHARD: header carries no shard suffix" no "$(has "$out" "(shard")"
judge "no SHARD: every suite ran once, in sorted order" "$STUB_FULL" "$(cat "$RAN")"
judge "no SHARD: one '==>' line per suite" 7 "$(printf '%s\n' "$out" | grep -c '^==> ')"
judge "no SHARD: no suite read the list or make's stdin" 0 "$(grep -c '^STDIN' "$RAN")"
judge "no SHARD: the closing line counts every suite" yes "$(has "$out" "--- 7 of 7 suites ran ---")"
judge "no SHARD: the witness ran before and after every suite" 14 "$(grep -c call "$WITNESS")"
judge "no SHARD: suites receive SUPERPOWERS_SHELLCHECK_DONE=1" 1 "$(cat "$MARKER")"

for n in 1 2 3; do
  union=""
  for i in $(seq 1 "$n"); do
    out="$(run_make test-hooks "SHARD=$i/$n")"; rc=$?
    want="$(bash "$SHARD_SH" "$i/$n" "$TREE")"
    judge "SHARD=$i/$n: make exits 0" 0 "$rc"
    judge "SHARD=$i/$n: make ran exactly the script's list, in order" "$want" "$(cat "$RAN")"
    judge "SHARD=$i/$n: the witness bracketed every suite in the shard" "$(( 2 * $(printf '%s\n' "$want" | grep -c .) ))" "$(grep -c call "$WITNESS")"
    if [ "$n" -eq 1 ]; then
      judge "SHARD=1/1: header is the unsharded one" yes "$(has "$out" "--- Hook behavior tests ---")"
    else
      judge "SHARD=$i/$n: header names the shard" yes "$(has "$out" "--- Hook behavior tests (shard $i/$n) ---")"
    fi
    union="$union$(cat "$RAN")"$'\n'
  done
  judge "SHARD=*/$n: the shards together ran every suite exactly once" "$STUB_FULL" "$(printf '%s' "$union" | grep . | LC_ALL=C sort)"
done

out="$(run_make test-hooks SHARD=9/3)"; rc=$?
judge "SHARD=9/3: make fails" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
judge "SHARD=9/3: the script's error reaches the output" yes "$(has "$out" "SHARD must be")"
judge "SHARD=9/3: nothing ran" "" "$(cat "$RAN")"
judge "SHARD=9/3: the witness never ran" 0 "$(grep -c call "$WITNESS")"

out="$(run_make test-hooks SHARD=bogus)"; rc=$?
judge "SHARD=bogus: make fails" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
judge "SHARD=bogus: nothing ran" "" "$(cat "$RAN")"

# A failing suite inside a shard fails the shard, and the suites after it do not run.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "%s"\nexit 1\n' "$RAN" > "$TREE/tests/hooks/test-h1.sh"
out="$(run_make test-hooks SHARD=1/2)"; rc=$?
judge "a failing suite fails its shard" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
judge "the failing suite is the last one that ran" "tests/hooks/test-h1.sh" "$(tail -n 1 "$RAN")"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "%s"\n' "$RAN" > "$TREE/tests/hooks/test-h1.sh"

# The witness check is live inside a shard: a check that reports a leak fails the
# shard and names the suite. The stub's `check` now always reports one.
cat > "$TREE/scripts/real-home-witness.sh" <<EOF
#!/usr/bin/env bash
printf 'call\n' >> "$WITNESS"
[ "\$1" = check ] || exit 0
printf '  witness: LEAK added intent/x.json (stub)\n'
exit 1
EOF
out="$(run_make test-hooks SHARD=2/2)"; rc=$?
judge "a changed real-home fingerprint fails the shard" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
judge "the witness failure names the suite" yes "$(has "$out" "FAIL $(bash "$SHARD_SH" 2/2 "$TREE" | head -n 1) wrote to the real")"
judge "the witness's leak report reaches the output" yes "$(has "$out" "witness: LEAK added intent/x.json")"
judge "the witness failure stops the shard at the first suite" 1 "$(grep -c . "$RAN")"

# ---------------------------------------------------------------------------
section "real Makefile wiring"

judge "make -n test-hooks SHARD=2/4 parses" 0 "$(env -u SHARD -u MAKEFLAGS -u MAKEOVERRIDES -u MFLAGS -u MAKELEVEL make -n test-hooks SHARD=2/4 >/dev/null 2>&1; echo $?)"
judge "make -n test-hooks calls scripts/ci/shard-suites.sh" yes "$(has "$(env -u SHARD -u MAKEFLAGS -u MAKEOVERRIDES -u MFLAGS -u MAKELEVEL make -n test-hooks SHARD=2/4 2>&1)" "scripts/ci/shard-suites.sh")"
judge "make -n test-hooks no longer carries its own find" no "$(has "$(env -u SHARD -u MAKEFLAGS -u MAKEOVERRIDES -u MFLAGS -u MAKELEVEL make -n test-hooks 2>&1)" "find tests")"
judge "make -n validate parses" 0 "$(make -n validate >/dev/null 2>&1; echo $?)"
judge "make help documents SHARD" yes "$(has "$(make help 2>&1)" "SHARD=i/n")"
judge "make -n test-hooks hands suites SUPERPOWERS_SHELLCHECK_DONE=1" yes "$(has "$(make -n test-hooks 2>&1)" "SUPERPOWERS_SHELLCHECK_DONE=1 bash")"
judge "make lint is still the gate's shellcheck pass" yes "$(has "$(make -n lint 2>&1)" "shellcheck -S warning")"
judge "validate still depends on lint" yes "$(has "$(grep -E '^validate:' "$REPO_ROOT/Makefile")" " lint ")"

# ---------------------------------------------------------------------------
section "one shellcheck pass per gate (tests/test-static.sh under the marker)"

# A fake shellcheck that logs every call and passes: test-static standalone must
# reach it, test-static under the marker must not. The fake keeps each run to the
# cost of the file walk rather than the real ~50 s pass.
FAKEBIN="$TMP/bin"
SC_LOG="$TMP/shellcheck.log"
mkdir -p "$FAKEBIN"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$SC_LOG" > "$FAKEBIN/shellcheck"
chmod +x "$FAKEBIN/shellcheck"

: > "$SC_LOG"
out="$(env -u SUPERPOWERS_SHELLCHECK_DONE PATH="$FAKEBIN:$PATH" bash "$REPO_ROOT/tests/test-static.sh" 2>&1)"; rc=$?
judge "standalone: test-static exits 0 with the fake shellcheck" 0 "$rc"
judge "standalone: test-static runs shellcheck over the tree" yes "$([ "$(grep -c . "$SC_LOG")" -gt 10 ] && echo yes || echo no)"
judge "standalone: test-static reports the shellcheck case as ok" yes "$(has "$out" "ok   every shipped .sh is shellcheck-clean")"
judge "standalone: the fake was called with the lint flags" yes "$(has "$(head -n 1 "$SC_LOG")" "-S warning --exclude SC2034")"

: > "$SC_LOG"
out="$(SUPERPOWERS_SHELLCHECK_DONE=1 PATH="$FAKEBIN:$PATH" bash "$REPO_ROOT/tests/test-static.sh" 2>&1)"; rc=$?
judge "under the marker: test-static exits 0" 0 "$rc"
judge "under the marker: test-static never calls shellcheck" 0 "$(grep -c . "$SC_LOG")"
judge "under the marker: test-static names the skip and its reason" yes "$(has "$out" "skip shellcheck — already run by make lint (SUPERPOWERS_SHELLCHECK_DONE=1)")"
judge "under the marker: the other sections still run" yes "$(has "$out" "--- executable bits ---")"

if harness_have shellcheck; then
  judge "shard-suites.sh is shellcheck-clean at -S warning" 0 "$(shellcheck -S warning --exclude SC2034 "$SHARD_SH" >/dev/null 2>&1; echo $?)"
else
  skip "shard-suites.sh shellcheck" "shellcheck not installed"
fi

harness_summary
