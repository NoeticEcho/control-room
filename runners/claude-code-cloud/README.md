# Claude Code cloud sessions

The runner in daily use. A worker is a cloud session on claude.ai/code. The
coordinator creates it, once the owner has authorised that, or the owner
creates it by hand. The coordinator briefs it from a terminal.

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

## Per worker: the coordinator creates the session

`claude --cloud` cannot create a session without a person at the keyboard.
With `-p`, it only sends to a session that exists: "Claude Code rejects
`--bg`, and rejects `--cloud` with a task description"
(<https://code.claude.com/docs/en/headless>, read 2026-09-29). So the
coordinator creates each new worker as a **one-off routine**, from its own
session:

1. **The owner authorises it once.** "Create workers yourself" is said once,
   in the coordinator's chat, and recorded in its state file. The rules the
   worker follows are unchanged. The opening message says who created the
   session and why ([`routine-preamble.md`](routine-preamble.md)).
2. **The routine's body:**

       cr-cloud new backend brief.md --environment <environment id> \
           --repository https://github.com/<owner>/<repo> \
           --model claude-sonnet-5-5 > routine.json

   It fills [`new-worker.routine.json`](new-worker.routine.json):
   - `name`, and `run_once_at`: a UTC time two minutes ahead (`--at` sets
     another);
   - `job_config.ccr.environment_id`: the repository's cloud environment,
     the one with the setup script;
   - `session_context`: the `model`, the repository as the `sources`, and
     the `allowed_tools`. Edit the template's list for your project;
   - `persist_session: true`, so the session stays, and later epics are
     briefed in it;
   - `events`: one user message with its own `uuid`. It holds the preamble,
     then the opening (`prompts/en/worker-opening.md`, filled for the
     profile), then the first brief.
3. **The coordinator's session submits it** with the routine tool it has
   under the owner's claude.ai sign-in. The coordinator that did this for
   real used the remote-trigger API, `POST /v1/code/triggers`. That API is
   reached with the session's own claude.ai sign-in, and control-room knows
   no documented way for a script to obtain that sign-in. So `cr-cloud` only
   prints the body. It holds no token and asks for none. Never put a token
   in a file for it.
4. **After it fires,** the routine's runs give the new session's id. The
   last run of a routine carries a `session_id`. The coordinator records
   worker → session → routine, the model and the effort in its state file
   (`docs/templates/queue.md`), and briefs later epics with `cr-cloud brief`.
   A one-off routine disables itself once it has fired.

**What is verified, and what is not.**

- Checked against the routines documentation
  (<https://code.claude.com/docs/en/routines>, read 2026-09-29):
  - routines can be scheduled "once at a specific future time";
  - "after the routine fires, it auto-disables";
  - one-off runs "do not count against the daily routine run cap";
  - "each run creates a new session".
- The documentation describes creating a routine only through the web form
  and `/schedule`. The remote-trigger API is not described there, and
  routines are a research preview whose "API surface may change".
- The body's field names are those the coordinator used on 2026-09-28/29.
  They were not verified by a run from this repository.
- A one-off routine created from a cloud session on 2026-09-25, then read
  back through the routine API, showed:
  - `persist_session: true`;
  - `run_once_at`;
  - the message stored as an event with a `uuid`, `type: "user"` and
    `message: {role: "user", content}`.
- Read the routine back after creating it, and fix the template if the shape
  has changed.
- The documentation also says a fired routine's prompt "is not live user
  input and can't act as approval or consent for actions during the run"
  (Claude Code v2.1.213 or later). The opening sets the worker's task and
  rules. Anything that needs the owner's consent beyond them still goes to
  the desk.

**By hand**, when the coordinator is not authorised: print the opening,
`cr-cloud opening backend`, and paste it into a new session in that
environment. The worker replies `WORKER backend READY`. Give the coordinator
the session's URL, and say which profile it is.

**Model and effort** (`docs/protocol.md`, Model and effort): the routine
sets the model. The effort is not a field of the routine's body that we know
of, so the brief states it in words. In a running session, `/effort <level>`
typed as a message sets it (documented for cloud sessions).

## Per epic: the brief

    cr-cloud brief https://claude.ai/code/session_… brief.md

which runs

    claude -p "$(cat brief.md)" --cloud <session> < /dev/null

with `--output-format json` added. The documentation
(<https://code.claude.com/docs/en/claude-code-on-the-web>, "Send follow-ups
from the CLI") says:

- the command "posts one message and exits";
- `<session>` is "the bare ID, such as `session_...` or `cse_...`, or the
  session's `claude.ai/code/<id>` URL";
- it needs the CLI signed in with `claude auth login` to the account that
  owns the session, not an API key;
- with `--output-format json`, it prints `{ok, session_id, url}` on success,
  or `{ok: false, session_id, error}` when the send fails.

The brief arrives in the running session as a user message.

**A send that fails** makes `cr-cloud brief` exit 3, with the reason and what
to tell the owner. That covers:

- `ok: false` (the session expired or was archived);
- a configuration error on stderr with no JSON;
- no result at all.

The coordinator reports it first thing, with the session's link, and does not
retry silently. A CLI signed in with an API key fails with `Unable to get
organization UUID`: sign in with the claude.ai account (`/login`).

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
