---
type: llm
---

PASS if the brief lists web/src/settings and web/src/theme as the paths the worker may change, AND its acceptance criteria are concrete checks that could fail (for example a named test covering the toggle's states), AND it requires that each new test fails without its change.
FAIL if the paths are missing, or the acceptance is vague ("works", "tests pass") with no concrete check, or nothing asks for tests to be shown failing without the change.
