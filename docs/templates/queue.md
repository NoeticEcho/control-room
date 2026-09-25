# Queue: <project>

<!--
The coordinator's state, for a coordinator that starts with no memory
(docs/coordinator-loop.md). Every act updates this file as it happens, and
adds to the journal line of the run: the next run has no other memory.
Keep it next to the journal, outside the project's integration branch (every
write would be a commit). No secrets, ever: sessions and ids only.
Times are UTC, as 2026-09-25T10:30Z. Delete this comment in your copy.
-->

Updated: <time> by <loop | interactive>
Paused by: none
<!-- or: Paused by: interactive until <time>. While a pause holds, the loop
     only reads and writes its journal line. An expired pause is void. -->

Integration branch: <main>
Landing lock: <default: cr-land.lock in the git common directory | a path in CR_LAND_LOCK>
Heavy-job lock: </tmp/cr-heavy.lock>
Journal: <path to journal.md>
Desk: <link>
Tracker: <how to read it, e.g. bd ready>
Last reminder to the owner: <time>

## How to brief

Brief files: <directory>. One file per brief, named `<epic>.md`, written
before it is sent.

| Runner | Command |
|---|---|
| Claude Code cloud | `claude -p "$(cat <file>)" --cloud <session> </dev/null` (queues it and returns) |
| Local worktree | `nohup runners/local/cr-worker brief <profile> <file> >/dev/null 2>&1 &` (75: in a turn, try next run) |
| e2b | `runners/e2b/cr-e2b brief --sandbox <id> --brief <file>` |

A status question uses the same command with the question in the file.

## How to land

Under the landing lock, after checking the sha is not already landed
(docs/coordinator-loop.md § Two coordinators):

    scripts/land-lock --who <loop | interactive> -- <landing command> <sha>

- Landing command: <what it does: throwaway checkout, merge --no-ff, check, push by refspec>
- Full check: `<make check>`, under the heavy-job lock, at most one per run
- CI after the push: <how to read it: gh run list --commit <sha>, or local-ci status>
- Fenced paths: <list>; they land only with the owner's quoted approval

## Workers

<!-- State: idle, briefing, working, silent-asked, blocked, waiting-owner,
     ready, landing, ci-pending. "Since" is when it entered that state.
     "Last commit" is the time of the branch's last commit on origin. -->

| Profile | Runner | Session / id | Current epic | Branch | State | Since | Last commit | Asked | Next epic |
|---|---|---|---|---|---|---|---|---|---|
| backend | cloud | session_<id> | proj-12 | claude/proj-12-login | working | 2026-09-25T09:02Z | 2026-09-25T10:14Z | - | proj-14 |
| docs | local | worktree docs | - | - | idle | 2026-09-25T08:40Z | - | - | proj-15 |

## Epics waiting for a worker

<!-- In order. An epic moves up to its worker's "Next epic" when the worker
     is free, and its brief file is written then. -->

- proj-15 (docs): <one line>; depends on proj-12
- proj-16 (backend): <one line>

## Pending

<!-- What a run started and the next run must finish. An intent with no
     outcome is checked against the world before anything is repeated. -->

- landing proj-11 <sha>: CI pending since <time>
- briefing docs proj-15: intent written <time>, not yet confirmed sent

## Waiting for the owner

- card <id>: <the question, one line>, since <time>, for <worker / epic>
