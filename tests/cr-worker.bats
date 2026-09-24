#!/usr/bin/env bats
# Tests for runners/local/cr-worker. Each test clones a throwaway repository
# from a bare "origin" and runs workers with a fake agent that records what it
# was asked (tests/fixtures/fake-agent).

bats_require_minimum_version 1.5.0

CR_WORKER="$BATS_TEST_DIRNAME/../runners/local/cr-worker"

setup() {
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
	export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
	origin="$BATS_TEST_TMPDIR/origin.git"
	repo="$BATS_TEST_TMPDIR/repo"
	git init -q --bare -b main "$origin"
	git clone -q "$origin" "$repo" 2>/dev/null
	git -C "$repo" commit -q --allow-empty -m init
	git -C "$repo" push -q origin main
	export CR_WORKTREES="$BATS_TEST_TMPDIR/workers"
	export CR_AGENT="$BATS_TEST_DIRNAME/fixtures/fake-agent"
	export FAKE_AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
	unset CR_AGENT_ARGS CR_OPENING CR_PROFILE
	cd "$repo"
}

# call <n>: the n-th recorded agent call (1-based), as JSON
call() {
	sed -n "${1}p" "$FAKE_AGENT_LOG"
}

session_of() {
	cat "$(git -C "$CR_WORKTREES/$1" rev-parse --absolute-git-dir)/cr-worker/session-id"
}

# ---- new -------------------------------------------------------------------

@test "new: makes a worktree on <prefix><epic>-<slug> from origin's integration branch" {
	run "$CR_WORKER" new backend proj-12 login
	[ "$status" -eq 0 ]
	wt="$CR_WORKTREES/backend"
	[ "$(git -C "$wt" symbolic-ref --short HEAD)" = claude/proj-12-login ]
	[ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$repo" rev-parse origin/main)" ]
}

@test "new: the branch does not track the integration branch" {
	"$CR_WORKER" new backend proj-12 login
	run git -C "$CR_WORKTREES/backend" config branch.claude/proj-12-login.merge
	[ "$status" -ne 0 ]
}

@test "new: starts from origin's latest integration branch, not the local one" {
	other="$BATS_TEST_TMPDIR/other"
	git clone -q "$origin" "$other"
	git -C "$other" commit -q --allow-empty -m newer
	git -C "$other" push -q origin main
	"$CR_WORKER" new backend proj-12 login
	[ "$(git -C "$CR_WORKTREES/backend" rev-parse HEAD)" = "$(git -C "$other" rev-parse HEAD)" ]
}

