# The checks a worker runs before READY, and CI runs on every pull request.
# Needs: shellcheck, bats, jq, git, python3 with jsonschema. The e2b runner's
# tests use a fake SDK; its contract test also needs the real one
# (pip install e2b) and is skipped without it, except in CI.

.POSIX:
.PHONY: check lint test

check: lint test

lint:
	shellcheck scripts/guard runners/local/cr-worker tests/fixtures/fake-agent
	shellcheck --shell=bash tests/*.bats
	python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' \
		scripts/validate-handoff runners/e2b/cr-e2b tests/fixtures/e2b-contract.py tests/fixtures/fake-e2b/e2b/__init__.py

test:
	bats tests
	GUARD_SH=bash bats tests/guard.bats
