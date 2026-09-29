# Queue: <project>

<!--
The coordinator's state, for a coordinator that starts with no memory
(docs/coordinator-loop.md). Every act updates this file as it happens, and
adds one line to the journal: the next run has no other memory.
Keep it next to the journal, outside the project's integration branch (every
write would be a commit). No secrets, ever: sessions and ids only.
Times are UTC, as 2026-09-25T10:30Z. Delete this comment in your copy.
-->

Updated: <time> by <loop | interactive>
Paused by: none
<!-- or: Paused by: interactive until <time>. While a pause holds, the loop
     only reads, and writes its journal lines. An expired pause is void. -->

Integration branch: <main>
Landing lock: <default: cr-land.lock in the git common directory | a path in CR_LAND_LOCK>
Heavy-job lock: </tmp/cr-heavy.lock>
Journal: <path to journal.md>
Desk: <link>
Tracker: <how to read it, e.g. bd ready>
Last reminder to the owner: <time>
Workers created by the coordinator: <not authorised | authorised by the owner on <time>: "<their words>">
Cloud environment: <environment id, with the setup script>. Repository: <url>

## How to brief

Brief files: <directory>. One file per brief, named `<epic>.md`, written
before it is sent.

| Runner | Command |
|---|---|
| Claude Code cloud | `runners/claude-code-cloud/cr-cloud brief <session> <file>` (queues it and returns; 3: not delivered, tell the owner first) |
| Local worktree | `nohup runners/local/cr-worker brief <profile> <file> >/dev/null 2>&1 &` (75: in a turn, try next run) |
| e2b | `runners/e2b/cr-e2b brief --sandbox <id> --brief <file>` |

A status question uses the same command with the question in the file.

The brief states the model and the effort (docs/protocol.md, Model and
effort): the strongest model at high effort for long-horizon, architecture,
security-sensitive or hard-merge work; a fast model at medium effort (high
when harder) for well-specified epics.

## How to create a worker

Only when "Workers created by the coordinator" above says authorised.

    runners/claude-code-cloud/cr-cloud new <profile> <brief file> \
        --environment <environment id> --repository <url> --model <model> > <routine file>

Submit the routine file with the routine tool of the coordinator's session
(runners/claude-code-cloud/README.md). Record the routine at once. On the run
after it fires, read its run for the session id, and fill the worker's row.

## How to land

Under the landing lock, after checking the sha is not already landed
(docs/coordinator-loop.md § Two coordinators):

    scripts/land-lock --who <loop | interactive> -- <landing command> <sha>

- Landing command: <what it does: throwaway checkout, merge --no-ff, check, push by refspec>
- Full check: `<make check>`, under the heavy-job lock, at most one per run
- CI after the push: <how to read it: gh run list --commit <sha>, or local-ci status>
- Fenced paths: <list>; they land only with the owner's quoted approval

## Workers

<!-- State: creating, idle, briefing, working, silent-asked, blocked,
     waiting-owner, not-delivered, ready, landing, ci-pending. "Since" is when
     it entered that state. "Routine" is the one-off routine that created a
     cloud worker, if the coordinator created it.
     "Last commit" is the time of the branch's last commit on origin. -->

| Profile | Runner | Session / id | Routine | Model / effort | Current epic | Branch | State | Since | Last commit | Asked | Next epic |
|---|---|---|---|---|---|---|---|---|---|---|---|
| backend | cloud | session_<id> | trig_<id> | opus / high | proj-12 | claude/proj-12-login | working | 2026-09-25T09:02Z | 2026-09-25T10:14Z | - | proj-14 |
| docs | local | worktree docs | - | sonnet-5-5 / medium | - | - | idle | 2026-09-25T08:40Z | - | - | proj-15 |

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
- creating worker docs: routine trig_<id> fires <time>; session not yet read

## Waiting for the owner

<!-- A send that was not delivered is the first line of the next report to
     the owner, with the session's link. -->

- not delivered: brief proj-14 to backend (session <link>): "Session expired", since <time>
- card <id>: <the question, one line>, since <time>, for <worker / epic>