@test "new: without a remote, starts from the local integration branch" {
	git -C "$repo" remote remove origin
	"$CR_WORKER" new backend proj-12 login
	[ "$(git -C "$CR_WORKTREES/backend" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ]
}

@test "new: writes the profile into the worker's environment, outside the worktree's files" {
	"$CR_WORKER" new backend proj-12 login
	run "$CR_WORKER" env backend
	[ "$status" -eq 0 ]
	[ "$output" = "export CR_PROFILE=backend" ]
	[ -z "$(git -C "$CR_WORKTREES/backend" status --porcelain)" ]
}

@test "new: gives the worker a session id that is a version 4 UUID" {
	"$CR_WORKER" new backend proj-12 login
	[[ "$(session_of backend)" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

@test "new: refuses a profile that is not a profile name" {
	run "$CR_WORKER" new Backend proj-12 login
	[ "$status" -eq 2 ]
	[[ "$output" == *"must match"* ]]
	run "$CR_WORKER" new ../x proj-12 login
	[ "$status" -eq 2 ]
}

@test "new: refuses a branch that exists or is not a branch name" {
	git -C "$repo" branch claude/proj-12-login
	run "$CR_WORKER" new backend proj-12 login
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	run "$CR_WORKER" new backend 'proj 13' login
	[ "$status" -eq 2 ]
	[[ "$output" == *"not a valid branch name"* ]]
}

@test "new: the next epic reuses a clean worktree and keeps the session" {
	"$CR_WORKER" new backend proj-12 login
	first=$(session_of backend)
	run "$CR_WORKER" new backend proj-13 logout
	[ "$status" -eq 0 ]
	[ "$(git -C "$CR_WORKTREES/backend" symbolic-ref --short HEAD)" = claude/proj-13-logout ]
	[ "$(session_of backend)" = "$first" ]
}

@test "new: the next epic is refused while the worktree has uncommitted work" {
	"$CR_WORKER" new backend proj-12 login
	echo wip >"$CR_WORKTREES/backend/wip.txt"
	run "$CR_WORKER" new backend proj-13 logout
	[ "$status" -eq 1 ]
	[[ "$output" == *"uncommitted changes"* ]]
}

@test "new: control-room.json sets the integration branch, the prefix and the variable" {
	git -C "$repo" switch -q -c develop
	git -C "$repo" push -q origin develop
	printf '{"integration_branch": "develop", "branch_prefix": "agent/", "profile_variable": "WORKER_PROFILE"}\n' \
		>"$repo/control-room.json"
	"$CR_WORKER" new backend proj-12 login
	[ "$(git -C "$CR_WORKTREES/backend" symbolic-ref --short HEAD)" = agent/proj-12-login ]
	[ "$(git -C "$CR_WORKTREES/backend" rev-parse HEAD)" = "$(git -C "$repo" rev-parse origin/develop)" ]
	[ "$("$CR_WORKER" env backend)" = "export WORKER_PROFILE=backend" ]
}

@test "new: an invalid control-room.json is refused" {
	printf '{"branch_prefix": 3}\n' >"$repo/control-room.json"
	run "$CR_WORKER" new backend proj-12 login
	[ "$status" -eq 1 ]
	[[ "$output" == *"control-room.json is not valid"* ]]
}

@test "new: outside a repository it says so" {
	cd "$BATS_TEST_TMPDIR"
	run "$CR_WORKER" new backend proj-12 login
	[ "$status" -eq 1 ]
	[[ "$output" == *"inside the repository"* ]]
}

# ---- start -----------------------------------------------------------------

@test "start: runs the agent in the worktree, with the profile set, on a new session" {
	"$CR_WORKER" new backend proj-12 login
	run "$CR_WORKER" start backend
	[ "$status" -eq 0 ]
	[[ "$output" == *"fake agent"* ]]
	[ "$(call 1 | jq -r .cwd)" = "$CR_WORKTREES/backend" ]
	[ "$(call 1 | jq -r .profile)" = backend ]
	[ "$(call 1 | jq -r '.args[0]')" = -p ]
	[ "$(call 1 | jq -r '.args[2]')" = --session-id ]
	[ "$(call 1 | jq -r '.args[3]')" = "$(session_of backend)" ]
}

@test "start: the opening message is filled in for this worker" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" start backend
	opening=$(call 1 | jq -r '.args[1]')
	[[ "$opening" == *'profile `backend`'* ]]
	[[ "$opening" == *'`CR_PROFILE` is `backend`'* ]]
	[[ "$opening" == *'`claude/proj-12-login`'* ]]
	[[ "$opening" == *"pull request against main"* ]]
	[[ "$opening" == *"WORKER backend READY"* ]]
	[[ "$opening" != *"<profile>"* ]]
	[[ "$opening" != *"<integration-branch>"* ]]
	[[ "$opening" != *"<branch>"* ]]
}

@test "start: CR_OPENING replaces the opening message, CR_AGENT_ARGS are passed on" {
	printf 'Hello <profile> on <integration-branch>.\n' >"$BATS_TEST_TMPDIR/opening.md"
	"$CR_WORKER" new backend proj-12 login
	CR_OPENING="$BATS_TEST_TMPDIR/opening.md" CR_AGENT_ARGS="--permission-mode acceptEdits" \
		"$CR_WORKER" start backend
	[ "$(call 1 | jq -r '.args[1]')" = "Hello backend on main." ]
	[ "$(call 1 | jq -c '.args[4:]')" = '["--permission-mode","acceptEdits"]' ]
}

@test "start: a worker is started once" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" start backend
	run "$CR_WORKER" start backend
	[ "$status" -eq 1 ]
	[[ "$output" == *"already started"* ]]
}

@test "start: the agent's failure is the command's failure, and the worker stays unstarted" {
	"$CR_WORKER" new backend proj-12 login
	FAKE_AGENT_EXIT=3 run "$CR_WORKER" start backend
	[ "$status" -eq 3 ]
	run "$CR_WORKER" brief backend /dev/null
	[[ "$output" == *"not started"* ]]
}

@test "start: an unknown worker is refused" {
	run "$CR_WORKER" start backend
	[ "$status" -eq 1 ]
	[[ "$output" == *"no worker 'backend'"* ]]
}

# ---- brief -----------------------------------------------------------------

@test "brief: delivers the brief as the next user message in the same session" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" start backend
	printf 'EPIC proj-12: branch claude/proj-12-login, scope src/\n\nWhy: because.\n' >"$BATS_TEST_TMPDIR/brief.md"
	run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/brief.md"
	[ "$status" -eq 0 ]
	[ "$(call 2 | jq -r '.args[0]')" = -p ]
	[ "$(call 2 | jq -r '.args[1]')" = "$(cat "$BATS_TEST_TMPDIR/brief.md")" ]
	[ "$(call 2 | jq -r '.args[2]')" = --resume ]
	[ "$(call 2 | jq -r '.args[3]')" = "$(session_of backend)" ]
	[ "$(call 2 | jq -r .cwd)" = "$CR_WORKTREES/backend" ]
	[ "$(call 2 | jq -r .profile)" = backend ]
	[[ "$output" != *"not a brief"* ]]
}

@test "brief: a message of another shape goes through, with a warning that it is a question" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" start backend
	printf 'Where are you?\n' >"$BATS_TEST_TMPDIR/q.md"
	run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/q.md"
	[ "$status" -eq 0 ]
	[[ "$output" == *"not a brief"*"question"* ]]
	[ "$(call 2 | jq -r '.args[1]')" = "Where are you?" ]
}

