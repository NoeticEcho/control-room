#!/usr/bin/env bats
# Tests for runners/claude-code-cloud: cr-cloud against a fake agent that
# records its calls, the routine template's shape, and the setup script's
# promise to exit zero.
# bats sets $stderr (SC2154).
# shellcheck disable=SC2154

bats_require_minimum_version 1.5.0

CR_CLOUD="$BATS_TEST_DIRNAME/../runners/claude-code-cloud/cr-cloud"
SETUP="$BATS_TEST_DIRNAME/../runners/claude-code-cloud/setup.sh"
ROUTINE="$BATS_TEST_DIRNAME/../runners/claude-code-cloud/new-worker.routine.json"

setup() {
	export CR_AGENT="$BATS_TEST_DIRNAME/fixtures/fake-agent"
	export FAKE_AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	# What claude -p --cloud --output-format json prints on success
	# (code.claude.com/docs/en/claude-code-on-the-web, "Output and errors").
	export FAKE_AGENT_STDOUT='{"ok":true,"session_id":"session_01abc","url":"https://claude.ai/code/session_01abc"}'
	unset CR_OPENING CR_ROUTINE CR_PREAMBLE FAKE_AGENT_STDERR FAKE_AGENT_EXIT
	cd "$BATS_TEST_TMPDIR" || return 1
	printf 'EPIC proj-12: branch claude/proj-12-login, scope src/\n' >brief.md
}

# new_worker [options]: cr-cloud new for profile backend with the required
# options, and any others given
new_worker() {
	run --separate-stderr "$CR_CLOUD" new backend brief.md --environment env_test \
		--repository https://example.invalid/o/r.git --model claude-sonnet-5-5 "$@"
}

