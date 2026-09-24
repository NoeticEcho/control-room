EPIC <id>: branch <prefix>/<id>-<slug>, scope and grants below.

This brief is for profile `<profile>`. If your profile is not `<profile>`, reply `BRIEF MISROUTED`, change nothing, and wait.

## What landed since your last epic
<one or two lines: the merge commit, and what became of each of your findings>

## Why this epic
<the goal and the milestone it serves, in the owner's words where possible>

## The epic
<what to build, item by item; what is yours to decide, with a line of reasoning in the PR; what to keep unchanged>

**Acceptance:**
- <a check that can fail>
- each new test fails without its change — show it
- the full local check passes

## Scope
    <paths the worker may change>
    <handoff dir>/handoff/<id>.json
    <runs dir>/*.json            (new files only)

## Grants (this epic only)
    <a coordinator-held path>   (<exactly what may change in it>)

Anything else goes into `shared_change_requests[]`.

## Protocol
- git fetch origin && git switch -c <prefix>/<id>-<slug> origin/<integration-branch>
- push by the branch's own name, every turn
- open the pull request at the end, not before
- end with `EPIC <id> READY <sha> <pr-url>` or `EPIC <id> BLOCKED <reason>`
