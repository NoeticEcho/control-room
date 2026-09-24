#!/usr/bin/env bats
# Tests for scripts/guard. Each test builds a throwaway repository on a
# worker branch and feeds the guard a PreToolUse-shaped event.
# The commands under test are data, so they sit in single quotes (SC2016);
# bats sets $stderr and $stderr_lines (SC2154).
# shellcheck disable=SC2016,SC2154

bats_require_minimum_version 1.5.0

GUARD="$BATS_TEST_DIRNAME/../scripts/guard"

setup() {
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
	export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
	repo="$BATS_TEST_TMPDIR/repo"
	git init -q -b main "$repo"
	git -C "$repo" commit -q --allow-empty -m init
	git -C "$repo" switch -q -c claude/cr-1-x
}

# event <command> [cwd]: a Bash PreToolUse event
event() {
	jq -cn --arg c "$1" --arg d "${2:-$repo}" \
		'{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d,
		  tool_input: {command: $c}}'
}

# mcp_event <tool> <tool_input json>
mcp_event() {
	jq -cn --arg t "$1" --argjson i "$2" --arg d "$repo" \
		'{hook_event_name: "PreToolUse", tool_name: $t, cwd: $d, tool_input: $i}'
}

feed() {
	printf '%s' "$1" >"$BATS_TEST_TMPDIR/event"
	# shellcheck disable=SC2086 # GUARD_SH may carry options: "bash --posix"
	run ${GUARD_SH:-sh} "$GUARD" <"$BATS_TEST_TMPDIR/event"
}

allows() {
	feed "$(event "$@")"
	if [ "$status" -ne 0 ] || [ -n "$output" ]; then
		echo "expected allow for: $1"
		echo "status $status: $output"
		return 1
	fi
}

# denies <command> <text the reason must contain> [cwd]
denies() {
	feed "$(event "$1" "${3:-$repo}")"
	check_denied "$1" "$2"
}

check_denied() {
	if [ "$status" -ne 2 ] || [[ "$output" != *"guard: denied: "*"$2"*"Instead: "* ]]; then
		echo "expected a denial containing '$2' for: $1"
		echo "status $status: $output"
		return 1
	fi
}

# ---- a push to anything but the current branch -----------------------------

@test "push: to another worker branch is denied" {
	denies 'git push origin claude/cr-2-other' 'not the current branch claude/cr-1-x'
}

@test "push: HEAD:main is denied" {
	denies 'git push origin HEAD:main' 'integration branch main'
}

@test "push: HEAD:refs/heads/main is denied" {
	denies 'git push origin HEAD:refs/heads/main' 'integration branch main'
}

@test "push: the integration branch by name is denied" {
	denies 'git push origin main' 'integration branch main'
}

@test "push: the integration branch is denied even when it is the current branch" {
	git -C "$repo" switch -q main
	denies 'git push origin main' 'integration branch main'
}

@test "push: a current branch outside the worker prefix is denied" {
	git -C "$repo" switch -q -c feature
	denies 'git push origin feature' 'not a worker branch (claude/...)'
}

@test "push: another ref namespace is denied" {
	denies 'git push origin HEAD:refs/notes/x' 'a push to refs/notes/x'
}

@test "push: every branch at once is denied" {
	denies 'git push --all origin' 'every branch'
	denies 'git push --mirror origin' 'every branch'
}

@test "push: from a detached HEAD is denied" {
	git -C "$repo" switch -q --detach
	denies 'git push origin claude/cr-1-x' 'not on a branch'
}

@test "push: git -C <dir> checks the branch of <dir>" {
	other="$BATS_TEST_TMPDIR/other"
	git init -q -b main "$other"
	git -C "$other" commit -q --allow-empty -m init
	denies "git -C $other push origin claude/cr-1-x" 'not the current branch main'
	denies "git -C $other push origin main" 'integration branch main'
}

