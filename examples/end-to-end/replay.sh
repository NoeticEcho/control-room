#!/bin/sh
# replay.sh <outdir>: replays epic wc-3 on a toy repository, `wordcount`, and
# writes the files the protocol produces into <outdir>. The files in this
# directory were written by it; `make check` replays it and compares.
#
# The script plays both roles: the worker (branch, handoff, change, recorded
# check, READY) and the coordinator (the landing checklist, the desk card).
# No agent runs. The git commands, the check and the landing are real; commit
# dates are fixed, so the shas are the same on every replay.
#
# Dependencies: POSIX sh, git, jq, awk.

set -eu

[ $# -eq 1 ] || { echo "usage: replay.sh <outdir>" >&2; exit 2; }
out=$1
mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C TZ=UTC

# as <who> <HH:MM>: the author and the fixed time of the next commit
as() {
	case $1 in
	owner) GIT_AUTHOR_NAME="The owner" GIT_AUTHOR_EMAIL=owner@example.invalid ;;
	worker) GIT_AUTHOR_NAME="backend worker" GIT_AUTHOR_EMAIL=worker@example.invalid ;;
	coordinator) GIT_AUTHOR_NAME="coordinator" GIT_AUTHOR_EMAIL=coordinator@example.invalid ;;
	esac
	GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
	GIT_AUTHOR_DATE="2026-09-25T$2:00Z" GIT_COMMITTER_DATE="2026-09-25T$2:00Z"
	export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
}

q() { git "$@" >/dev/null 2>&1; }

# ---- the toy repository, on main --------------------------------------------

git init -q --bare -b main "$work/origin.git"
git init -q -b main "$work/seed"
cd "$work/seed"
cat >wordcount <<'EOF'
#!/bin/sh
# wordcount: count the lines of standard input.
awk 'END { print NR }'
EOF
cat >check.sh <<'EOF'
#!/bin/sh
# The toy's whole check.
set -e
lines=$(printf 'one two\nthree\n' | sh wordcount)
[ "$lines" = 2 ] || { echo "FAIL lines: got $lines"; exit 1; }
echo "ok lines"
EOF
cat >README.md <<'EOF'
# wordcount

Counts the lines of standard input: `sh wordcount < file`.
EOF
as owner 08:00
git add -A
q commit -m "wordcount: count lines"
q remote add origin "$work/origin.git"
q push origin main

# ---- 1. the brief (coordinator -> worker, as a user message) ----------------

cat >"$out/1-brief.md" <<'EOF'
EPIC wc-3: branch claude/wc-3-count-words, scope wordcount check.sh README.md handoff/ runs/, grants none

Why: people want words, not only lines; the next release promises it.

The epic:
- wc-3.1: `sh wordcount -w` prints the number of words; without -w it still prints lines.
- wc-3.2: words are separated by any space, not only ASCII ones.

Accepted when: `sh check.sh` passes with a test for -w that fails without the change.

Protocol: as the agent instructions say. End with `EPIC wc-3 READY <sha> <pr-url>` or `EPIC wc-3 BLOCKED <reason>`.
EOF

# ---- 2. the worker: branch, handoff at working -------------------------------

git clone -q "$work/origin.git" "$work/worker"
cd "$work/worker"
q switch --no-track -c claude/wc-3-count-words origin/main
base=$(git rev-parse origin/main)
mkdir -p handoff runs

handoff() { # <status> <children json> <extra json>
	jq -n --arg base "$base" --arg status "$1" --argjson children "$2" --argjson extra "$3" '
		{epic: "wc-3", profile: "backend", session: "cr-worker:backend",
		 branch: "claude/wc-3-count-words", status: $status, base: $base,
		 children: $children,
		 questions: [{text: "wc-3.2: awk splits words on ASCII blanks only. Should wordcount split on every Unicode space (my recommendation), keep ASCII and document it, or use a segmenter library (a first dependency)?", blocking: false}]}
		+ $extra' >handoff/wc-3.json
}

handoff working '[{"id": "wc-3.1", "outcome": "open"}, {"id": "wc-3.2", "outcome": "open"}]' '{}'
as worker 08:10
git add handoff/wc-3.json
q commit -m "handoff: wc-3 working"
q push origin claude/wc-3-count-words
mkdir -p "$out/2-working/handoff"
cp handoff/wc-3.json "$out/2-working/handoff/wc-3.json"

# ---- 3. the work: a test that fails without the change, then the change ------

