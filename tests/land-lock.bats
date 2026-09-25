#!/usr/bin/env bats
# Tests for scripts/land-lock: real flock, real concurrent processes. A holder
# signals that it holds the lock by creating a file, and lets go when the test
# creates another, so no test depends on timing beyond "within ten seconds".
# Shell text under test sits in single quotes (SC2016); bats sets $stderr
# (SC2154).
# shellcheck disable=SC2016,SC2154

bats_require_minimum_version 1.5.0

LAND_LOCK="$BATS_TEST_DIRNAME/../scripts/land-lock"

setup() {
	T=$BATS_TEST_TMPDIR
	export CR_LAND_LOCK="$T/land.lock"
	unset CR_LAND_WHO
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
	holders=
}

teardown() {
	: >"$T/release"
	for pid in $holders; do
		wait "$pid" 2>/dev/null || true
	done
	if [ -s "$T/bgpid" ]; then
		kill "$(cat "$T/bgpid")" 2>/dev/null || true
	fi
}

# await <file>: wait up to ten seconds for the file to appear
await() {
	i=0
	while [ ! -e "$1" ]; do
		i=$((i + 1))
		[ "$i" -lt 200 ] || { echo "timed out waiting for $1"; return 1; }
		sleep 0.05
	done
}

# hold [land-lock options]: a land-lock in the background whose command
# creates $T/started, then runs until $T/release exists. Sets holder (its
# pid) and waits until it holds the lock.
hold() {
	rm -f "$T/started" "$T/release"
	"$LAND_LOCK" "$@" -- sh -c ': >"$1"; while [ ! -e "$2" ]; do sleep 0.05; done' \
		sh "$T/started" "$T/release" 2>"$T/holder.err" &
	holder=$!
	holders="$holders $holder"
	await "$T/started"
}

# release: let the holder's command end, and wait for land-lock to exit
release() {
	: >"$T/release"
	holder_status=0
	wait "$holder" || holder_status=$?
}

@test "runs the command with its arguments intact, and exits with its status" {
	run "$LAND_LOCK" -- sh -c 'printf "[%s]" "$@"' sh 'a b' '' '*' '--lock' '$HOME'
	[ "$status" -eq 0 ]
	[ "$output" = '[a b][][*][--lock][$HOME]' ]
	run "$LAND_LOCK" -- sh -c 'exit 3'
	[ "$status" -eq 3 ]
}

@test "two concurrent holders: the second exits 75, says who holds it, and runs nothing" {
	hold --who loop
	run --separate-stderr "$LAND_LOCK" --who person -- sh -c ': >"$1"' sh "$T/second-ran"
	[ "$status" -eq 75 ]
	[[ "$stderr" == "land-lock: held by loop, pid $holder, since "*": sh -c "*"(lock: $T/land.lock); try again later" ]]
	[ ! -e "$T/second-ran" ]
	release
	[ "$holder_status" -eq 0 ]
	run "$LAND_LOCK" --who person -- sh -c ': >"$1"' sh "$T/second-ran"
	[ "$status" -eq 0 ]
	[ -e "$T/second-ran" ]
}

@test "the lock is released when the command fails, and the holder line is cleared" {
	run "$LAND_LOCK" -- sh -c 'exit 7'
	[ "$status" -eq 7 ]
	[ ! -s "$T/land.lock" ]
	run "$LAND_LOCK" -- true
	[ "$status" -eq 0 ]
}

@test "--wait: takes the lock when the holder lets go in time" {
	hold
	"$LAND_LOCK" --wait 10 -- sh -c ': >"$1"' sh "$T/waiter-ran" &
	waiter=$!
	sleep 0.3
	[ ! -e "$T/waiter-ran" ]
	release
	wait "$waiter"
	[ -e "$T/waiter-ran" ]
}

@test "--wait: gives up with 75 when the holder does not let go" {
	hold
	run --separate-stderr "$LAND_LOCK" --wait 1 -- true
	[ "$status" -eq 75 ]
	[[ "$stderr" == "land-lock: held by "* ]]
}

