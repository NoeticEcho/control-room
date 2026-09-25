#!/usr/bin/env bats
# Tests for desk/gh-desk, against a fake gh (tests/fixtures/fake-gh) that
# records its arguments and answers `issue list` from fixture files.

bats_require_minimum_version 1.5.0

GH_DESK="$BATS_TEST_DIRNAME/../desk/gh-desk"

setup() {
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin"
	ln -s "$BATS_TEST_DIRNAME/fixtures/fake-gh" "$bin/gh"
	export PATH="$bin:$PATH"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log" FAKE_GH_DIR="$BATS_TEST_TMPDIR/issues"
	mkdir -p "$FAKE_GH_DIR"
	# 2026-09-25T12:00:00Z
	export GH_DESK_NOW=1790337600
	unset GH_DESK_REPO FAKE_GH_EXIT
}

# issue <number> <title> <createdAt> <comments> <labels...>
issue() {
	jq -cn --argjson n "$1" --arg t "$2" --arg c "$3" --argjson k "$4" '
		{number: $n, title: $t, createdAt: $c, url: "https://github.com/o/r/issues/\($n)",
		 comments: [range($k) | {body: "c"}], labels: [$ARGS.positional[] | {name: .}]}' --args -- "${@:5}"
}

@test "list: asks gh for open decision and action issues, with the fields it reads" {
	echo '[]' >"$FAKE_GH_DIR/decision.json"
	run "$GH_DESK"
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "$FAKE_GH_LOG")" = '["issue","list","--state","open","--label","decision","--limit","200","--json","number,title,labels,createdAt,url,comments"]' ]
	[ "$(sed -n 2p "$FAKE_GH_LOG" | jq -r '.[5]')" = action ]
}

@test "list: answered cards first, then those waiting on the owner, oldest first, and one summary line" {
	{
		echo '['
		issue 12 "Pick the retention period" 2026-09-25T09:00:00Z 3 decision answered
		echo ','
		issue 15 "Licence of the sample text" 2026-09-25T10:00:00Z 0 decision
		echo ']'
	} >"$FAKE_GH_DIR/decision.json"
	{
		echo '['
		issue 14 "Create the docs environment" 2026-09-24T10:00:00Z 1 action
		echo ']'
	} >"$FAKE_GH_DIR/action.json"
	run "$GH_DESK"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Answered: act on these (1):" ]
	[[ "${lines[1]}" == "  #12 decision"*"Pick the retention period"*"(open 3h, 3 comments) https://github.com/o/r/issues/12" ]]
	[ "${lines[2]}" = "Waiting on the owner (2):" ]
	[[ "${lines[3]}" == "  #14 action"*"(open 26h, 1 comment) "* ]]
	[[ "${lines[4]}" == "  #15 decision"*"(open 2h, 0 comments) "* ]]
	[ "${lines[5]}" = "desk: 2 waiting on the owner, 1 answered; most urgent: #14 Create the docs environment (open 26h)" ]
	[ "${#lines[@]}" -eq 6 ]
}

@test "list: an issue with both labels is listed once; ages past two days are in days" {
	{ echo '['; issue 7 "Old one" 2026-09-20T12:00:00Z 0 decision action; echo ']'; } >"$FAKE_GH_DIR/decision.json"
	cp "$FAKE_GH_DIR/decision.json" "$FAKE_GH_DIR/action.json"
	run "$GH_DESK"
	[ "$(grep -c '^  #7 ' <<<"$output")" -eq 1 ]
	[[ "$output" == *"(open 5d, 0 comments)"* ]]
}

@test "list: a card labelled done but still open is flagged to close" {
	{ echo '['; issue 9 "Done thing" 2026-09-25T11:00:00Z 2 action answered "done"; echo ']'; } >"$FAKE_GH_DIR/action.json"
	run "$GH_DESK"
	[ "${lines[0]}" = "Done but still open: close them (1):" ]
	[ "${lines[2]}" = "desk: nothing waits on the owner or on you" ]
}

@test "list: an empty desk says so" {
	run "$GH_DESK"
	[ "$status" -eq 0 ]
	[ "$output" = "desk: nothing waits on the owner or on you" ]
}

@test "list: GH_DESK_REPO selects the repository" {
	GH_DESK_REPO=o/r run "$GH_DESK"
	[ "$(sed -n 1p "$FAKE_GH_LOG" | jq -r '.[-2:] | join(" ")')" = "-R o/r" ]
}

@test "list: gh's failure is the command's failure" {
	FAKE_GH_EXIT=4 run "$GH_DESK"
	[ "$status" -eq 1 ]
	[[ "$output" == *"gh issue list failed"* ]]
}

@test "labels: creates or updates the four labels" {
	run "$GH_DESK" labels
	[ "$status" -eq 0 ]
	[ "$(jq -r '"\(.[0]) \(.[1]) \(.[2]) \(.[3])"' "$FAKE_GH_LOG" | tr '\n' ';')" = \
		"label create decision --force;label create action --force;label create answered --force;label create done --force;" ]
}

@test "usage: an unknown command is refused" {
	run "$GH_DESK" merge
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown command"* ]]
}