cat >>check.sh <<'EOF'
words=$(printf 'one two\nthree\n' | sh wordcount -w)
[ "$words" = 3 ] || { echo "FAIL words: got $words"; exit 1; }
echo "ok words"
EOF
if sh check.sh >"$work/red.log" 2>&1; then
	echo "replay: the new test passed without the change" >&2
	exit 1
fi
cat >wordcount <<'EOF'
#!/bin/sh
# wordcount: count the lines of standard input, or with -w its words.
case ${1-} in
-w) awk '{ words += NF } END { print words + 0 }' ;;
'') awk 'END { print NR }' ;;
*) echo "usage: wordcount [-w] < file" >&2; exit 2 ;;
esac
EOF
cat >README.md <<'EOF'
# wordcount

Counts the lines of standard input, `sh wordcount < file`, or its words,
`sh wordcount -w < file`.
EOF
as worker 08:40
git add wordcount check.sh README.md
q commit -m "wordcount -w: count words (wc-3.1)"
q push origin claude/wc-3-count-words
work_head=$(git rev-parse HEAD)

# ---- 4. before READY: merge the integration branch, run the full check -------

q fetch origin
q merge --no-edit origin/main
base=$(git rev-parse origin/main)
head=$(git rev-parse HEAD)
start=$(date +%s)
if sh check.sh >"$work/check.log" 2>&1; then outcome=passed; else outcome=failed; fi
seconds=$(($(date +%s) - start))
[ "$outcome" = passed ] || { cat "$work/check.log" >&2; exit 1; }
jq -n --arg head "$head" --arg outcome "$outcome" --argjson seconds "$seconds" \
	--arg log "$(cat "$work/check.log")" --arg red "$(cat "$work/red.log")" '
	{id: "run-wc-3-1", epic: "wc-3", head: $head,
	 gates: {status: $outcome, seconds: $seconds, head: $head,
	         results: [{id: "check.sh", command: "sh check.sh", outcome: $outcome, output: $log}]},
	 red_before_change: {command: "sh check.sh", output: $red}}' >runs/run-wc-3-1.json

# ---- 5. READY: the handoff at ready, in the branch's last commit -------------

handoff ready "$(jq -n --arg c "$work_head" '[
	{id: "wc-3.1", outcome: "done", commits: [$c]},
	{id: "wc-3.2", outcome: "deferred", note: "Waits on the owner: which spaces separate words (questions[0], desk card wc-3-unicode)."}]')" \
	"$(jq -n --arg head "$head" --argjson seconds "$seconds" '{
	runs: ["run-wc-3-1"],
	lane: {verdict: "passed", seconds: $seconds, head: $head, gates: [{id: "check.sh", outcome: "passed"}]},
	discovered: [{text: "wordcount reads a file only on standard input; `sh wordcount file` silently ignores the argument.", paths: ["wordcount"]}]}')"
as worker 08:50
git add handoff/wc-3.json runs/run-wc-3-1.json
q commit -m "handoff: wc-3 ready"
q push origin claude/wc-3-count-words
ready=$(git rev-parse HEAD)
mkdir -p "$out/3-run/runs" "$out/4-ready/handoff"
cp runs/run-wc-3-1.json "$out/3-run/runs/run-wc-3-1.json"
cp handoff/wc-3.json "$out/4-ready/handoff/wc-3.json"
printf 'EPIC wc-3 READY %s https://git.example.invalid/wordcount/pull/3\n' "$ready" >"$out/5-ready-line.txt"

# ---- 6. landing (coordinator, in a throwaway checkout) -----------------------