@test "a process the command leaves in the background does not keep the lock" {
	run "$LAND_LOCK" -- sh -c 'sleep 60 >/dev/null 2>&1 & echo $! >"$1"' sh "$T/bgpid"
	[ "$status" -eq 0 ]
	kill -0 "$(cat "$T/bgpid")"
	run "$LAND_LOCK" -- true
	[ "$status" -eq 0 ]
}

@test "TERM to land-lock alone waits for the command, and keeps the lock until then" {
	hold
	kill -TERM "$holder"
	sleep 0.3
	run "$LAND_LOCK" -- true
	[ "$status" -eq 75 ]
	release
	[ "$holder_status" -eq 0 ]
	grep -q 'land-lock: TERM received; released after the command ended (status 0)' "$T/holder.err"
	run "$LAND_LOCK" -- true
	[ "$status" -eq 0 ]
}

@test "the default lock is one file in the git common directory, from every worktree" {
	unset CR_LAND_LOCK
	git init -q -b main "$T/repo"
	git -C "$T/repo" commit -q --allow-empty -m one
	git -C "$T/repo" worktree add -q "$T/wt" -b other
	common=$(cd "$T/repo/.git" && pwd -P)
	cd "$T/repo"
	run "$LAND_LOCK" --path
	[ "$status" -eq 0 ]
	[ "$output" = "$common/cr-land.lock" ]
	cd "$T/wt"
	run "$LAND_LOCK" --path
	[ "$output" = "$common/cr-land.lock" ]
	cd "$T/repo"
	hold
	cd "$T/wt"
	run "$LAND_LOCK" -- true
	[ "$status" -eq 75 ]
}

@test "--lock beats CR_LAND_LOCK; outside a repository one of them is required" {
	run "$LAND_LOCK" --path --lock "$T/other.lock"
	[ "$output" = "$T/other.lock" ]
	run "$LAND_LOCK" --path
	[ "$output" = "$T/land.lock" ]
	unset CR_LAND_LOCK
	cd "$T"
	run "$LAND_LOCK" -- true
	[ "$status" -eq 2 ]
	[[ "$output" == *"give --lock or CR_LAND_LOCK"* ]]
}

@test "without flock it exits 69 and says where flock comes from, running nothing" {
	bin="$T/bin"
	mkdir "$bin"
	for c in cat date id uname sed; do
		ln -s "$(command -v "$c")" "$bin/$c"
	done
	run env PATH="$bin" "$(command -v sh)" "$LAND_LOCK" -- "$(command -v touch)" "$T/ran"
	[ "$status" -eq 69 ]
	[[ "$output" == *"flock is not installed"*"util-linux"* ]]
	[ ! -e "$T/ran" ]
}

@test "a lock file that cannot be opened is an error, not a held lock" {
	run "$LAND_LOCK" --lock "$T/no/such/dir/lock" -- true
	[ "$status" -eq 1 ]
	[[ "$output" == *"cannot open the lock file"* ]]
}

@test "usage errors exit 2" {
	run "$LAND_LOCK"
	[ "$status" -eq 2 ]
	[[ "$output" == *"land-lock [--lock <file>]"* ]]
	run "$LAND_LOCK" --
	[ "$status" -eq 2 ]
	run "$LAND_LOCK" --bogus -- true
	[ "$status" -eq 2 ]
	run "$LAND_LOCK" --wait soon -- true
	[ "$status" -eq 2 ]
	[[ "$output" == *"whole seconds"* ]]
	run "$LAND_LOCK" --lock
	[ "$status" -eq 2 ]
	run "$LAND_LOCK" --path -- true
	[ "$status" -eq 2 ]
}

@test "shellcheck is clean" {
	if ! command -v shellcheck >/dev/null; then
		skip "shellcheck is not installed; make check needs it anyway"
	fi
	run shellcheck "$LAND_LOCK"
	echo "$output"
	[ "$status" -eq 0 ]
}
