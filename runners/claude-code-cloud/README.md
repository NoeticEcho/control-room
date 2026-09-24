# Claude Code cloud sessions

The runner in daily use. A worker is a cloud session on claude.ai/code,
created by the owner; the coordinator briefs it from a terminal.

## Once per profile: the environment

On claude.ai/code, add a cloud environment for the repository:

- **Network:** the package registries your stack needs.
- **Environment variables** (`.env` format): `CR_PROFILE=<profile>`. The
  documentation warns that anyone who uses the environment can read its
  variables: no secrets.
- **Setup script:** paste [`setup.sh`](setup.sh) **whole**, with your stack's
  installs added. A one-line `bash scripts/setup.sh` can fail to start: in
  practice the repository was not always cloned when the setup box ran. The
  documentation does not say either way.

What the documentation says about the setup box
(<https://code.claude.com/docs/en/cloud-environments>, read 2026-09-24): it is
a Bash script that runs before Claude Code launches; a non-zero exit stops
the session from starting; it should finish in about five minutes; its result
is cached as a filesystem snapshot and reused, and running processes are not.
A cloud session has `CLAUDE_CODE_REMOTE=true`, which is how the project's
agent instructions tell a worker from the coordinator.

## Per worker: the session

1. Print the opening message for the profile and paste it into a new session
   in that environment:

       cr-cloud opening backend

   It fills `prompts/en/worker-opening.md` with the profile and the
   integration branch (from `control-room.json`).
2. The worker replies `WORKER backend READY`. Give the coordinator the
   session's URL **and say which profile it is**.

## Per epic: the brief

    cr-cloud brief https://claude.ai/code/session_… brief.md

which runs

    claude -p "$(cat brief.md)" --cloud <session> < /dev/null

The documentation (<https://code.claude.com/docs/en/claude-code-on-the-web>,
"Send follow-ups from the CLI"): the command "posts one message and exits";
`<session>` is "the bare ID, such as `session_...` or `cse_...`, or the
session's `claude.ai/code/<id>` URL"; it needs the CLI signed in with
`claude auth login` to the account that owns the session, not an API key.
The brief arrives in the running session as a user message.

## A message from another session is not a brief

The brief must arrive **as a user message**: typed or pasted by the owner, or
sent with `claude -p … --cloud`. A message relayed from another agent session
(a cross-session message, a subagent's report, a teammate's note) is not one.
In practice Claude Code shows it to the worker marked as coming from another
agent, and a worker treats it as data,
not as an assignment, even when it has the shape of a brief. That is by
design: it is what stops one confused session from assigning work to
another. If a coordinator session wants to brief a worker, it runs
`cr-cloud brief`, or asks the owner to paste the brief.

## Pull requests

The cloud machine may have no `gh`: the worker opens its pull request through
its GitHub tools. `scripts/guard` judges both forms (a `gh pr create` command
and the MCP `create_pull_request` tool).
