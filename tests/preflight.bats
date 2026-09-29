#!/usr/bin/env bats
# Tests for scripts/preflight: a PATH made of stubs for every tool it checks,
# with one or more taken away, and python3's modules replaced by stubs that
# import, or fail to.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
PREFLIGHT="$ROOT/scripts/preflight"
TOOLS="shellcheck bats bash jq git flock timeout python3 node"

setup() {
	local tool
	bin="$BATS_TEST_TMPDIR/bin"
	mods="$BATS_TEST_TMPDIR/mods"
	rm -rf "$bin" "$mods"
	mkdir -p "$bin" "$mods/jsonschema" "$mods/e2b"
	# What the preflight itself runs.
	ln -s "$(command -v sed)" "$bin/sed"
	for tool in $TOOLS; do
		stub "$tool" 'exit 0'
	done
	stub bats 'echo "Bats 1.10.0"'
	stub node 'echo "v22.1.0"'
	ln -sf "$(command -v python3)" "$bin/python3"
	# Modules that import, so the real machine's modules do not matter.
	: >"$mods/jsonschema/__init__.py"
	: >"$mods/e2b/__init__.py"
	export PYTHONPATH="$mods" PYTHONDONTWRITEBYTECODE=1
	unset CR_REQUIRE_E2B_SDK
}

# stub <tool> <shell text>: a fake tool on the test PATH
stub() {
	rm -f "$bin/$1"
	printf '#!/bin/sh\n%s\n' "$2" >"$bin/$1"
	chmod +x "$bin/$1"
}

# no_module <name>: python3 fails to import it
no_module() {
	printf 'raise ImportError("no %s here")\n' "$1" >"$mods/$1/__init__.py"
}

preflight() {
	run env PATH="$bin" "$(command -v sh)" "$PREFLIGHT"
}

@test "everything there: exit 0, one line" {
	preflight
	[ "$status" -eq 0 ]
	[ "$output" = "preflight: ok" ]
}

@test "each tool taken away alone is named, with how to install it, and nothing else" {
	local t checked=''
	for t in $TOOLS; do
		setup
		rm "$bin/$t"
		preflight
		[ "$status" -eq 1 ] || { echo "$t: status $status"; return 1; }
		[ "${#lines[@]}" -eq 2 ] || { echo "$t: $output"; return 1; }
		[[ "${lines[0]}" == "preflight: missing $t: "?* ]] || { echo "$t: ${lines[0]}"; return 1; }
		[ "${lines[1]}" = "preflight: 1 missing; make check would fail on it. Install, then run make check again." ]
		checked="$checked $t"
	done
	# setup runs inside the loop: it must not have clobbered the loop's t.
	[ "$checked" = " $TOOLS" ]
}

@test "python3 without jsonschema: the module is named, with pip and the distribution package" {
	no_module jsonschema
	preflight
	[ "$status" -eq 1 ]
	[ "${lines[0]}" = "preflight: missing the Python module jsonschema: pip install jsonschema, or your package manager, e.g. apt-get install python3-jsonschema (scripts/validate-handoff)" ]
}

@test "bats older than 1.5.0 is too old; versions compare as numbers, not text" {
	stub bats 'echo "Bats 1.4.1"'
	preflight
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "preflight: bats 1.4.1 is too old, need 1.5.0 or later: "* ]]
	stub bats 'echo "Bats 1.10.0"'
	preflight
	[ "$status" -eq 0 ]
	stub bats 'echo "Bats 2.0"'
	preflight
	[ "$status" -eq 0 ]
	stub bats 'echo "something else"'
	preflight
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "preflight: bats (unknown) is too old"* ]]
}

@test "node older than 18 is too old" {
	stub node 'echo v16.20.2'
	preflight
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "preflight: node 16.20.2 is too old, need 18 or later: https://nodejs.org"* ]]
	stub node 'echo v18.0.0'
	preflight
	[ "$status" -eq 0 ]
}

@test "the e2b module is checked only when CR_REQUIRE_E2B_SDK is set" {
	no_module e2b
	preflight
	[ "$status" -eq 0 ]
	CR_REQUIRE_E2B_SDK=1 preflight
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "preflight: missing the Python module e2b (CR_REQUIRE_E2B_SDK is set): pip install e2b"* ]]
}

@test "several missing: one line each, then the count" {
	rm "$bin/jq" "$bin/flock"
	no_module jsonschema
	preflight
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 4 ]
	[[ "${lines[0]}" == "preflight: missing jq: "* ]]
	[[ "${lines[1]}" == "preflight: missing flock: "* ]]
	[[ "${lines[2]}" == "preflight: missing the Python module jsonschema: "* ]]
	[[ "${lines[3]}" == "preflight: 3 missing;"* ]]
}

@test "make runs the preflight before the lint and the tests" {
	cd "$ROOT"
	# Under an outer make (make check runs this file), the inner one would
	# print "Entering directory" first.
	unset MAKEFLAGS MFLAGS MAKELEVEL
	run make --no-print-directory -n check
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "sh scripts/preflight" ]
	[ "$(grep -c '^sh scripts/preflight$' <<<"$output")" -eq 1 ]
	run make --no-print-directory -n test
	[ "${lines[0]}" = "sh scripts/preflight" ]
	run make --no-print-directory -n lint
	[ "${lines[0]}" = "sh scripts/preflight" ]
}
