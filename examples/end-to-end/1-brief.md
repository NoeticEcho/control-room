EPIC wc-3: branch claude/wc-3-count-words, scope wordcount check.sh README.md handoff/ runs/, grants none

Why: people want words, not only lines; the next release promises it.

The epic:
- wc-3.1: `sh wordcount -w` prints the number of words; without -w it still prints lines.
- wc-3.2: words are separated by any space, not only ASCII ones.

Accepted when: `sh check.sh` passes with a test for -w that fails without the change.

Protocol: as the agent instructions say. End with `EPIC wc-3 READY <sha> <pr-url>` or `EPIC wc-3 BLOCKED <reason>`.
