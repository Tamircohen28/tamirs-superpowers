---
type: regex
target: { source: file, path: "hello.txt" }
match: contains
flags: i
---
^\s*ready\s*$
