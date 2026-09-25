#!/usr/bin/env bats
# Tests for ci/local-ci, against a real git origin in a temporary directory
# and a fake gh (tests/fixtures/fake-gh) that records the statuses it is
# asked to post.

bats_require_minimum_version 1.5.0

LOCAL_CI="$BATS_TEST_DIRNAME/../ci/local-ci"

setup() {
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin"
	ln -s "$BATS_TEST_DIRNAME/fixtures/fake-gh" "$bin/gh"
	export PATH="$bin:$PATH"
	export FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log" FAKE_GH_DIR="$BATS_TEST_TMPDIR/gh"
	mkdir -p "$FAKE_GH_DIR"
	: >"$FAKE_GH_LOG"
	unset FAKE_GH_EXIT LOCAL_CI_NO_STATUS
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

	origin="$BATS_TEST_TMPDIR/origin.git"
	git init -q --bare -b main "$origin"
	seed="$BATS_TEST_TMPDIR/seed"
	git clone -q "$origin" "$seed" 2>/dev/null
	git -C "$seed" switch -q -c main
	printf 'exit 0\n' >"$seed/check.sh"
	printf 'build/\n' >"$seed/.gitignore"
	git -C "$seed" add check.sh .gitignore
	git -C "$seed" commit -q -m one
	git -C "$seed" push -q origin main
	work="$BATS_TEST_TMPDIR/work"
	git clone -q "$origin" "$work"

	state="$BATS_TEST_TMPDIR/state"
	export LOCAL_CI_CONFIG="$BATS_TEST_TMPDIR/config.json"
	jq -n --arg w "$work" --arg s "$state" '{state: $s, repos: [
		{name: "app", slug: "o/app", workdir: $w, branches: ["main"], check: "sh check.sh"}]}' >"$LOCAL_CI_CONFIG"
}

# commit <content of check.sh>: a new commit on origin's main; prints its sha
commit() {
	printf '%s\n' "$1" >"$seed/check.sh"
	git -C "$seed" commit -q -am "check: $1"
	git -C "$seed" push -q origin main
	git -C "$seed" rev-parse HEAD
}

statuses() {
	jq -r 'select(.[0] == "api") | [.[3], (.[] | select(startswith("state=")))] | join(" ")' "$FAKE_GH_LOG"
}

