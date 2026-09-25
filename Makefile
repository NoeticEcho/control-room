# The checks a worker runs before READY, and CI runs on every pull request.
# Needs: shellcheck, bats, jq, git, python3 with jsonschema, and node for the
# desk page's test (no packages). The e2b runner's tests use a fake SDK; its
# contract test also needs the real one (pip install e2b) and is skipped
# without it, except in CI.

.POSIX:
.PHONY: check lint test

check: lint test

lint:
	shellcheck scripts/guard runners/local/cr-worker runners/claude-code-cloud/cr-cloud \
		runners/claude-code-cloud/setup.sh desk/gh-desk examples/end-to-end/replay.sh \
		tests/fixtures/fake-agent tests/fixtures/fake-gh
	shellcheck --shell=bash tests/*.bats
	python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' \
		scripts/validate-handoff runners/e2b/cr-e2b tests/fixtures/e2b-contract.py \
		tests/fixtures/fake-e2b/e2b/__init__.py tests/fixtures/no-e2b/e2b/__init__.py

test:
	bats tests
	node --test tests/desk.test.mjs
	GUARD_SH=bash bats tests/guard.bats
