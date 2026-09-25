# Local worktrees: many workers on one machine

`cr-worker` runs each worker as a headless agent session in its own git
worktree, on its own epic branch, with its profile in the environment.

```sh
cd path/to/repo                        # any worktree of the project
cr-worker new backend proj-12 login    # worktree + branch claude/proj-12-login
cr-worker start backend                # the session, with the opening message
cr-worker brief backend brief.md       # the brief, as the next user message
cr-worker brief backend answer.md      # later: an answer, a question, the next brief
```

- **`new <profile> <epic> <slug>`** fetches the integration branch and makes a
  worktree at `$CR_WORKTREES/<profile>` (default `<repo>/../<repo>-workers/`)
  on `<prefix><epic>-<slug>` from `origin/<integration>`. The branch does not
  track the integration branch, so a bare `git push` cannot land there. The
  profile, the epic, the branch and a session id go into the worktree's own
  git directory (`.git/worktrees/<profile>/cr-worker/`), where no commit can
  pick them up. For the worker's next epic, `new` again switches the same
  worktree to the new branch, if it is clean, and keeps the session.
- **`start <profile>`** runs the agent in the worktree with the profile
  variable set, and sends the opening message ([`opening.md`](opening.md),
  filled in) as the first turn of a new session. The worker answers
  `WORKER <profile> READY`.
- **`brief <profile> <file>`** sends the file as the next user message in that
  session. A file that does not start `EPIC <id>: branch ...` still goes
  through, with a warning: the worker will treat it as a question.
- **`path <profile>`** prints the worktree; **`env <profile>`** prints
  `export CR_PROFILE=<profile>` for a shell of your own
  (`eval "$(cr-worker env backend)"`).

Everything the agent prints is shown and appended to
`.git/worktrees/<profile>/cr-worker/log`.

## How the session works (Claude Code)

`start` runs, in the worktree:

    claude -p "<opening>" --session-id <uuid>

and each `brief` runs:

    claude -p "<brief>" --resume <uuid>

Each call is one headless turn: it returns when the worker ends its turn, with
its last line (`WORKER … READY`, `EPIC … READY …`, `EPIC … BLOCKED …`).

**Verified** on Claude Code 2.1.282, on 2026-09-24:

- `claude --help` lists `--session-id <uuid>` ("must be a valid UUID") and
  `-r, --resume`;
- the headless documentation shows `claude -p "..." --resume "$session_id"`
  continuing a conversation, and says the session is found by id in any
  project on the machine (<https://code.claude.com/docs/en/headless>);
- a real run: `claude -p … --session-id <uuid>` answered `WORKER docs READY`
  after reading `CR_PROFILE` with a shell command; then
  `claude -p "<brief>" --resume <uuid>` answered with its previous reply,
  under the same `session_id`. The brief arrived as a user message in the same
  conversation.

**Permissions.** A headless session cannot ask anyone to approve a tool. Give
it what a worker needs through the project's `.claude/settings.json`
(allow rules, and `scripts/guard` as a PreToolUse hook, see
`scripts/README.md`) and through `CR_AGENT_ARGS`, for example:

    CR_AGENT_ARGS="--permission-mode acceptEdits --permission-prompts none"

`--permission-prompts none` denies whatever nothing else allows, instead of
waiting. Choose the mode for your project; `bypassPermissions` belongs only
in a sandbox.

**The agent's instructions.** A project's `CLAUDE.md` or `AGENTS.md` usually
tells a worker from the coordinator by `CLAUDE_CODE_REMOTE=true`, which only
cloud sessions have. For local workers, branch on the profile variable
(`CR_PROFILE` set) instead, or as well.

## Configuration

`control-room.json` at the repository root: `integration_branch` (`main`),
`branch_prefix` (`claude/`), `profile_variable` (`CR_PROFILE`).

Environment: `CR_AGENT` (the agent CLI, default `claude`), `CR_AGENT_ARGS`
(extra arguments for every call, split on spaces), `CR_WORKTREES`,
`CR_OPENING` (another opening template; `<profile>`, `<profile-variable>`,
`<integration-branch>`, `<prefix>` and `<branch>` are filled in).

## Shared-machine hazards

Worktrees share one repository, and workers share one machine.

- **The git stash is shared** between all worktrees. A bare `git stash` in
  one worker's worktree and `git stash pop` in another's moves one worker's
  work into another's branch. Never use a bare `git stash`; commit instead,
  or name the stash and check it is yours.
- **`git add -A` stages whatever is in the worktree**, including files a tool
  or another process dropped there. Stage explicit paths only.
- **Heavy jobs in parallel turn green into red.** Two full test suites or
  builds on a small machine time out, run out of memory, or fight over ports
  and caches, and a failure that is load, not code, costs a landing. Run
  heavy jobs one at a time (a lock such as `flock /tmp/cr-heavy.lock make
  check` is enough), and give each worker its own ports and cache paths
  where the stack needs them.
- **Branches and refs are shared.** A branch is checked out in one worktree
  at a time; `new` refuses a branch that exists. The coordinator deletes
  landed branches, never a worker.
- **One login for all.** Every session uses the same agent and GitHub
  credentials. The guard stops a worker from pushing someone else's branch;
  nothing stops it from reading another worktree.

The opening message tells the worker the first three.

## Tests

`tests/cr-worker.bats` runs `cr-worker` in a temporary repository with a fake
agent (`tests/fixtures/fake-agent`) that records its arguments, working
directory and profile.
