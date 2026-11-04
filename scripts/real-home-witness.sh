#!/usr/bin/env bash
# real-home-witness.sh [--home DIR] — print one fingerprint of the plugin's state in the REAL home.
#
# `make test-hooks` takes it before and after every suite and fails, naming the suite, when it changes: a suite
# that drives the real hooks must use the resolver's test root, never the user's own config or state. Two suites
# leaked there in the 5.2.0 run (an intent file, a confirm stamp) and nothing noticed until a human looked.
#
# The home comes from the passwd entry, not $HOME: suites set a fake HOME, and the leak is precisely a write that
# went past it. `--home DIR` exists for this script's own self-test only. A missing directory fingerprints as
# "absent", so CI (where neither exists) compares equal.
set -euo pipefail
if [ "${1:-}" = "--home" ]; then
  home="$2"
else
  home="$(python3 -I -S -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
fi
for d in "$home/.config/tamirs-superpowers" "$home/.local/state/tamirs-superpowers"; do
  if [ -e "$d" ]; then
    printf '%s\n' "$d"
    # path, size, nanosecond mtime and a content hash of everything under it: any write changes the
    # fingerprint. Whole-second mtime missed an overwrite of same-length content within the same second.
    python3 -I -S - "$d" <<'PY'
import hashlib, os, sys
for root, dirs, files in sorted(os.walk(sys.argv[1])):
    dirs.sort()
    for n in [root] + [os.path.join(root, f) for f in sorted(files)]:
        st = os.lstat(n)
        digest = hashlib.sha256(open(n, "rb").read()).hexdigest() if os.path.isfile(n) and not os.path.islink(n) else "-"
        print(n, st.st_size, st.st_mtime_ns, digest)
PY
  else
    printf '%s absent\n' "$d"
  fi
done | shasum | awk '{print $1}'
