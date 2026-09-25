#!/usr/bin/env bats
# Tests for examples/end-to-end: replayed, it gives the same files; every
# handoff passes the protocol's validator; every desk file fits the schema;
# and the pieces agree with each other.

bats_require_minimum_version 1.5.0

ROOT="$BATS_TEST_DIRNAME/.."
EX="$ROOT/examples/end-to-end"

# normalized <dir>: a copy of the example's files with the measured seconds
# set to 0, in $BATS_TEST_TMPDIR/norm-<name>
normalized() {
	dest="$BATS_TEST_TMPDIR/norm-$(basename "$1")"
	mkdir -p "$dest"
	(cd "$1" && find . -type f ! -name README.md ! -name replay.sh) | while read -r f; do
		mkdir -p "$dest/$(dirname "$f")"
		case $f in
		*.json) jq '(.. | objects | select(has("seconds")) | .seconds) |= 0' "$1/$f" >"$dest/$f" ;;
		*) cp "$1/$f" "$dest/$f" ;;
		esac
	done
	printf '%s\n' "$dest"
}

@test "replay: replaying the epic gives exactly the files in the example" {
	run "$EX/replay.sh" "$BATS_TEST_TMPDIR/replayed"
	[ "$status" -eq 0 ]
	committed=$(normalized "$EX")
	replayed=$(normalized "$BATS_TEST_TMPDIR/replayed")
	run diff -r "$committed" "$replayed"
	echo "$output"
	[ "$status" -eq 0 ]
}

@test "handoffs: the protocol's validator passes on every handoff in the examples" {
	handoffs=$(find "$ROOT/examples" -path '*/handoff/*.json' | sort)
	[ "$(printf '%s\n' "$handoffs" | wc -l)" -ge 2 ]
	# shellcheck disable=SC2086 # one path per word
	run "$ROOT/scripts/validate-handoff" $handoffs
	echo "$output"
	[ "$status" -eq 0 ]
}

@test "desk: the example desk and the example's desk files fit the schema" {
	run python3 - "$ROOT/desk/desk.schema.json" "$ROOT/desk/desk.example.json" "$EX"/7-desk/desk-*.json <<'PY'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
bad = 0
for path in sys.argv[2:]:
    for e in validator.iter_errors(json.load(open(path))):
        print("%s: %s" % (path, e.message)); bad += 1
sys.exit(1 if bad else 0)
PY
	echo "$output"
	[ "$status" -eq 0 ]
}

@test "desk: the schema refuses a done card without a resolution" {
	run python3 - "$ROOT/desk/desk.schema.json" <<'PY'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
card = {"id": "a", "kind": "decision", "title": "t", "why": "w", "status": "done",
        "answer": {"at": "2026-09-25T09:00:00Z"}}
errors = list(jsonschema.Draft7Validator(schema).iter_errors({"cards": [card]}))
print([e.message for e in errors])
sys.exit(0 if errors else 1)
PY
	[ "$status" -eq 0 ]
	[[ "$output" == *"'resolution' is a required property"* ]]
}

@test "agree: the brief's branch is the handoff's, and the run's head is the lane's" {
	branch=$(sed -n 's/^EPIC wc-3: branch \([^,]*\),.*/\1/p' "$EX/1-brief.md")
	[ "$branch" = "$(jq -r .branch "$EX/4-ready/handoff/wc-3.json")" ]
	[ "$branch" = "$(jq -r .branch "$EX/2-working/handoff/wc-3.json")" ]
	[ "$(jq -r .head "$EX/3-run/runs/run-wc-3-1.json")" = "$(jq -r .lane.head "$EX/4-ready/handoff/wc-3.json")" ]
	[ "$(jq -r .gates.status "$EX/3-run/runs/run-wc-3-1.json")" = "$(jq -r .lane.verdict "$EX/4-ready/handoff/wc-3.json")" ]
}

@test "agree: the READY line is well formed, and its sha is the one the landing checked" {
	line=$(cat "$EX/5-ready-line.txt")
	[[ "$line" =~ ^EPIC\ wc-3\ READY\ ([0-9a-f]{40})\ https://[^\ ]+$ ]]
	sha=${BASH_REMATCH[1]}
	grep -q "is \`$sha\`" "$EX/6-landing.md"
}

@test "agree: the owner's answer, applied to the open card, gives the answered card" {
	run jq -n --slurpfile open "$EX/7-desk/desk-open.json" --slurpfile a "$EX/7-desk/answer.json" \
		--slurpfile answered "$EX/7-desk/desk-answered.json" '
		($open[0].cards | map(if .id == $a[0].card then . + {status: $a[0].status, answer: $a[0].answer} else . end))
		== $answered[0].cards'
	[ "$output" = true ]
}