git clone -q "$work/origin.git" "$work/landing"
cd "$work/landing"
q fetch origin claude/wc-3-count-words
branch_head=$(git rev-parse origin/claude/wc-3-count-words)
[ "$branch_head" = "$ready" ] || { echo "replay: head is not the READY sha" >&2; exit 1; }
status=$(git show "$ready:handoff/wc-3.json" | jq -r .status)
lane_head=$(git show "$ready:handoff/wc-3.json" | jq -r .lane.head)
after_run=$(git diff --name-only "$lane_head" "$ready" | tr '\n' ' ' | sed 's/ $//')
changed=$(git diff --name-only "origin/main...$ready" | tr '\n' ' ' | sed 's/ $//')
outside=
for f in $changed; do
	case $f in wordcount | check.sh | README.md | handoff/* | runs/*) ;; *) outside="$outside $f" ;; esac
done
[ -z "$outside" ] || { echo "replay: outside scope:$outside" >&2; exit 1; }
as coordinator 09:05
q merge --no-ff -m "Merge wc-3: wordcount -w counts words" "$ready"
merge=$(git rev-parse HEAD)
sh check.sh >"$work/landing-check.log" 2>&1
q push origin "HEAD:refs/heads/main"
landed=$(git -C "$work/origin.git" rev-parse main)
[ "$landed" = "$merge" ] || { echo "replay: main is not the merge" >&2; exit 1; }

cat >"$out/6-landing.md" <<EOF
# Landing wc-3

The coordinator's notes, by the landing checklist in docs/protocol.md.
Written by replay.sh from what the commands returned.

1. **Head and handoff.** \`origin/claude/wc-3-count-words\` is \`$branch_head\`,
   the READY sha. The handoff there has status \`$status\`. Its lane ran at
   \`$lane_head\`; between that and the READY sha only these files changed:
   \`$after_run\` (handoff and run files only).
2. **Scope.** Changed against main: \`$changed\`. All inside the brief's scope
   (\`wordcount check.sh README.md handoff/ runs/\`); no grants were given.
3. **Security-sensitive.** Nothing: no access policy, no user text rendered,
   no configuration, nothing that looks like a secret.
4. **Merge** with \`--no-ff\` in a throwaway clone: \`$merge\`.
5. **Checks.** \`sh check.sh\` on the merge:

   \`\`\`text
$(sed 's/^/   /' "$work/landing-check.log")
   \`\`\`

6. **Push** with an explicit refspec: \`git push origin HEAD:refs/heads/main\`.
   \`main\` is now \`$landed\`.
7. **CI.** The toy has no CI; on a real repository, read the run for
   \`$landed\` before going on.
8. **Close and file.**
   - wc-3.1 closed, with \`$work_head\` and the run \`run-wc-3-1\` in the reason.
   - wc-3.2 stays open: it waits on the owner. Desk card \`wc-3-unicode\` made
     from the handoff's question (7-desk/).
   - The discovered item ("\`sh wordcount file\` silently ignores the
     argument") filed as a new task.
   - The worker's next brief opens with: wc-3 landed at \`$landed\`; wc-3.2
     waits on the desk; the argument bug is a new task.
EOF

# ---- 7. the desk card, and the owner's answer --------------------------------

mkdir -p "$out/7-desk"
card=$(jq -n '{
	id: "wc-3-unicode", kind: "decision",
	title: "How should wordcount count words in text that is not ASCII?",
	why: "wc-3.2 waits on it; wc-3.1 (words) landed without it.",
	context: "awk splits words on ASCII blanks. Text with non-breaking spaces, or in scripts written without spaces, counts oddly. The fix is small either way; the choice is what users are promised.",
	choices: [
		{id: "unicode-spaces", label: "Split on every Unicode space", consequence: "What most people expect for European text. Scripts without spaces still count one word per run. One more test.", recommended: true},
		{id: "ascii-only", label: "Keep ASCII blanks, and document it", consequence: "No code change. The README says what counts as a word."},
		{id: "segmenter", label: "Use a word segmenter library", consequence: "Right for every script, but the tool gains its first dependency."}],
	links: [{label: "The question in the handoff", url: "https://git.example.invalid/wordcount/blob/claude/wc-3-count-words/handoff/wc-3.json"}],
	status: "open", created: "2026-09-25T09:10:00Z", source: "handoff wc-3, questions[0]"}')
jq -n --argjson card "$card" '{"$schema": "../../../desk/desk.schema.json", updated: "2026-09-25T09:10:00Z", cards: [$card]}' >"$out/7-desk/desk-open.json"
answer='{"card": "wc-3-unicode", "status": "answered", "answer": {"choice": "unicode-spaces", "note": "Yes, and say in the README that scripts without spaces are not segmented.", "at": "2026-09-25T09:32:00.000Z"}}'
printf '%s\n' "$answer" | jq . >"$out/7-desk/answer.json"
jq -n --argjson card "$card" --argjson a "$answer" '{"$schema": "../../../desk/desk.schema.json", updated: "2026-09-25T09:35:00Z",
	cards: [$card + {status: $a.status, answer: $a.answer}]}' >"$out/7-desk/desk-answered.json"

echo "replayed wc-3: READY $ready, landed $landed"
