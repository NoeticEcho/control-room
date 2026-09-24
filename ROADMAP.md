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

- **`runners/claude-code-cloud/`**: the setup-script template, the opening
  message (`cr-cloud opening`), the brief command (`cr-cloud brief`, which
  runs `claude -p --cloud`), and why a cross-session message is not a brief.
  Proven in use; the flags checked against the documentation.
- **`runners/local/`**: `cr-worker new <profile> <epic> <slug>` makes the
  worktree and branch and records the profile; `cr-worker start <profile>`
  opens the headless session; `cr-worker brief <profile> brief.md` delivers
  the brief as a user message in that session. Claude Code's
  `--session-id`/`--resume` verified by a real run. Documented shared-machine
  hazards. Tested with a fake agent.
- **`runners/e2b/`**: `cr-e2b start` creates a sandbox, clones, installs the
  agent CLI, sets the profile and starts the agent headless with the opening
  message and the brief. Keys only from the environment. Tested against a
  fake SDK, with a contract test against the real one; the live path is
  unverified until a first run with a key.
- **`runners/codex/`**: the protocol mapped onto Codex cloud chats from
  Codex's documentation, with links and what could not be verified; the
  guard's rules for `AGENTS.md`, since Codex cloud has no documented
  pre-command hook.

## CR-3: the desk

- `desk/index.html` renders `desk.json` with copy buttons, and works without
  a server.
- `desk/github-issues.md`: the Issues variant, with labels and a reminder
  script.

## CR-4: an end-to-end example

A small public example repository, run through one full epic: brief, worker,
READY, landing. Recorded as a transcript.
