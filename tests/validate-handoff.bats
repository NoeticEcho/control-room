#!/usr/bin/env bats
# Tests for scripts/validate-handoff. Each fixture in tests/fixtures/handoff/
# breaks one rule of a valid handoff.
# The expected messages contain backquotes and $ as text (SC2016).
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

VALIDATE="$BATS_TEST_DIRNAME/../scripts/validate-handoff"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/handoff"

# fixture <case>: the one handoff file in that case's directory
fixture() {
	set -- "$FIXTURES/$1"/*.json
	printf '%s\n' "$1"
}

valid() {
	run "$VALIDATE" "$@"
	if [ "$status" -ne 0 ] || [ -n "$output" ]; then
		echo "expected valid: $*"
		echo "status $status: $output"
		return 1
	fi
}

# invalid <case> <text the problem line must contain>
invalid() {
	run "$VALIDATE" "$(fixture "$1")"
	if [ "$status" -ne 1 ] || [[ "$output" != *"$2"* ]]; then
		echo "expected a problem containing '$2' for $1"
		echo "status $status: $output"
		return 1
	fi
}

@test "valid: a ready handoff with every rule kept" {
	valid "$(fixture valid)"
}

@test "valid: a working handoff may have open children and no lane" {
	valid "$(fixture working-open-child)"
}

@test "valid: the example in schemas/, named for its epic" {
	cp "$BATS_TEST_DIRNAME/../schemas/handoff-example.json" "$BATS_TEST_TMPDIR/proj-12.json"
	valid "$BATS_TEST_TMPDIR/proj-12.json"
}

@test "valid: several files at once" {
	valid "$(fixture valid)" "$(fixture working-open-child)"
}

@test "schema: required, additionalProperties and enum are enforced" {
	invalid schema-violations "'profile' is a required property"
	invalid schema-violations "'extra' was unexpected"
	invalid schema-violations "'landed' is not one of"
}

@test "name: the file must be named for its epic" {
	invalid misnamed 'the file is proj-99.json but the epic is proj-12'
}

@test "ready: needs a lane" {
	invalid ready-without-lane 'a ready handoff needs the lane of its finished run'
}

@test "ready: the lane must have passed" {
	invalid ready-failed-lane 'a ready handoff needs a passed lane, not failed'
}

@test "ready: no child may be open" {
	invalid ready-open-child 'proj-12.1 is open; a ready handoff decides every child'
}

@test "deferred: needs a note" {
	invalid deferred-without-note 'proj-12.2 is deferred without a note'
}

@test "deferred: a blank note does not count" {
	invalid deferred-blank-note 'proj-12.2 is deferred without a note'
}

@test "reparented: needs a to" {
	invalid reparented-without-to 'proj-12.3 is reparented without a `to`'
}

@test "sha: a short commit sha is refused" {
	invalid short-commit-sha "\$.children[0].commits[0]: '9fceb02' is not a full sha"
}

@test "sha: a short base is refused" {
	invalid short-base "\$.base: '4b825dc' is not a full sha"
}

@test "sha: an uppercase lane head is refused" {
	invalid uppercase-lane-head "\$.lane.head: '9FCEB02D0AE598E95DC970B74767F19372D61AF8' is not a full sha"
}

@test "prefix: the branch must carry the default prefix" {
	invalid other-prefix 'agent/proj-12-slug is not a worker branch (claude/...)'
}

@test "prefix: --config sets the prefix" {
	printf '{"branch_prefix": "agent/"}\n' >"$BATS_TEST_TMPDIR/control-room.json"
	run "$VALIDATE" --config "$BATS_TEST_TMPDIR/control-room.json" "$(fixture other-prefix)"
	[ "$status" -eq 0 ]
	run "$VALIDATE" --config "$BATS_TEST_TMPDIR/control-room.json" "$(fixture valid)"
	[ "$status" -eq 1 ]
	[[ "$output" == *"claude/proj-12-slug is not a worker branch (agent/...)"* ]]
}

@test "prefix: control-room.json at the repository root is found" {
	repo="$BATS_TEST_TMPDIR/repo"
	git init -q "$repo"
	mkdir "$repo/handoff"
	printf '{"branch_prefix": "agent/"}\n' >"$repo/control-room.json"
	cp "$(fixture other-prefix)" "$repo/handoff/proj-12.json"
	valid "$repo/handoff/proj-12.json"
}

@test "prefix: an invalid control-room.json is reported, not guessed around" {
	printf '{"branch_prefix": 3}\n' >"$BATS_TEST_TMPDIR/control-room.json"
	run "$VALIDATE" --config "$BATS_TEST_TMPDIR/control-room.json" "$(fixture valid)"
	[ "$status" -eq 1 ]
	[[ "$output" == *"control-room.json is not valid"* ]]
}

@test "input: a file that is not JSON is reported" {
	invalid not-json 'not JSON'
}

@test "input: a missing file is reported" {
	run "$VALIDATE" "$BATS_TEST_TMPDIR/nope.json"
	[ "$status" -eq 1 ]
	[[ "$output" == *"cannot read"* ]]
}

@test "usage: no file is a usage error" {
	run "$VALIDATE"
	[ "$status" -eq 2 ]
	[[ "$output" == *"usage:"* ]]
}

@test "usage: every problem in every file is reported, one line each" {
	run "$VALIDATE" "$(fixture misnamed)" "$(fixture ready-open-child)" "$(fixture valid)"
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ "${lines[0]}" == */misnamed/proj-99.json:* ]]
	[[ "${lines[1]}" == */ready-open-child/proj-12.json:* ]]
}
