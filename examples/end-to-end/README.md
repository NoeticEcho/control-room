# One epic, end to end

Epic `wc-3` on a toy repository, `wordcount` (a few lines of sh and awk),
as the files the protocol produces, in order. Every file here was written by
[`replay.sh`](replay.sh), which plays the worker and the coordinator with
real git commands on a throwaway repository. No agent ran; the commits, the
check, the merge and the push did. Commit dates are fixed, so the shas below
are the same on every replay, and `make check` replays it and compares.

The toy repository is not published: the pull request URL in the READY line
(`git.example.invalid`) stands for wherever yours would be.

| Step | Who | File |
|---|---|---|
| 1. The brief, delivered as a user message | coordinator → worker | [`1-brief.md`](1-brief.md) |
| 2. Branch from the integration branch; the handoff at `working` in the first commit | worker | [`2-working/handoff/wc-3.json`](2-working/handoff/wc-3.json) |
| 3. A test that fails without the change, the change, then the full check, **recorded** | worker | [`3-run/runs/run-wc-3-1.json`](3-run/runs/run-wc-3-1.json) |
| 4. The handoff at `ready`, in the branch's last commit | worker | [`4-ready/handoff/wc-3.json`](4-ready/handoff/wc-3.json) |
| 5. The READY line | worker | [`5-ready-line.txt`](5-ready-line.txt) |
| 6. Landing, by the checklist | coordinator | [`6-landing.md`](6-landing.md) |
| 7. The question in the handoff becomes a desk card; the owner answers | coordinator, owner | [`7-desk/`](7-desk/) |

## What happens

1. **The brief** names the epic, the branch `claude/wc-3-count-words`, the
   scope (`wordcount check.sh README.md handoff/ runs/`), no grants, why, and
   how it is accepted: a test for `-w` that fails without the change.
2. **The worker** branches from `origin/main` without tracking it, and commits
   the handoff at `working`: both children `open`, and one question it can
   already see. wc-3.2 asks for "any space", and awk splits on ASCII blanks
   only; which spaces count is the owner's call. The question is not
   blocking: wc-3.1 can go on without it.
3. **The work.** The worker adds the `-w` test first and runs the check: it
   fails (`FAIL words: got 2`, kept in the run file as
   `red_before_change`). Then it writes the change, merges `origin/main`, and
   runs the full check, `sh check.sh`, at `c25fff0…`. The result is written
   to `runs/run-wc-3-1.json`: this is the record, not a report of it.
4. **READY.** The handoff moves to `ready` in one more commit, holding only
   the handoff and the run file:
   - wc-3.1 `done`, with its commit;
   - wc-3.2 `deferred`, with a note: it waits on the owner;
   - the lane copied from the run: `passed`, at `c25fff0…`;
   - one thing found on the way (`discovered`): `sh wordcount file` ignores
     its argument. It is not this epic's work, so it goes to the tracker.
5. **The READY line** carries that last commit, `bc20c17…`, the sha the
   coordinator will land.
6. **Landing** in a throwaway clone, by the checklist in
   `docs/protocol.md`:
   - the branch head is the READY sha;
   - only handoff and run files changed after the lane's head;
   - every changed file is in scope;
   - merge `--no-ff`, run the check on the merge, and push with an explicit
     refspec.

   Then close wc-3.1, keep wc-3.2 open, and file the discovered item.
7. **The desk.** The handoff's question becomes the card `wc-3-unicode`
   ([`desk-open.json`](7-desk/desk-open.json)). The owner answers on the page
   and pastes [the snippet](7-desk/answer.json) to the coordinator, who
   writes it into [`desk-answered.json`](7-desk/desk-answered.json). The
   answer then goes into the worker's next brief for wc-3.2.

## Checked by `make check`

`tests/examples.bats`:

- replays the epic and compares every file with the ones here. Only the
  measured `seconds` are ignored, since a check takes as long as it takes.
- runs `scripts/validate-handoff` on both handoffs;
- checks the desk files against `desk/desk.schema.json`;
- checks the pieces agree:
  - the brief's branch is the handoff's;
  - the run's head is the lane's;
  - the READY line's sha is the one the landing notes checked;
  - the answer applied to the open card is the answered card.
