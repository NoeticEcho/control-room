# The checks a worker runs before READY, and CI runs on every pull request.
# Needs: shellcheck, bats, jq, git, python3 with jsonschema.

.POSIX:
.PHONY: check lint test

check: lint test

lint:
	shellcheck scripts/guard
	shellcheck --shell=bash tests/*.bats

test:
	bats tests
	GUARD_SH=bash bats tests/guard.bats
