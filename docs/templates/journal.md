# Journal: <project>

<!--
One line per coordinator run, appended, never edited
(docs/coordinator-loop.md). The interactive coordinator adds one line per
session too. A run reads the last twenty lines before it acts, and appends
its own line as its last act: when it started, who ran it, how long it took,
what it did, and what the next run must look at. A run that did nothing
still writes a line: the durations are how the interval is tuned.

  <start> <who> <duration> | <acts, separated by "; "> | next: <what to look at>

Acts use the queue's words: landed, returned, briefed, asked, answered,
carded, reminded, lock held, paused. A sha is the first 7 characters here;
the queue and the landing notes have it in full. No secrets. Times are UTC.
Delete this comment in your copy, and the example lines below.
-->

2026-09-25T09:00Z loop 3m | briefed backend proj-12 | next: -
2026-09-25T09:30Z loop 1m | nothing to do | next: -
2026-09-25T10:00Z loop 14m | landed proj-11 8e1d0b2 (CI pending); briefed docs proj-15 | next: CI of 8e1d0b2
2026-09-25T10:30Z loop 2m | CI green 8e1d0b2; lock held (interactive, landing proj-13): skipped landing | next: -
2026-09-25T10:41Z interactive 25m | paused until 12:41Z; landed proj-13 51c0a7e; carded backend's question (card 7) | next: card 7
2026-09-25T11:00Z loop 1m | paused by interactive until 12:41Z: read only | next: card 7
2026-09-25T13:00Z loop 2m | asked backend (no commit since 10:52Z); reminded owner of card 7 | next: backend's answer