@test "brief: runs claude -p <brief> --cloud <session> --output-format json, with the brief unchanged" {
	run "$CR_CLOUD" brief https://claude.ai/code/session_01abc brief.md
	[ "$status" -eq 0 ]
	[ "$(jq -c .args "$FAKE_AGENT_LOG")" = \
		"$(jq -cn --arg b "$(cat brief.md)" '["-p", $b, "--cloud", "https://claude.ai/code/session_01abc", "--output-format", "json"]')" ]
	[[ "$output" == *"delivered to https://claude.ai/code/session_01abc"* ]]
	[[ "$output" != *"not a brief"* ]]
}

@test "brief: a message of another shape goes through, with a warning" {
	printf 'Status?\n' >q.md
	run "$CR_CLOUD" brief session_01abc q.md
	[ "$status" -eq 0 ]
	[[ "$output" == *"not a brief"*"question"* ]]
	[ "$(jq -r '.args[1]' "$FAKE_AGENT_LOG")" = "Status?" ]
}

@test "brief: a send that fails says so at once, exit 3, with the reason and what to tell the owner" {
	FAKE_AGENT_STDOUT='{"ok":false,"session_id":"session_01abc","error":"Session expired"}' FAKE_AGENT_EXIT=1 \
		run --separate-stderr "$CR_CLOUD" brief session_01abc brief.md
	[ "$status" -eq 3 ]
	[[ "$stderr" == *"NOT delivered to session_01abc: Session expired"* ]]
	[[ "$stderr" == *"tell the owner first"* ]]
	[[ "$stderr" == *"claude auth login"* ]]
}

@test "brief: a configuration error with no JSON is a failed delivery too" {
	FAKE_AGENT_STDOUT='' FAKE_AGENT_EXIT=1 FAKE_AGENT_STDERR='Error: Unable to get organization UUID' \
		run --separate-stderr "$CR_CLOUD" brief session_01abc brief.md
	[ "$status" -eq 3 ]
	[[ "$stderr" == *"Unable to get organization UUID"* ]]
	[[ "$stderr" == *"NOT delivered"*"exited 1 without a delivery result"* ]]
}

@test "brief: success without a delivery result is not taken on trust" {
	FAKE_AGENT_STDOUT='Sent to cloud session.' run --separate-stderr "$CR_CLOUD" brief session_01abc brief.md
	[ "$status" -eq 3 ]
	[[ "$stderr" == *"NOT delivered"* ]]
}

@test "routine template: valid JSON, one user event, a persistent session, every placeholder once" {
	jq -e . "$ROUTINE" >/dev/null
	[ "$(jq -r .persist_session "$ROUTINE")" = true ]
	[ "$(jq '.job_config.ccr.events | length' "$ROUTINE")" -eq 1 ]
	[ "$(jq -r '.job_config.ccr.events[0].message.role' "$ROUTINE")" = user ]
	[ "$(jq -r '.job_config.ccr.session_context.allowed_tools | type' "$ROUTINE")" = array ]
	for p in '<name>' '<run-once-at>' '<environment-id>' '<model>' '<repository-url>' '<event-uuid>' '<message>'; do
		[ "$(jq --arg p "$p" '[.. | strings | select(. == $p)] | length' "$ROUTINE")" -eq 1 ] || { echo "placeholder $p"; return 1; }
	done
	[ "$(jq '[.. | strings | select(test("^<.*>$"))] | length' "$ROUTINE")" -eq 7 ]
	# No credential of any kind has a place in it.
	run ! grep -i -E 'token|secret|api[_-]?key|authorization' "$ROUTINE"
}

@test "new: fills every placeholder, and leaves the template's shape" {
	new_worker --at 2026-09-29T10:02:00Z
	[ "$status" -eq 0 ]
	body=$output
	[ "$(jq '[.. | strings | select(test("^<.*>$"))] | length' <<<"$body")" -eq 0 ]
	[ "$(jq -r .name <<<"$body")" = "worker backend: proj-12" ]
	[ "$(jq -r .run_once_at <<<"$body")" = 2026-09-29T10:02:00Z ]
	[ "$(jq -r .job_config.ccr.environment_id <<<"$body")" = env_test ]
	[ "$(jq -r .job_config.ccr.session_context.model <<<"$body")" = claude-sonnet-5-5 ]
	[ "$(jq -r '.job_config.ccr.session_context.sources[0].url' <<<"$body")" = https://example.invalid/o/r.git ]
	[[ "$(jq -r '.job_config.ccr.events[0].uuid' <<<"$body")" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
	[ "$(jq -S 'del(.. | strings)' "$ROUTINE")" = "$(jq -S 'del(.. | strings)' <<<"$body")" ]
}

@test "new: one user message, the preamble, then the opening, then the brief unchanged" {
	new_worker
	[ "$status" -eq 0 ]
	message=$(jq -r '.job_config.ccr.events[0].message.content' <<<"$output")
	[[ "$message" == "I, the owner, have authorised the coordinator once to create worker sessions"* ]]
	[[ "$message" == *"You are a cloud worker for this repository, profile \`backend\`"* ]]
	[[ "$message" != *"<profile>"* ]]
	[ "$(printf '%s' "$message" | tail -n 1)" = "$(cat brief.md)" ]
}

@test "new: run_once_at is two minutes ahead in UTC by default, --name overrides the name" {
	new_worker --name "backend again"
	[ "$status" -eq 0 ]
	at=$(jq -r .run_once_at <<<"$output")
	ahead=$(jq -rn --arg at "$at" '($at | fromdate) - now | floor')
	[ "$ahead" -ge 60 ] && [ "$ahead" -le 180 ]
	[ "$(jq -r .name <<<"$output")" = "backend again" ]
}

@test "new: sends nothing and prints no credential from the environment" {
	ANTHROPIC_API_KEY=model-test-not-a-key GITHUB_TOKEN=gh-test-not-a-token new_worker
	[ "$status" -eq 0 ]
	[ ! -e "$FAKE_AGENT_LOG" ]
	[[ "$output" != *"not-a-key"* && "$output" != *"not-a-token"* ]]
}

@test "new: refuses a missing option, a bad time, a bad profile or a missing brief" {
	run "$CR_CLOUD" new backend brief.md --repository r --model m
	[ "$status" -eq 2 ]
	[[ "$output" == *"--environment is required"* ]]
	run "$CR_CLOUD" new backend brief.md --environment e --model m
	[ "$status" -eq 2 ]
	run "$CR_CLOUD" new backend brief.md --environment e --repository r
	[ "$status" -eq 2 ]
	[[ "$output" == *"--model is required"* ]]
	new_worker --at tomorrow
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"UTC time"* ]]
	run "$CR_CLOUD" new Backend brief.md --environment e --repository r --model m
	[ "$status" -eq 2 ]
	run "$CR_CLOUD" new backend none.md --environment e --repository r --model m
	[ "$status" -eq 2 ]
	run "$CR_CLOUD" new backend brief.md --environment e --repository r --model m --colour red
	[ "$status" -eq 2 ]
}

@test "new: CR_ROUTINE replaces the template" {
	printf '{"n": "<name>", "m": "<message>"}\n' >r.json
	CR_ROUTINE=r.json new_worker
	[ "$status" -eq 0 ]
	[ "$(jq -r .n <<<"$output")" = "worker backend: proj-12" ]
	printf 'not json' >r.json
	CR_ROUTINE=r.json new_worker
	[ "$status" -ne 0 ]
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