@test "push: git -C <dir> from elsewhere allows <dir>'s own branch" {
	allows "git -C $repo push origin claude/cr-1-x" "$BATS_TEST_TMPDIR"
	allows "git -C repo push origin claude/cr-1-x" "$BATS_TEST_TMPDIR"
}

@test "push: cd <dir> earlier in the command is followed" {
	other="$BATS_TEST_TMPDIR/other"
	git init -q -b main "$other"
	git -C "$other" commit -q --allow-empty -m init
	denies "cd $other && git push origin claude/cr-1-x" 'not the current branch main'
}

# ---- a push with no explicit refspec -------------------------------------

@test "no refspec: bare git push is denied" {
	denies 'git push' 'no explicit refspec'
}

@test "no refspec: git push origin is denied" {
	denies 'git push origin' 'no explicit refspec'
}

@test "no refspec: git push -u origin is denied, and the reason names the branch" {
	denies 'git push -u origin' 'git push origin claude/cr-1-x'
}

# ---- force pushes ----------------------------------------------------------

@test "force: --force is denied" {
	denies 'git push --force origin claude/cr-1-x' 'force push'
}

@test "force: -f and bundled short flags are denied" {
	denies 'git push -f origin claude/cr-1-x' 'force push'
	denies 'git push -uf origin claude/cr-1-x' 'force push'
}

@test "force: --force-with-lease is denied" {
	denies 'git push --force-with-lease origin claude/cr-1-x' 'force push'
	denies 'git push --force-with-lease=claude/cr-1-x origin claude/cr-1-x' 'force push'
}

@test "force: --force-if-includes is denied" {
	denies 'git push --force-if-includes origin claude/cr-1-x' 'force push'
}

@test "force: a + refspec is denied" {
	denies 'git push origin +claude/cr-1-x' 'force push'
	denies 'git push origin +HEAD:claude/cr-1-x' 'force push'
}

@test "force: an option after the refspec still counts" {
	denies 'git push origin claude/cr-1-x --force' 'force push'
}

# ---- tags ------------------------------------------------------------------

@test "tags: git push --tags is denied" {
	denies 'git push --tags' 'writing a tag'
	denies 'git push origin --tags' 'writing a tag'
}

@test "tags: git push --follow-tags is denied" {
	denies 'git push --follow-tags origin claude/cr-1-x' 'writing a tag'
}

@test "tags: pushing a tag ref is denied" {
	denies 'git push origin refs/tags/v1' 'writing a tag'
	denies 'git push origin HEAD:refs/tags/v1' 'writing a tag'
}

@test "tags: creating or deleting a tag is denied" {
	denies 'git tag v1' 'writing a tag'
	denies 'git tag -a v1 -m release' 'writing a tag'
	denies 'git tag -d v1' 'writing a tag'
	denies 'git tag -am release v1' 'writing a tag'
}

@test "tags: gh release create is denied" {
	denies 'gh release create v1 --notes x' 'writing a tag'
}

# ---- branch deletions ------------------------------------------------------

@test "delete: git push origin :branch is denied" {
	denies 'git push origin :claude/cr-1-x' 'deleting a branch'
}

@test "delete: git push --delete and -d are denied" {
	denies 'git push --delete origin claude/cr-1-x' 'deleting a branch'
	denies 'git push -d origin claude/cr-1-x' 'deleting a branch'
}

@test "delete: git push --prune is denied" {
	denies 'git push --prune origin claude/cr-1-x' 'deleting a branch'
}

@test "delete: git branch -d, -D and --delete are denied" {
	denies 'git branch -d old' 'deleting a branch'
	denies 'git branch -D old' 'deleting a branch'
	denies 'git branch --delete old' 'deleting a branch'
	denies 'git branch -rd origin/old' 'deleting a branch'
}

# ---- merging a pull request ------------------------------------------------

@test "merge: gh pr merge is denied" {
	denies 'gh pr merge 12 --squash' 'merging a pull request'
}