@test "brief: the agent's output is shown and kept in the worker's log" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" start backend
	printf 'EPIC proj-12: branch claude/proj-12-login, scope src/\n' >"$BATS_TEST_TMPDIR/brief.md"
	run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/brief.md"
	[[ "$output" == *"fake agent: 4 arguments"* ]]
	log="$(git -C "$CR_WORKTREES/backend" rev-parse --absolute-git-dir)/cr-worker/log"
	[ "$(grep -c 'fake agent' "$log")" -eq 2 ]
	[ -z "$(git -C "$CR_WORKTREES/backend" status --porcelain)" ]
}

@test "brief: the agent's failure is the command's failure" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" start backend
	printf 'EPIC proj-12: branch claude/proj-12-login, scope src/\n' >"$BATS_TEST_TMPDIR/brief.md"
	FAKE_AGENT_EXIT=5 run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/brief.md"
	[ "$status" -eq 5 ]
}

@test "brief: refuses a worker that is not started, and a missing or empty brief" {
	"$CR_WORKER" new backend proj-12 login
	printf 'EPIC x\n' >"$BATS_TEST_TMPDIR/brief.md"
	run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/brief.md"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not started"* ]]
	"$CR_WORKER" start backend
	run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/none.md"
	[ "$status" -eq 2 ]
	: >"$BATS_TEST_TMPDIR/empty.md"
	run "$CR_WORKER" brief backend "$BATS_TEST_TMPDIR/empty.md"
	[ "$status" -eq 2 ]
	[ "$(wc -l <"$FAKE_AGENT_LOG")" -eq 1 ]
}

@test "brief: works from inside another worker's worktree" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" new docs proj-13 guide
	"$CR_WORKER" start docs
	printf 'EPIC proj-13: branch claude/proj-13-guide, scope docs/\n' >"$BATS_TEST_TMPDIR/brief.md"
	cd "$CR_WORKTREES/backend"
	run "$CR_WORKER" brief docs "$BATS_TEST_TMPDIR/brief.md"
	[ "$status" -eq 0 ]
	[ "$(call 2 | jq -r .cwd)" = "$CR_WORKTREES/docs" ]
	[ "$(call 2 | jq -r .profile)" = docs ]
}

# ---- two workers, and the rest ---------------------------------------------

@test "workers: two profiles get two worktrees and two sessions" {
	"$CR_WORKER" new backend proj-12 login
	"$CR_WORKER" new docs proj-13 guide
	[ "$(session_of backend)" != "$(session_of docs)" ]
	[ "$("$CR_WORKER" path backend)" = "$CR_WORKTREES/backend" ]
	[ "$("$CR_WORKER" path docs)" = "$CR_WORKTREES/docs" ]
}

@test "usage: no command or an unknown one prints the usage" {
	run "$CR_WORKER"
	[ "$status" -eq 2 ]
	[[ "$output" == *"cr-worker new <profile> <epic> <slug>"* ]]
	run "$CR_WORKER" merge backend
	[ "$status" -eq 2 ]
	run "$CR_WORKER" new backend
	[ "$status" -eq 2 ]
}
