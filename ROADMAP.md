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

- `desk/index.html` renders `desk.json` with no server and no framework:
  every card field, whole texts with copy buttons, choices with the
  recommended one marked, light and dark, phone width. An answer is a JSON
  snippet to paste to the coordinator, the desk's only writer.
  `desk/desk.schema.json` states the card; `desk/desk.example.json` has three
  cards. Tested in node without dependencies.
- `desk/github-issues.md`: the Issues variant, with the labels `decision`,
  `action`, `answered`, `done`, an issue template, and `desk/gh-desk` for the
  coordinator's hourly check.

## CR-6: local-ci

`ci/local-ci` runs a repository's check on the coordinator's machine and
posts the verdict as a commit status, with no Actions minutes
([`docs/local-ci.md`](docs/local-ci.md)). Written when hosted CI stopped
starting jobs over billing.

## CR-4: an end-to-end example

`examples/end-to-end/`: epic `wc-3` on a toy repository, as the files the
protocol produces (brief, handoff at `working` and `ready`, recorded check,
READY line, landing notes, desk card and answer). Written by a replay with
real git commands and fixed dates; `make check` replays it, compares, and
runs the validator on every handoff.

Next: the same epic run by a real worker session on a public repository,
recorded as a transcript.

## CR-5: desk answers

What daily use of the desk taught, ported as behaviour:

- **The page checks each card** against the schema before rendering, and shows
  a card that does not fit as malformed, with its raw JSON. A field the page
  silently ignored once hid every recommendation for days.
- **Structured questions:** several questions in one card, answered with
  pills; the note is composed as `<id> <key>` lines, with a live preview.
- **Quoting** a context paragraph into the answer with one tap.
- **A glossary** of terms, epics and abbreviations, and an id pattern, shown
  as text-only tooltips.
- The Issues variant answers questions as `Q1 a` lines, which `gh-desk`
  passes through as written.
