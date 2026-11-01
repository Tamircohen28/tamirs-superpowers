---
name: reference-macos-binary-killed-stale-signature
description: A signed macOS binary that dies with exit 137 on launch while the identical bytes run elsewhere is a stale kernel signature on that inode - re-copy to a fresh inode
metadata:
  type: reference
---

`~/.opencode/bin/opencode` (2.2.5, Developer ID signed) was SIGKILLed on every launch (exit 137, crash report `SIGKILL (Code Signature Invalid)`, `Taskgated Invalid Signature`) although `codesign --verify` said "valid on disk". The app bundle's `opencode-cli` had the **same sha256** and ran fine, and a plain `cp` of the broken file to a new path ran fine too.

**Why:** the file had been overwritten in place (inode kept), so the kernel's cached code-signature verdict for that inode was stale. Bytes and signature were never wrong.

**How to apply:** compare hashes first, then `cp good opencode.new && mv -f opencode.new opencode` in the same directory (new inode, atomic). Do not reinstall or upgrade the CLI, and leave a running service alone: it keeps its own mapping. Fixed 2026-11-01 this way; the live OpenCode checks in `make validate` then ran for real. Related: [[feedback-verify-mechanism-claims]].
