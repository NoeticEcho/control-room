#!/usr/bin/env bats
# Tests for runners/e2b/cr-e2b, against a fake e2b SDK that records its calls
# (tests/fixtures/fake-e2b). No key and no network: the live path is
# unverified here.
# Shell text under test sits in single quotes (SC2016).
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

CR_E2B="$BATS_TEST_DIRNAME/../runners/e2b/cr-e2b"

setup() {
	export PYTHONPATH="$BATS_TEST_DIRNAME/fixtures/fake-e2b" PYTHONDONTWRITEBYTECODE=1
	export FAKE_E2B_LOG="$BATS_TEST_TMPDIR/e2b.log"
	export FAKE_E2B_FILES="$BATS_TEST_TMPDIR/sandbox"
	export E2B_API_KEY=e2b-test-not-a-key ANTHROPIC_API_KEY=model-test-not-a-key
	unset GITHUB_TOKEN FAKE_E2B_FAIL
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	printf 'EPIC proj-12: branch claude/proj-12-login, scope src/\n\nWhy: because.\n' >"$BATS_TEST_TMPDIR/brief.md"
}

start() {
	run python3 "$CR_E2B" start --repo https://example.invalid/o/r.git --profile backend \
		--brief "$BATS_TEST_TMPDIR/brief.md" "$@"
}

# refute <command...>: fails when the command succeeds (a bare `!` does not
# fail a bats test unless it is the last command)
refute() {
	if "$@"; then
		echo "expected to fail: $*"
		return 1
	fi
}

# calls <name>: the recorded calls of that name, one JSON per line
calls() {
	jq -c --arg c "$1" 'select(.call == $c)' "$FAKE_E2B_LOG"
}

# command <n>: the n-th command run in the sandbox (1-based)
command_n() {
	calls commands.run | sed -n "${1}p" | jq -r .cmd
}

@test "start: creates the sandbox from the template, with the profile and the model key" {
	start --template my-stack --timeout 7200
	[ "$status" -eq 0 ]
	create=$(calls Sandbox.create)
	[ "$(jq -r .template <<<"$create")" = my-stack ]
	[ "$(jq -r .timeout <<<"$create")" = 7200 ]
	[ "$(jq -r .envs.CR_PROFILE <<<"$create")" = backend ]
	[ "$(jq -r .envs.ANTHROPIC_API_KEY <<<"$create")" = model-test-not-a-key ]
	[ "$(jq -r .api_key_set <<<"$create")" = true ]
	[[ "$output" == *"sandbox sbx-fake-1: profile backend"* ]]
}

@test "start: clones on the integration branch, installs the agent, then starts it" {
	start
	[ "$status" -eq 0 ]
	cmds=$(calls commands.run | jq -r .cmd)
	clone=$(grep -n '^git clone' <<<"$cmds" | cut -d: -f1)
	install=$(grep -n 'claude.ai/install.sh' <<<"$cmds" | cut -d: -f1)
	agent=$(grep -n '^nohup' <<<"$cmds" | cut -d: -f1)
	[ "$clone" -lt "$install" ] && [ "$install" -lt "$agent" ]
	[[ "$(sed -n "${clone}p" <<<"$cmds")" == "git clone --branch main https://example.invalid/o/r.git /home/user/repo" ]]
}

