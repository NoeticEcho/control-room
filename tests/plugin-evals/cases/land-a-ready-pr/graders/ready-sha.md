---
type: llm
---

PASS if the plan merges exactly the READY commit 3f2a9c1e0b7d4a6f8e2c5b9d1a3f7e6c4b2d8a0f (not the branch's newer head), AND it checks whether the later commit only merged main before deciding what to do with it or with the pull request.
FAIL if the plan merges the branch's latest head or the pull request as it stands now, or ignores the commit pushed after the READY line.
