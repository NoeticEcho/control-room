# Roadmap

## CR-1: generic scripts, with tests

- **`scripts/guard`**: the worker guard as a PreToolUse-style hook. It reads
  a JSON event on stdin and denies with a reason and an "instead". The rules
  are in `docs/protocol.md` § The guard.
  - POSIX sh plus jq, shellcheck clean.
  - A test per rule, including chained and wrapped commands, and tests that
    everything else passes through.
  - Wired for Claude Code hooks (`scripts/README.md`); where a runner has no
    pre-command hook, the same script runs as a git `pre-push` hook.
  - Configured by `control-room.json`: the integration branch and the branch
    prefix.
- **`scripts/validate-handoff`**: the schema, plus what the schema cannot
  state:
  - the file name matches `epic`, and the branch carries the prefix;
  - a ready handoff has a passing lane and no open child;
  - `deferred` has a `note`, and `reparented` has a `to`;
  - every sha is 40 hex characters.
  - Python 3 with jsonschema, so a real implementation checks the schema.
- **CI**: `make check` (shellcheck and both bats suites) on pull requests and
  on `main`, actions pinned by commit.

## CR-2: runners

- **`runners/claude-code-cloud/`**: a setup-script template, the opening
  message, the brief command. Proven in use.
- **`runners/local/`**: `cr-worker new <profile> <epic> <slug>` makes the
  worktree and branch and starts the session with the profile set.
  `cr-worker brief <profile> brief.md` delivers the brief as a user message.
  Documented shared-machine hazards.
- **`runners/e2b/`**: create a sandbox, clone, install the agent CLI, start
  the agent headless with the opening message and the brief. Keep the API key
  out of the repository.
- **`runners/codex/`**: map the protocol onto Codex cloud tasks, verified
  against Codex's documentation. Say plainly what could not be verified.

## CR-3: the desk

- `desk/index.html` renders `desk.json` with copy buttons, and works without
  a server.
- `desk/github-issues.md`: the Issues variant, with labels and a reminder
  script.

## CR-4: an end-to-end example

A small public example repository, run through one full epic: brief, worker,
READY, landing. Recorded as a transcript.