@test "start: the agent runs headless, opening then brief, in one session" {
	start
	[ "$status" -eq 0 ]
	session=$(cat "$FAKE_E2B_FILES/home/user/.cr/session-id")
	[[ "$session" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
	agent=$(calls commands.run | jq -r .cmd | grep '^nohup')
	[[ "$agent" == *'claude -p "$(cat /home/user/.cr/opening.md)" --session-id '"$session"* ]]
	[[ "$agent" == *'claude -p "$(cat /home/user/.cr/brief-1.md)" --resume '"$session"* ]]
	[[ "$agent" == *"cd /home/user/repo"* ]]
	[[ "$agent" == *">>/home/user/.cr/log 2>&1 </dev/null &" ]]
	[[ "$output" == *"agent started: session $session"* ]]
}

@test "start: the brief is delivered unchanged, and the opening is filled in" {
	start --integration develop --prefix agent/
	[ "$status" -eq 0 ]
	diff "$BATS_TEST_TMPDIR/brief.md" "$FAKE_E2B_FILES/home/user/.cr/brief-1.md"
	opening=$(cat "$FAKE_E2B_FILES/home/user/.cr/opening.md")
	[[ "$opening" == *'profile `backend`'* ]]
	[[ "$opening" == *'`CR_PROFILE` is `backend`'* ]]
	[[ "$opening" == *"pull request against develop"* ]]
	[[ "$opening" == *"agent/<id>-<slug>"* ]]
	[[ "$opening" != *"<profile>"* ]]
	[[ "$opening" != *"<integration-branch>"* ]]
}

@test "start: --agent-args reaches every agent turn; the default is acceptEdits" {
	start
	[ "$(calls commands.run | jq -r .cmd | grep -o -- '--permission-mode acceptEdits' | wc -l)" -eq 2 ]
	: >"$FAKE_E2B_LOG"
	start --agent-args "--permission-mode auto --permission-prompts none"
	[ "$(calls commands.run | jq -r .cmd | grep -o -- '--permission-prompts none' | wc -l)" -eq 2 ]
}

@test "start: no key is written to a file or put on a command line" {
	export GITHUB_TOKEN=gh-test-not-a-token
	start
	[ "$status" -eq 0 ]
	[ "$(calls Sandbox.create | jq -r .envs.GITHUB_TOKEN)" = gh-test-not-a-token ]
	refute grep -rq -e model-test-not-a-key -e gh-test-not-a-token -e e2b-test-not-a-key "$FAKE_E2B_FILES"
	{ calls commands.run; calls files.write; } >"$BATS_TEST_TMPDIR/sent"
	[ -s "$BATS_TEST_TMPDIR/sent" ]
	refute grep -q -e model-test-not-a-key -e gh-test-not-a-token -e e2b-test-not-a-key "$BATS_TEST_TMPDIR/sent"
	[[ "$(command_n 1)" == *'credential.helper'*'password=$GITHUB_TOKEN'* ]]
}

@test "start: without GITHUB_TOKEN there is no credential helper" {
	start
	calls commands.run >"$BATS_TEST_TMPDIR/cmds"
	refute grep -q credential.helper "$BATS_TEST_TMPDIR/cmds"
	[ "$(calls Sandbox.create | jq -r '.envs | has("GITHUB_TOKEN")')" = false ]
}

@test "start: the git identity is the one given, or the local one" {
	start --git-name 'A Worker' --git-email worker@example.invalid
	calls commands.run | jq -r .cmd | grep -q "user.name 'A Worker' && git config --global user.email worker@example.invalid"
}

@test "start: a missing key is refused before any sandbox is created" {
	unset E2B_API_KEY
	start
	[ "$status" -eq 2 ]
	[[ "$output" == *"E2B_API_KEY is not set"* ]]
	export E2B_API_KEY=x
	unset ANTHROPIC_API_KEY
	start
	[ "$status" -eq 2 ]
	[[ "$output" == *"ANTHROPIC_API_KEY is not set"* ]]
	[ ! -s "$FAKE_E2B_LOG" ]
}

@test "start: a bad profile, a missing brief or an empty one is refused" {
	start --profile Backend
	[ "$status" -eq 2 ]
	[[ "$output" == *"must match"* ]]
	run python3 "$CR_E2B" start --repo r --profile backend --brief "$BATS_TEST_TMPDIR/none.md"
	[ "$status" -eq 2 ]
	[[ "$output" == *"cannot read the brief"* ]]
	: >"$BATS_TEST_TMPDIR/empty.md"
	run python3 "$CR_E2B" start --repo r --profile backend --brief "$BATS_TEST_TMPDIR/empty.md"
	[ "$status" -eq 2 ]
	[ ! -s "$FAKE_E2B_LOG" ]
}

@test "start: a failing step stops the runner and says which" {
	FAKE_E2B_FAIL="git clone" start
	[ "$status" -eq 1 ]
	[[ "$output" == *"cloning https://example.invalid/o/r.git failed (exit 1)"* ]]
	calls commands.run >"$BATS_TEST_TMPDIR/cmds"
	refute grep -q nohup "$BATS_TEST_TMPDIR/cmds"
}

@test "start: without the SDK it says how to get it" {
	PYTHONPATH="$BATS_TEST_TMPDIR/empty" start
	[ "$status" -eq 2 ]
	[[ "$output" == *"pip install e2b"* ]]
}

@test "brief: delivers a follow-up as a user message in the same session" {
	start
	session=$(cat "$FAKE_E2B_FILES/home/user/.cr/session-id")
	printf 'EPIC proj-13: branch claude/proj-13-next, scope src/\n' >"$BATS_TEST_TMPDIR/next.md"
	: >"$FAKE_E2B_LOG"
	run python3 "$CR_E2B" brief --sandbox sbx-fake-1 --brief "$BATS_TEST_TMPDIR/next.md"
	[ "$status" -eq 0 ]
	[ "$(calls Sandbox.connect | jq -r .sandbox_id)" = sbx-fake-1 ]
	written=$(calls files.write | jq -r .path)
	[[ "$written" == /home/user/.cr/brief-*.md ]]
	diff "$BATS_TEST_TMPDIR/next.md" "$FAKE_E2B_FILES$written"
	agent=$(calls commands.run | jq -r .cmd)
	[[ "$agent" == *"claude -p \"\$(cat $written)\" --resume $session"* ]]
	[[ "$agent" != *"--session-id"* ]]
	[[ "$output" != *"not a brief"* ]]
}

@test "brief: a message of another shape goes through, with a warning" {
	start
	printf 'Where are you?\n' >"$BATS_TEST_TMPDIR/q.md"
	run python3 "$CR_E2B" brief --sandbox sbx-fake-1 --brief "$BATS_TEST_TMPDIR/q.md"
	[ "$status" -eq 0 ]
	[[ "$output" == *"not a brief"*"question"* ]]
}

@test "log and kill: read the agent's log, and kill the sandbox" {
	start
	printf 'WORKER backend READY\n' >"$FAKE_E2B_FILES/home/user/.cr/log"
	run python3 "$CR_E2B" log --sandbox sbx-fake-1
	[ "$status" -eq 0 ]
	[ "$output" = "WORKER backend READY" ]
	run python3 "$CR_E2B" kill --sandbox sbx-fake-1
	[ "$status" -eq 0 ]
	[ "$(calls kill | jq -r .sandbox_id)" = sbx-fake-1 ]
}

@test "usage: a command is required" {
	run python3 "$CR_E2B"
	[ "$status" -eq 2 ]
	[[ "$output" == *"usage: cr-e2b"* ]]
}

@test "sdk: the real e2b SDK has every call the fake stands in for" {
	# CI installs the SDK and sets CR_REQUIRE_E2B_SDK=1, so there this runs.
	if ! PYTHONPATH="${E2B_SDK_PATH:-}" python3 -c 'import e2b' 2>/dev/null; then
		if [ -n "${CR_REQUIRE_E2B_SDK:-}" ]; then
			echo "the e2b SDK is not installed, and CR_REQUIRE_E2B_SDK is set"
			return 1
		fi
		skip "the e2b SDK is not installed; CI runs this"
	fi
	run env PYTHONPATH="${E2B_SDK_PATH:-}" python3 "$BATS_TEST_DIRNAME/fixtures/e2b-contract.py"
	echo "$output"
	[ "$status" -eq 0 ]
}