@test "merge: the merge endpoint through gh api is denied" {
	denies 'gh api -X PUT repos/o/r/pulls/12/merge' 'merging a pull request'
}

@test "merge: the MCP merge_pull_request tool is denied" {
	feed "$(mcp_event mcp__github__merge_pull_request '{"owner":"o","repo":"r","pullNumber":1}')"
	check_denied merge_pull_request 'merging a pull request'
}

@test "merge: the MCP enable_pr_auto_merge tool is denied" {
	feed "$(mcp_event mcp__github__enable_pr_auto_merge '{"owner":"o","repo":"r","pullNumber":1}')"
	check_denied enable_pr_auto_merge 'merging a pull request'
}

# ---- pull requests against the integration branch only ---------------------

@test "pr: MCP create_pull_request against another base is denied" {
	feed "$(mcp_event mcp__github__create_pull_request '{"base":"release","head":"claude/cr-1-x","title":"t"}')"
	check_denied create_pull_request 'a pull request against release'
}

@test "pr: MCP create_pull_request with no base is denied" {
	feed "$(mcp_event mcp__github__create_pull_request '{"head":"claude/cr-1-x","title":"t"}')"
	check_denied create_pull_request 'open the pull request against main'
}

@test "pr: MCP create_pull_request against the integration branch is allowed" {
	feed "$(mcp_event mcp__github__create_pull_request '{"base":"main","head":"claude/cr-1-x","title":"t"}')"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "pr: MCP update_pull_request moving the base is denied" {
	feed "$(mcp_event mcp__github__update_pull_request '{"pullNumber":1,"base":"release"}')"
	check_denied update_pull_request 'a pull request against release'
	feed "$(mcp_event mcp__github__update_pull_request '{"pullNumber":1,"title":"t"}')"
	[ "$status" -eq 0 ]
}

@test "pr: gh pr create against another base is denied" {
	denies 'gh pr create --base release --fill' 'a pull request against release'
	denies 'gh pr create -B release --fill' 'a pull request against release'
	allows 'gh pr create --base main --fill'
}

# ---- MCP writes to a branch ------------------------------------------------

@test "mcp: push_files to another branch is denied, to the current one allowed" {
	feed "$(mcp_event mcp__github__push_files '{"branch":"main","files":[]}')"
	check_denied push_files 'integration branch main'
	feed "$(mcp_event mcp__github__push_files '{"branch":"claude/cr-1-x","files":[]}')"
	[ "$status" -eq 0 ]
}

@test "mcp: create_or_update_file and delete_branch are checked" {
	feed "$(mcp_event mcp__github__create_or_update_file '{"branch":"claude/cr-2-y","path":"a"}')"
	check_denied create_or_update_file 'not the current branch'
	feed "$(mcp_event mcp__github__delete_branch '{"branch":"claude/cr-1-x"}')"
	check_denied delete_branch 'deleting a branch'
}

# ---- chained and wrapped commands ------------------------------------------

@test "chain: a denied push after && is found" {
	denies 'git add -A && git commit -m wip && git push origin HEAD:main' 'integration branch main'
}

@test "chain: a denied push after ; and || is found" {
	denies 'git fetch origin; git push' 'no explicit refspec'
	denies 'false || git push origin main' 'integration branch main'
}

@test "chain: a denied push inside a pipeline, a subshell or a substitution is found" {
	denies 'git push origin main 2>&1 | tail -3' 'integration branch main'
	denies '(git push origin main)' 'integration branch main'
	denies 'echo $(git push origin main)' 'integration branch main'
	denies 'echo `git push origin main`' 'integration branch main'
}

@test "chain: git switch -c <b> earlier in the command makes <b> current" {
	allows 'git switch -c claude/cr-1-y && git push -u origin claude/cr-1-y'
	allows 'git checkout -b claude/cr-1-y origin/main; git push origin claude/cr-1-y'
	denies 'git switch -c claude/cr-1-y && git push origin claude/cr-1-x' 'not the current branch claude/cr-1-y'
}

@test "chain: git switch <existing> earlier in the command is followed" {
	denies 'git switch main && git push origin claude/cr-1-x' 'not the current branch main'
}

@test "chain: git checkout -- <path> does not change the branch" {
	allows 'git checkout -- README.md && git push origin claude/cr-1-x'
}

@test "wrapped: sh -c, bash -lc and eval are looked into" {
	denies "bash -c 'git push origin main'" 'integration branch main'
	denies 'sh -c "git push --force origin claude/cr-1-x"' 'force push'
	denies "bash -lc 'cd /tmp && git push'" 'no explicit refspec'
	denies 'eval git push origin main' 'integration branch main'
}

@test "wrapped: assignments, env, timeout and a path to git are skipped" {
	denies 'GIT_TRACE=1 git push origin main' 'integration branch main'
	denies 'env -u X GIT_TRACE=1 git push origin main' 'integration branch main'
	denies 'timeout 60 git push origin main' 'integration branch main'
	denies '/usr/bin/git push origin main' 'integration branch main'
	denies 'if true; then git push origin main; fi' 'integration branch main'
}

@test "wrapped: git global options before push are skipped" {
	denies 'git -c push.default=current --no-pager push origin main' 'integration branch main'
}

# ---- configuration ---------------------------------------------------------

@test "config: control-room.json sets the integration branch and the prefix" {
	printf '{"integration_branch": "develop", "branch_prefix": "agent/"}\n' >"$repo/control-room.json"
	git -C "$repo" switch -q -c agent/cr-1-x
	allows 'git push origin agent/cr-1-x'
	denies 'git push origin main' 'not the current branch agent/cr-1-x'
	git -C "$repo" switch -q -c develop
	denies 'git push origin develop' 'integration branch develop'
	git -C "$repo" switch -q claude/cr-1-x
	denies 'git push origin claude/cr-1-x' 'not a worker branch (agent/...)'
	feed "$(mcp_event mcp__github__create_pull_request '{"base":"main","head":"x","title":"t"}')"
	check_denied create_pull_request 'open the pull request against develop'
}

@test "config: an invalid control-room.json denies pushes rather than guessing" {
	printf '{"integration_branch": 1}\n' >"$repo/control-room.json"
	denies 'git push origin claude/cr-1-x' 'control-room.json is not valid'
	allows 'git status'
}

@test "config: the defaults are main and claude/ when there is no file" {
	allows 'git push origin claude/cr-1-x'
	denies 'git push origin main' 'integration branch main'
}

# ---- output and input ------------------------------------------------------

@test "output: a denial is one line on stderr and a PreToolUse deny on stdout" {
	event 'git push origin main' >"$BATS_TEST_TMPDIR/event"
	# shellcheck disable=SC2086 # as in feed
	run --separate-stderr ${GUARD_SH:-sh} "$GUARD" <"$BATS_TEST_TMPDIR/event"
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[[ "$stderr" == "guard: denied: "*". Instead: "* ]]
	[ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.permissionDecision)" = deny ]
	[ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "$stderr" ]
}

@test "input: an event that is not JSON is denied" {
	feed 'git push origin main'
	check_denied 'not json' 'not a JSON object'
}

@test "input: without jq, git commands are denied and others allowed" {
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir "$bin"
	for t in cat git sed; do ln -s "$(command -v "$t")" "$bin/$t"; done
	event 'git status' >"$BATS_TEST_TMPDIR/event"
	run env PATH="$bin" /bin/sh "$GUARD" <"$BATS_TEST_TMPDIR/event"
	check_denied 'no jq' 'jq is not installed'
	event 'ls -la' >"$BATS_TEST_TMPDIR/event"
	run env PATH="$bin" /bin/sh "$GUARD" <"$BATS_TEST_TMPDIR/event"
	[ "$status" -eq 0 ]
}

# ---- everything else passes through ----------------------------------------

@test "pass: the worker's own push forms are allowed" {
	allows 'git push origin claude/cr-1-x'
	allows 'git push -u origin claude/cr-1-x'
	allows 'git push origin HEAD'
	allows 'git push origin HEAD:claude/cr-1-x'
	allows 'git push origin HEAD:refs/heads/claude/cr-1-x'
	allows 'git push --set-upstream origin refs/heads/claude/cr-1-x'
	allows 'git push -o ci.skip origin claude/cr-1-x'
	allows 'git push --no-verify origin claude/cr-1-x'
}

@test "pass: ordinary git commands are allowed" {
	allows 'git status'
	allows 'git log --oneline -5'
	allows 'git fetch origin main'
	allows 'git pull --no-rebase origin main'
	allows 'git merge --no-ff origin/main'
	allows 'git add -A && git commit -m "push to main later"'
	allows 'git switch -c claude/cr-1-y origin/main'
	allows 'git branch -a'
	allows 'git branch -m claude/cr-1-z'
	allows 'git tag'
	allows 'git tag -l "v*"'
	allows 'git tag --contains HEAD'
	allows 'git diff origin/main...HEAD'
}

@test "pass: text that only mentions a forbidden command is allowed" {
	allows 'echo "git push origin main"'
	allows "grep -rn 'git push --force' docs"
	allows 'git commit -m "never gh pr merge"'
	allows 'ls # git push origin main'
}

@test "pass: other commands and tools are allowed" {
	allows 'make check'
	allows 'ls -la && cat README.md | head'
	allows 'gh pr view 12'
	allows 'gh pr create --fill'
	feed '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
	[ "$status" -eq 0 ]
	feed "$(mcp_event mcp__github__get_file_contents '{"owner":"o","repo":"r","path":"a"}')"
	[ "$status" -eq 0 ]
}

# ---- the git pre-push fallback ---------------------------------------------

pre_push_setup() {
	remote="$BATS_TEST_TMPDIR/remote.git"
	git init -q --bare "$remote"
	git -C "$repo" remote add origin "$remote"
	git -C "$repo" push -q origin main claude/cr-1-x
	hooks="$BATS_TEST_TMPDIR/hooks"
	mkdir "$hooks"
	printf '#!/bin/sh\nexec sh "%s" --git-pre-push "$@"\n' "$GUARD" >"$hooks/pre-push"
	chmod +x "$hooks/pre-push"
	git -C "$repo" config core.hooksPath "$hooks"
	git -C "$repo" commit -q --allow-empty -m work
}

@test "pre-push: the current worker branch is allowed" {
	pre_push_setup
	run git -C "$repo" push origin claude/cr-1-x
	[ "$status" -eq 0 ]
}

@test "pre-push: the integration branch, a deletion and a tag are refused" {
	pre_push_setup
	run git -C "$repo" push origin HEAD:main
	[ "$status" -ne 0 ]
	[[ "$output" == *"integration branch main"* ]]
	run git -C "$repo" push origin :claude/cr-1-x
	[ "$status" -ne 0 ]
	[[ "$output" == *"deleting a branch"* ]]
	git -C "$repo" tag v1
	run git -C "$repo" push origin v1
	[ "$status" -ne 0 ]
	[[ "$output" == *"writing a tag"* ]]
}

@test "pre-push: a push that rewrites the remote branch is refused" {
	pre_push_setup
	git -C "$repo" push -q origin claude/cr-1-x
	git -C "$repo" reset -q --hard HEAD~1
	git -C "$repo" commit -q --allow-empty -m other
	run git -C "$repo" push --force origin claude/cr-1-x
	[ "$status" -ne 0 ]
	[[ "$output" == *"force push"* ]]
}
