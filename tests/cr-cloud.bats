#!/usr/bin/env bats
# Tests for runners/claude-code-cloud: cr-cloud against a fake agent that
# records its calls, and the setup script's promise to exit zero.

bats_require_minimum_version 1.5.0

CR_CLOUD="$BATS_TEST_DIRNAME/../runners/claude-code-cloud/cr-cloud"
SETUP="$BATS_TEST_DIRNAME/../runners/claude-code-cloud/setup.sh"

setup() {
	export CR_AGENT="$BATS_TEST_DIRNAME/fixtures/fake-agent"
	export FAKE_AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	unset CR_OPENING
	cd "$BATS_TEST_TMPDIR" || return 1
	printf 'EPIC proj-12: branch claude/proj-12-login, scope src/\n' >brief.md
}

@test "brief: runs claude -p <brief> --cloud <session>, with the brief unchanged" {
	run "$CR_CLOUD" brief https://claude.ai/code/session_01abc brief.md
	[ "$status" -eq 0 ]
	[ "$(jq -c .args "$FAKE_AGENT_LOG")" = \
		"$(jq -cn --arg b "$(cat brief.md)" '["-p", $b, "--cloud", "https://claude.ai/code/session_01abc"]')" ]
	[[ "$output" != *"not a brief"* ]]
}

@test "brief: a message of another shape goes through, with a warning" {
	printf 'Status?\n' >q.md
	run "$CR_CLOUD" brief session_01abc q.md
	[ "$status" -eq 0 ]
	[[ "$output" == *"not a brief"*"question"* ]]
	[ "$(jq -r '.args[1]' "$FAKE_AGENT_LOG")" = "Status?" ]
}

@test "brief: the CLI's failure is the command's failure" {
	FAKE_AGENT_EXIT=1 run "$CR_CLOUD" brief session_01abc brief.md
	[ "$status" -eq 1 ]
}

@test "brief: refuses a missing session, a missing brief or an empty one" {
	run "$CR_CLOUD" brief --help brief.md
	[ "$status" -eq 2 ]
	run "$CR_CLOUD" brief session_01abc none.md
	[ "$status" -eq 2 ]
	: >empty.md
	run "$CR_CLOUD" brief session_01abc empty.md
	[ "$status" -eq 2 ]
	[ ! -e "$FAKE_AGENT_LOG" ]
}

@test "opening: fills the kit's worker opening message for the profile" {
	run "$CR_CLOUD" opening backend
	[ "$status" -eq 0 ]
	[[ "$output" == *"profile \`backend\`"* ]]
	[[ "$output" == *"WORKER backend READY"* ]]
	[[ "$output" == *"pull request against main"* ]]
	[[ "$output" != *"<profile>"* ]]
	[[ "$output" != *"<integration-branch>"* ]]
	[[ "$output" != *"<main-branches>"* ]]
}

@test "opening: takes the integration branch from control-room.json" {
	git init -q repo
	printf '{"integration_branch": "develop"}\n' >repo/control-room.json
	cd repo
	run "$CR_CLOUD" opening backend
	[ "$status" -eq 0 ]
	[[ "$output" == *"pull request against develop"* ]]
	[[ "$output" == *"push develop or a tag"* ]]
}

@test "opening: refuses a bad profile" {
	run "$CR_CLOUD" opening Backend
	[ "$status" -eq 2 ]
}

@test "setup.sh: exits zero even when every install fails" {
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir "$bin"
	printf '#!/bin/sh\nexit 1\n' >"$bin/apt-get"
	printf '#!/bin/sh\nexit 1\n' >"$bin/python3"
	chmod +x "$bin/apt-get" "$bin/python3"
	run env PATH="$bin" CR_PROFILE=backend "$(command -v bash)" "$SETUP"
	[ "$status" -eq 0 ]
	[[ "$output" == *"jq install failed"* ]]
	[[ "$output" == *"jsonschema install failed"* ]]
	[[ "$output" == *"done for profile backend"* ]]
}

@test "usage: an unknown command prints the usage" {
	run "$CR_CLOUD" merge
	[ "$status" -eq 2 ]
	[[ "$output" == *"cr-cloud brief <session> <brief.md>"* ]]
}
