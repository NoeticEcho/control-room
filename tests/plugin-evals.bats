#!/usr/bin/env bats
# Tests for tests/plugin-evals/run, with a fake `claude` that records what it
# was given, and for the shape of the eval cases themselves.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
RUN="$ROOT/tests/plugin-evals/run"
CASES="$ROOT/tests/plugin-evals/cases"

setup() {
	bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin"
	# The fake agent: records its arguments and the plugin it was pointed at.
	cat >"$bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$FAKE_LOG/args"
plugin=$3
( cd "$plugin" && find . -type f | sort ) >"$FAKE_LOG/tree"
echo "$plugin" >"$FAKE_LOG/where"
exit "${FAKE_STATUS:-0}"
EOF
	chmod +x "$bin/claude"
	export FAKE_LOG="$BATS_TEST_TMPDIR/log" CR_EVAL_OUT="$BATS_TEST_TMPDIR/out"
	mkdir -p "$FAKE_LOG"
	export PATH="$bin:$PATH"
}

@test "runs claude plugin eval on a scratch copy of the plugin with the cases as its evals/" {
	run "$RUN" --runs 1 --case 'brief-*'
	[ "$status" -eq 0 ]
	[ "$(sed -n 1,2p "$FAKE_LOG/args" | tr '\n' ' ')" = "plugin eval " ]
	[ "$(sed -n 4,8p "$FAKE_LOG/args" | tr '\n' ' ')" = "--trust-plugin --no-publish --output-dir $CR_EVAL_OUT --runs " ]
	[ "$(sed -n 9,11p "$FAKE_LOG/args" | tr '\n' ' ')" = "1 --case brief-* " ]
	grep -qx './.claude-plugin/plugin.json' "$FAKE_LOG/tree"
	grep -qx './skills/land-ready/SKILL.md' "$FAKE_LOG/tree"
	grep -qx './evals/brief-an-epic/prompt.md' "$FAKE_LOG/tree"
	grep -qx './evals/unrelated-git-question/graders/no-skill.md' "$FAKE_LOG/tree"
	[ "${lines[-1]}" = "run: results in $CR_EVAL_OUT" ]
	[ -d "$CR_EVAL_OUT" ]
}

@test "the scratch copy is removed, and the repository's plugin gets no evals/" {
	run "$RUN"
	[ "$status" -eq 0 ]
	[ ! -e "$(cat "$FAKE_LOG/where")" ]
	[ ! -e "$ROOT/plugin/evals" ]
}

@test "the eval's own exit status is passed on" {
	FAKE_STATUS=1 run "$RUN"
	[ "$status" -eq 1 ]
	[ ! -e "$(cat "$FAKE_LOG/where")" ]
}

@test "no claude: exit 69 and say so" {
	CR_AGENT=no-such-agent run "$RUN"
	[ "$status" -eq 69 ]
	[ "$output" = "run: no-such-agent is not installed" ]
}

@test "each case: a prompt.md with known frontmatter, and graders with a type" {
	n=0
	for dir in "$CASES"/*/; do
		name=$(basename "$dir")
		[ -f "$dir/prompt.md" ] || { echo "$name: no prompt.md"; return 1; }
		[ "$(sed -n 1p "$dir/prompt.md")" = --- ]
		while IFS= read -r line; do
			key=${line%%:*}
			[[ " description max_turns allowed_tools timeout_seconds runs tags " == *" $key "* ]] ||
				{ echo "$name: unknown key $key"; return 1; }
		done < <(sed -n '2,/^---$/p' "$dir/prompt.md" | sed '$d')
		for grader in "$dir"/graders/*.md; do
			grep -qE '^type: (regex|tool_used|tool_order|file_exists|llm|baseline)$' "$grader" ||
				{ echo "$grader: no type"; return 1; }
		done
		n=$((n + 1))
	done
	[ "$n" -ge 5 ]
	# Every skill has a case that expects it to fire.
	for skill in "$ROOT"/plugin/skills/*/; do
		grep -rqF "$(basename "$skill")\"" "$CASES"/*/graders/skill-fired.md ||
			{ echo "no case fires $(basename "$skill")"; return 1; }
	done
}
