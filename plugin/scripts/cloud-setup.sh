#!/bin/bash
# control-room: setup script for a Claude Code cloud environment, one per
# worker profile. Paste it WHOLE into the environment's "Setup script" box on
# claude.ai/code; do not replace it with `bash scripts/setup.sh`, which can
# fail to start (see README.md).
#
# What the documentation says about this box (code.claude.com/docs/en/
# cloud-environments, read 2026-09-24): it is a Bash script that runs before
# Claude Code launches; it must exit zero or the session fails to start; it
# should finish within about five minutes; its result is cached as a
# filesystem snapshot for later sessions, so background processes do not
# survive. Anyone who can use the environment can read this script and the
# environment's variables: no secrets here.
#
# Set the profile as an environment variable of the environment, in .env
# format, one line:
#     CR_PROFILE=<profile>

set -u

log() { printf 'control-room setup: %s\n' "$*"; }

# The guard (scripts/guard) needs jq; the handoff validator needs Python 3
# with jsonschema. `|| true` keeps a flaky mirror from blocking the session;
# the guard itself refuses to pass commands it cannot check without jq.
if ! command -v jq >/dev/null 2>&1; then
	(apt-get update -qq && apt-get install -y -qq jq) || log "jq install failed"
fi
python3 -c 'import jsonschema' 2>/dev/null ||
	python3 -m pip install -q --break-system-packages jsonschema || log "jsonschema install failed"

# ---- your stack ------------------------------------------------------------
# Install what the profile's checks need and the base image lacks. Keep each
# step idempotent and tolerant, and run independent installs in parallel:
#
#   (apt-get install -y -qq shellcheck bats || log "shellcheck/bats failed") &
#   (npm install -g pnpm@9 || log "pnpm failed") &
#   wait

log "done for profile ${CR_PROFILE:-<unset>}"
exit 0