@test "run: a passing check posts pending, then success, on the commit" {
	sha=$(git -C "$seed" rev-parse HEAD)
	run "$LOCAL_CI" run app main
	[ "$status" -eq 0 ]
	[ "$(statuses)" = "repos/o/app/statuses/$sha state=pending
repos/o/app/statuses/$sha state=success" ]
	grep -q "context=local-ci" "$FAKE_GH_LOG"
	[ "$(cut -f2,3 "$state/app/results.tsv")" = "$sha	success" ]
	[ "$(git -C "$work" rev-parse HEAD)" = "$sha" ]
}

@test "run: a failing check posts failure, keeps the log and exits non-zero" {
	sha=$(commit 'echo broken; exit 3')
	run "$LOCAL_CI" run app "$sha"
	[ "$status" -eq 1 ]
	statuses | tail -n 1 | grep -qx "repos/o/app/statuses/$sha state=failure"
	grep -q "exit 3" "$FAKE_GH_LOG"
	grep -qx broken "$state/app/$sha.log"
}

@test "run: the status names no local path" {
	sha=$(commit 'exit 1')
	run "$LOCAL_CI" run app "$sha"
	run ! grep -q "$BATS_TEST_TMPDIR" "$FAKE_GH_LOG"
	grep -q "log app/$sha.log" "$FAKE_GH_LOG"
}

@test "run: a check past its timeout is an error, not a failure" {
	command -v timeout >/dev/null || skip "no timeout(1)"
	jq '.repos[0].timeout = 1' "$LOCAL_CI_CONFIG" >"$BATS_TEST_TMPDIR/c" && mv "$BATS_TEST_TMPDIR/c" "$LOCAL_CI_CONFIG"
	sha=$(commit 'sleep 5')
	run "$LOCAL_CI" run app "$sha"
	[ "$status" -eq 1 ]
	statuses | tail -n 1 | grep -qx "repos/o/app/statuses/$sha state=error"
}

@test "run: refuses a workdir with modified tracked files, and posts nothing" {
	echo changed >>"$work/check.sh"
	run "$LOCAL_CI" run app main
	[ "$status" -eq 2 ]
	[[ "$output" == *"modified tracked files"* ]]
	[ ! -s "$FAKE_GH_LOG" ]
}

@test "run: ignored build output survives between runs" {
	mkdir -p "$work/build" && echo cached >"$work/build/cache"
	commit 'test -f build/cache' >/dev/null
	run "$LOCAL_CI" run app main
	[ "$status" -eq 0 ]
}

@test "run: a second check while one holds the lock exits 75 and posts nothing" {
	mkdir -p "$state/lock" && echo $$ >"$state/lock/pid"
	run "$LOCAL_CI" run app main
	[ "$status" -eq 75 ]
	[ ! -s "$FAKE_GH_LOG" ]
}

@test "run: a lock left by a dead process is taken over" {
	mkdir -p "$state/lock" && echo 999999 >"$state/lock/pid"
	run "$LOCAL_CI" run app main
	[ "$status" -eq 0 ]
	[[ "$output" == *"stale lock"* ]]
	[ ! -d "$state/lock" ]
}

@test "run: LOCAL_CI_NO_STATUS records the verdict and posts nothing" {
	LOCAL_CI_NO_STATUS=1 run "$LOCAL_CI" run app main
	[ "$status" -eq 0 ]
	[ ! -s "$FAKE_GH_LOG" ]
	[ -s "$state/app/results.tsv" ]
}

@test "run: a status gh cannot post is said, and the verdict still stands" {
	FAKE_GH_EXIT=1 run "$LOCAL_CI" run app main
	[ "$status" -eq 0 ]
	[[ "$output" == *"could not post"* ]]
	[ "$(cut -f3 "$state/app/results.tsv")" = success ]
}

@test "poll: checks a new head once, and a known head never again" {
	run "$LOCAL_CI" poll
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$state/app/results.tsv")" -eq 1 ]
	run "$LOCAL_CI" poll
	[ "$(wc -l <"$state/app/results.tsv")" -eq 1 ]
	commit 'true' >/dev/null
	run "$LOCAL_CI" poll
	[ "$(wc -l <"$state/app/results.tsv")" -eq 2 ]
}

@test "poll: a red check does not fail poll" {
	commit 'exit 1' >/dev/null
	run "$LOCAL_CI" poll
	[ "$status" -eq 0 ]
	[ "$(cut -f3 "$state/app/results.tsv")" = failure ]
}

@test "poll: exits 0 and does nothing while another check runs" {
	mkdir -p "$state/lock" && echo $$ >"$state/lock/pid"
	run "$LOCAL_CI" poll
	[ "$status" -eq 0 ]
	[ ! -f "$state/app/results.tsv" ]
}

@test "poll --prs: checks same-repository pull requests and never a fork's" {
	git -C "$seed" switch -q -c feature
	printf 'exit 0\n' >"$seed/f.sh" && git -C "$seed" add f.sh && git -C "$seed" commit -q -m f
	git -C "$seed" push -q origin feature
	mine=$(git -C "$seed" rev-parse HEAD)
	jq -n --arg m "$mine" '[{headRefName: "feature", headRefOid: $m, isCrossRepository: false},
		{headRefName: "evil", headRefOid: "0123456789012345678901234567890123456789", isCrossRepository: true}]' \
		>"$FAKE_GH_DIR/prs.json"
	run "$LOCAL_CI" poll --prs
	[ "$status" -eq 0 ]
	grep -q "$mine" "$state/app/results.tsv"
	run ! grep -q 0123456789 "$state/app/results.tsv"
}

@test "status and repos: read the records and the configuration" {
	run "$LOCAL_CI" status
	[[ "$output" == "app  no verdicts yet" ]]
	"$LOCAL_CI" run app main 2>/dev/null
	run "$LOCAL_CI" status app
	[[ "$output" == *"success"* ]]
	run "$LOCAL_CI" repos
	[ "$output" = "app	o/app	main	sh check.sh" ]
}

@test "a configuration without repos is refused with a pointer to the docs" {
	echo '{}' >"$LOCAL_CI_CONFIG"
	run "$LOCAL_CI" status
	[ "$status" -eq 2 ]
	[[ "$output" == *"needs repos[]"* ]]
}
