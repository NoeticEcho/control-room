---
type: llm
---

PASS if the plan checks that the changed files are inside services/api/, AND merges in a separate or throwaway checkout (for example a git worktree) rather than the user's working directory, AND reads the real CI result for the pushed commit after pushing.
FAIL if any of those three is missing.
