#!/usr/bin/env bats
# Tests for plugin/scripts/ready-check: a bare origin and a clone, a worker
# branch that ends in a READY sha, and each way a READY claim can be wrong.

bats_require_minimum_version 1.5.0

CHECK="$BATS_TEST_DIRNAME/../plugin/scripts/ready-check"

setup() {
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
	export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	origin="$BATS_TEST_TMPDIR/origin.git"
	repo="$BATS_TEST_TMPDIR/repo"
	git init -q --bare -b main "$origin"
	git init -q -b main "$repo"
	cd "$repo" || return 1
	git remote add origin "$origin"
	mkdir -p src/app docs ci
	echo one >src/app/a.txt
	echo ci >ci/check.yml
	echo doc >docs/readme.md
	git add . && git commit -qm base
	git push -q origin main
	git switch -qc claude/web-4-x
	echo two >src/app/b.txt
	git add . && git commit -qm work
	ready=$(git rev-parse HEAD)
	git push -q origin claude/web-4-x
}

# commit_on <branch> <file> <text>: a commit on <branch>, pushed
commit_on() {
	git switch -q "$1"
	mkdir -p "$(dirname "$2")"
	echo "$3" >"$2"
	git add "$2" && git commit -qm "$2"
	git push -q origin "$1"
}

check() {
	run "$CHECK" "$@"
}

@test "the head is the READY sha, inside the scope, merges cleanly: exit 0" {
	check --scope 'src/*' "$ready" claude/web-4-x
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "ok: origin/claude/web-4-x ends at the READY sha" ]
	[[ "$output" == *"ok: 1 file(s) changed, all inside the scope"* ]]
	[[ "$output" == *"ok: the READY sha merges into origin/main without a conflict"* ]]
	[[ "$output" != *FINDING* ]]
	[ "${lines[-1]}" = "ready-check: nothing found; go on with the checklist (read, merge --no-ff, check, push, CI)" ]
}

@test "already on the integration branch: exit 3, land nothing" {
	git switch -q main && git merge -q --no-ff --no-edit "$ready" && git push -q origin main
	check "$ready" claude/web-4-x
	[ "$status" -eq 3 ]
	[ "$output" = "ready-check: $ready is already on origin/main: land nothing" ]
}

@test "a file outside every scope pattern is a finding; * covers nested paths" {
	commit_on claude/web-4-x docs/extra.md more
	sha=$(git rev-parse HEAD)
	check --scope 'src/*' "$sha" claude/web-4-x
	[ "$status" -eq 1 ]
	[[ "$output" == *"FINDING outside scope: docs/extra.md"* ]]
	[[ "$output" != *"outside scope: src/app/b.txt"* ]]
	check --scope 'src/*' --scope 'docs/*' "$sha" claude/web-4-x
	[ "$status" -eq 0 ]
}

@test "a fenced path is a finding even inside the scope" {
	commit_on claude/web-4-x ci/check.yml changed
	sha=$(git rev-parse HEAD)
	check --scope '*' --fence 'ci/*' "$sha" claude/web-4-x
	[ "$status" -eq 1 ]
	[[ "$output" == *"FINDING fenced: ci/check.yml changed; it lands only with the person's quoted approval"* ]]
	[[ "$output" != *"fenced: src/app/b.txt"* ]]
}

@test "no scope given: nothing is checked against the brief, and it says so" {
	check "$ready" claude/web-4-x
	[ "$status" -eq 0 ]
	[[ "$output" == *"info: 1 file(s) changed; no --scope given, so none was checked against the brief"* ]]
}

@test "moved past READY with only a merge of main: land the READY sha" {
	commit_on main docs/news.md landed
	git switch -q claude/web-4-x && git merge -q --no-edit main && git push -q origin claude/web-4-x
	check --scope 'src/*' "$ready" claude/web-4-x
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "ok: origin/claude/web-4-x moved 2 commit(s) past READY, but they only merged main: land the READY sha"* ]]
}

@test "moved past READY with a change: a finding, ask for a new READY" {
	commit_on claude/web-4-x src/app/c.txt later
	check --scope 'src/*' "$ready" claude/web-4-x
	[ "$status" -eq 1 ]
	[ "${lines[0]}" = "FINDING origin/claude/web-4-x moved 1 commit(s) past READY and they change the tree: land nothing from it until the worker writes a new READY line" ]
}

@test "a READY sha that is not on the branch is a finding" {
	git switch -q main
	echo side >src/app/side.txt && git add . && git commit -qm side
	other=$(git rev-parse HEAD)
	git reset -q --hard origin/main
	check "$other" claude/web-4-x
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "FINDING $other is not on origin/claude/web-4-x"* ]]
}

@test "a conflict with the integration branch is a finding that names the file" {
	commit_on main src/app/b.txt theirs
	check --scope 'src/*' "$ready" claude/web-4-x
	[ "$status" -eq 1 ]
	[[ "$output" == *"FINDING the READY sha conflicts with origin/main in: src/app/b.txt"* ]]
}

@test "two landings since the branch left: run the full check on the merge" {
	check "$ready" claude/web-4-x
	[[ "$output" == *"info: the branch left origin/main 0 landing(s) ago"* ]]
	commit_on main docs/one.md 1
	commit_on main docs/two.md 2
	check "$ready" claude/web-4-x
	[ "$status" -eq 0 ]
	[[ "$output" == *"info: the branch left origin/main 2 landings ago: run the full check on the merge, not only the pull request's CI"* ]]
}

@test "--base and --remote name another integration branch and remote" {
	git remote rename origin up
	git push -q up main:develop
	git fetch -q up
	check --remote up --base develop "$ready" claude/web-4-x
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "ok: up/claude/web-4-x ends at the READY sha" ]
	[[ "$output" == *"merges into up/develop"* ]]
}

@test "usage: a short sha, a missing ref, a missing option value or no arguments exit 2" {
	check "${ready:0:12}" claude/web-4-x
	[ "$status" -eq 2 ]
	[[ "$output" == *"the READY sha must be the full 40-character sha"* ]]
	check "$ready" claude/nothing-here
	[ "$status" -eq 2 ]
	[ "$output" = "ready-check: no origin/claude/nothing-here: git fetch origin first" ]
	check --scope
	[ "$status" -eq 2 ]
	[ "$output" = "ready-check: --scope needs a value" ]
	check
	[ "$status" -eq 2 ]
	[[ "$output" == *"ready-check [--remote <name>]"* ]]
}

@test "it changes nothing: refs, index and working tree are as before" {
	commit_on main src/app/b.txt theirs
	git switch -q claude/web-4-x
	before=$(git for-each-ref; git status --porcelain; git worktree list)
	check --scope 'src/*' "$ready" claude/web-4-x
	after=$(git for-each-ref; git status --porcelain; git worktree list)
	[ "$before" = "$after" ]
}
