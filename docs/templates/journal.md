# Journal: <project>

<!--
One line per coordinator action, appended, never edited
(docs/coordinator-loop.md). Every act writes its line as it happens:
landed, returned, briefed, asked, answered, carded, reminded, created a
worker, archived a session, a send not delivered, lock held, paused. Each
run also ends with one line, with its duration and what the next run must
look at. A run that did nothing still writes that line: the durations are
how the interval is tuned. The interactive coordinator writes the same lines.
A run reads the last twenty lines before it acts.

  <time> <who> <act> | <detail>
  <start> <who> end <duration> | next: <what to look at>

A sha is the first 7 characters here; the queue and the landing notes have
it in full. No secrets. Times are UTC.
Delete this comment in your copy, and the example lines below.
-->

2026-09-25T09:01Z loop briefed backend proj-12 | opus / high
2026-09-25T09:03Z loop end 3m | next: -
2026-09-25T09:31Z loop end 1m | nothing to do; next: -
2026-09-25T10:02Z loop created worker docs | routine trig_<id>, fires 10:04Z, sonnet-5-5 / medium, first brief proj-15
2026-09-25T10:09Z loop landed proj-11 8e1d0b2 | with proj-10 4c2e9a1, one check; CI pending
2026-09-25T10:14Z loop end 14m | next: CI of 8e1d0b2; session of trig_<id>
2026-09-25T10:31Z loop CI green 8e1d0b2 | deployed to test, health ok, status posted
2026-09-25T10:31Z loop worker docs has session_<id> | from the run of trig_<id>
2026-09-25T10:32Z loop lock held | interactive, landing proj-13: skipped landing
2026-09-25T10:33Z loop end 2m | next: -
2026-09-25T10:41Z interactive paused | until 12:41Z
2026-09-25T10:58Z interactive landed proj-13 51c0a7e | CI pending
2026-09-25T11:04Z interactive carded backend's question | card 7
2026-09-25T11:06Z interactive end 25m | next: card 7
2026-09-25T13:00Z loop not delivered | brief proj-14 to backend: "Session expired"; first line of the report, with the link
2026-09-25T13:01Z loop asked backend | no commit since 10:52Z
2026-09-25T13:02Z loop archived loop session | session_<id> of the 09:00Z run
2026-09-25T13:02Z loop end 2m | next: backend's answer; the owner on proj-14
