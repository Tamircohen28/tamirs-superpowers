---
name: feedback-macos-sed-insert
description: On macOS, never use sed inline insert — use Python instead
metadata:
  type: feedback
---

Never use `sed '/pattern/i text'` inline on macOS for line insertion — the macOS BSD `sed` requires a literal `\` followed by a newline after the `i` flag; the GNU/Linux inline form silently fails or errors.

**Why:** Discovered when patching the awesome-ai-plugins README; `sed` failed and required an immediate fallback to Python mid-task.

**How to apply:** For any "insert line before/after pattern" operation on macOS, use Python directly:

```python
with open("file") as f:
    lines = f.readlines()
out = []
for line in lines:
    if line.startswith("TARGET"):
        out.append("NEW LINE\n")
    out.append(line)
with open("file", "w") as f:
    f.writelines(out)
```
