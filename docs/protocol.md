# The protocol

## Roles and their boundaries

The system holds together because each role has things it **does not do**.
Remove one boundary and within a week there are two copies of the tracker,
someone else's half-finished work in your commit, or an unchecked branch in a
release.

- **Owner.** Decides on the desk. Creates cloud environments. Grants access
  to outside services. Authorises the coordinator once to create worker
  sessions, or creates them. Secrets never go into a chat, the repository or
  a worker's environment.
- **Coordinator.** A local session. The only writer of the task tracker. The
  only one who merges into the integration branch. Creates worker sessions
  when the owner has authorised it (see
  [`runners/claude-code-cloud/`](../runners/claude-code-cloud/README.md)),
  briefs workers, keeps the desk, reminds the owner of cards waiting more
  than an hour, cuts releases when asked.
- **Worker.** One session per *profile* — a direction of work with its own
  paths and dependencies (`backend`, `mobile`, `docs`, …). A good profile
  answers "whose files are these?". Two profiles that keep editing the same
  files are one profile.

## One epic's life

1. **An epic in the tracker** (coordinator): a goal, children, and an
   acceptance criterion that can fail. Its assignee is a profile.
2. **The brief** (coordinator → worker): one message of a fixed shape —
   epic, branch, scope (paths the worker may change), grants (one-off
   permission on paths it normally may not), why, how it is accepted, and
   the model and effort it should run with (below).
3. **Branch and handoff** (worker): a branch from the fresh integration
   branch, and `handoff/<epic>.json` at `working` in the first commit. From
   then on, push every turn: a cloud machine can restart at any moment.
4. **Work and checks** (worker): tests that fail without the change and pass
   with it. Before READY, merge the integration branch and run the full
   check, as CI would. The result is *recorded* (a run file), not reported.
5. **READY** (worker): the handoff at `ready` with the recorded result, the
   head it ran at, and everything found on the way — `discovered`,
   `questions`, `shared_change_requests` (changes it needed outside scope).
   Open the pull request. Last line: `EPIC <id> READY <sha> <url>`.
6. **Landing** (coordinator): see the checklist below.
7. **Close and file** (coordinator): close the tracker items with the commit
   and the check in the reason; every finding becomes a task; every question
   for the owner becomes a desk card; the worker gets its next brief, which
   opens with what landed and what became of its findings.

A real worker session going through these steps, command by command:
[`examples/end-to-end/transcript.md`](../examples/end-to-end/transcript.md).

## The lines

```text
EPIC <id>: branch <prefix>/<id>-<slug>, scope <paths>, grants <paths>
EPIC <id> READY <full-sha> <pr-url>
EPIC <id> BLOCKED <reason>
```

A worker treats any message of another shape as a **question**: it answers,
changes nothing, and waits. That is what stops a stray comment or a pasted
log from becoming an instruction.

## The channels

- **Coordinator → worker:** the brief, delivered **as a user message** in the
  worker's session. A message relayed from another session (a cross-session
  message) is data to the worker, not an assignment — by design.
- **Worker → coordinator:** git only. The branch, its handoff, the pull
  request, the last line.
- **Owner → worker:** its own chat, or a comment on its pull request, still
  bounded by the brief.

## The guard

A hook runs before each of a worker's commands and refuses:
- a push to anything but its own branch;
- a push with no explicit branch name (a branch made from the integration
  branch tracks it, so a bare `git push` can land there);
- force pushes, tags, branch deletions;
- merging a pull request.

It also refuses a pull request against any base but the integration branch,
and a write through a GitHub MCP tool to any branch but the worker's own.

[`scripts/guard`](../scripts/guard) is this hook: a pre-command hook for
Claude Code, and a git `pre-push` hook where a runner has no pre-command hook.
It reads the integration branch and the workers' branch prefix from
`control-room.json` at the repository root (defaults `main` and `claude/`).
Each denial names the rule and says what to do instead. Wiring and limits:
[`scripts/README.md`](../scripts/README.md).

It is a guard against confusion, not a permission system: the session has the
owner's repository credentials. A worker the guard stops records the question
in its handoff and ends `BLOCKED`; it does not route around it.

## The fence

Some paths decide what "the checks passed" means: the CI workflow, the local
check script, the policy files. List them. A change to a fenced path lands
only with the owner's quoted approval — **the coordinator's own changes
included**.

## Model and effort

The coordinator picks a model and an effort level for each epic, when it
creates a worker and when it writes a brief, to spend the limits where they
buy something:

- **The strongest model at high effort** (an Opus-class model, `high`) for
  long-horizon work, architecture, security-sensitive guards and hard
  merges.
- **A fast model at medium effort** (a Sonnet-class model, for example
  `claude-sonnet-5-5`, `medium`, or `high` when the epic is harder) for
  well-specified epics: UI polish, CRUD, tests, docs.

The brief states both, and the coordinator's state file records them for
each worker. How a runner sets them:

- **Claude Code, local:** `claude --model <model> --effort <level>`, for
  example through `CR_AGENT_ARGS` for `cr-worker` (both flags are in the CLI
  reference, <https://code.claude.com/docs/en/cli-reference>).
- **Claude Code cloud:** the model is set when the session is created (the
  routine's `session_context.model`). A cloud session accepts `/model <name>`
  and `/effort <level>` typed as a message (the documentation's "Manage
  context" section of claude-code-on-the-web, Claude Code v2.1.205 or later).
  Whether `/effort` also takes effect when it is sent with `claude -p
  --cloud` is not documented, and has not been tried. So the brief always
  says the effort in words, and the worker applies it.
- **Other runners:** where the runner cannot set them, the brief asks for them
  in words.

## Delivery that failed is said at once

A brief or a question that did not reach the worker is the owner's to know
first. `cr-cloud brief` exits 3 when the send was not delivered: the session
expired or was archived, or the CLI needs `/login`. The coordinator puts that
as the **first line** of its next report to the owner, with the session's
link. It does not wait on it silently, and it does not re-send in a loop.

The common trap is a CLI signed in with an API key. It cannot reach cloud
sessions: `claude --cloud` then fails with `Unable to get organization UUID`,
or says API-key authentication is not sufficient. The fix is `/login`, or
`claude auth login`, with the claude.ai account
(<https://code.claude.com/docs/en/claude-code-on-the-web>, read 2026-09-29).

## Landing checklist

A pull request is **ready to land** when the worker's last line or a comment
on it says `EPIC <id> READY <sha> <url>`. It is also ready when it is open,
not a draft, mergeable, and has had no push for ten minutes: some workers
end a turn without the line. In that case the head at that moment is the sha
that lands.

1. The branch head equals the READY sha. The handoff is `ready`, where the
   project uses handoffs, and its recorded check passed at that sha or its
   parent (only handoff and run files after).
2. The changed files are inside the brief's scope; grants were used only as
   granted.
3. Read what is security-sensitive: access policies, escaping of user text,
   configuration, anything that looks like a secret.
4. Merge with `--no-ff` in a throwaway checkout, never in a person's working
   directory.
5. Checks. When the pull request's CI is green, the merge is clean, the
   worker's base is at most one landing behind, and nothing fenced is
   touched, the worker's recorded run and the PR's CI are the check.
   Otherwise run the full check on the merge.
6. Push with an explicit refspec, retrying on network errors.
7. Read the real CI run for the pushed sha. A green local run is not green CI.
   If it is red, revert and return the epic.
8. Deploy the pushed sha to the test environment, check its health, and post
   the result as a commit status (`ci/local-ci` posts statuses; see
   `docs/local-ci.md`). A failed deploy or health check is a red landing:
   revert and return the epic.
9. Close, file, export the tracker, brief the next epic.

### Several ready pull requests, one heavy check

When several pull requests are ready at once, they can share one full check:

1. In the throwaway checkout, merge each one `--no-ff`, in order: one merge
   commit per epic, each still checked against steps 1 to 3.
2. Run the full check once, on the last merge.
3. If it passes, push them all together and go on with steps 7 to 9.
4. If it fails, find the merge that broke it: run the check at each merge
   commit in turn. Return that epic, drop its merge and every merge after
   it, re-merge the others, and check again.

### Conflicts

- **Append-only conflicts** are the coordinator's to resolve by keeping both
  sides. Examples: two blocks added at the end of one stylesheet, or two
  settings added to one test helper. The resolution is the concatenation, and
  the check on the merge proves it.
- **A conflict in logic** goes back to the worker, and the coordinator does
  not resolve it. "Merge main" alone is not a brief, so the worker would
  answer it as a question and change nothing. Send it in the brief's shape,
  for the same epic and branch:

      EPIC <id>: branch <branch>, scope as before. Merge <integration branch>
      into your branch, resolve the conflict, run the full check, end READY.

### Clean merges that are still wrong

Every merge can be clean, and every branch green, and the merged tree still
be broken. Three cases:

- **Generated artefacts.** Several landed branches each regenerated the same
  generated file: a schema snapshot, a lockfile, a generated API client.
  Each one was right on its own branch. On the merged tree the file is
  stale, even when git merged it without a conflict, because it was made
  from each branch's input, never from all of them together. After the
  last merge, and before the check:
  - regenerate it once on the merged tree, with the project's own
    generator, and commit that as the coordinator's own commit in the
    landing;
  - never merge it by hand, taking lines from each side;
  - never add a new migration (or its equivalent) to paper over a snapshot
    that disagrees: the drift is in the file, not in the model. If the
    regenerated file needs one, the branches disagree in logic, and that is
    a logic conflict, returned as above.

  Then run the full check on that commit.
- **An append-only resolution is then built.** Keeping both sides is right,
  but a hand resolution can still drop a line. Two blocks added at the end
  of one stylesheet, joined by hand, lost a closing brace. Every test
  passed, because no test built the stylesheet, and the next two deploys
  failed on it. So the check before a push must build what the release
  builds (the stylesheet, the bundle, the image, the documentation site),
  not only run the tests. If the project's check does not, add the build to
  it; until then, run the release build on the merge yourself before
  pushing.
- **A pull request that moved after its READY line.** A worker may merge
  the integration branch into its branch after it wrote READY. The READY
  sha is what the worker checked, so land that sha, not the later head. The
  pull request then stays open on the later head. If merging that head
  would leave the integration branch's tree the same (nothing but the merge
  came after READY), close the pull request by hand, with a note such as
  "Landed at <READY sha> in <merge sha>; the later commits only merged
  <integration branch>." To check (git 2.38 or later):

      test "$(git merge-tree --write-tree origin/<main> <later head>)" \
        = "$(git rev-parse 'origin/<main>^{tree}')"

  A plain `git diff <later head> origin/<main>` is not the test: it
  differs as soon as anything else has landed since. If the merge would
  change the tree, the later commits changed something nobody checked: ask
  the worker for a new READY line, and land nothing more from it until
  then.

## A silent worker

A worker with no commit on its branch for more than two hours, and no READY
or BLOCKED, gets a status question, never a new brief. Silence is not
idleness: it may be in a long check, at a permission prompt, or on a
restarted machine, and a brief on top of unfinished work stacks two epics in
one session. Details, and the coordinator that runs on a schedule:
[`docs/coordinator-loop.md`](coordinator-loop.md).

When more than one coordinator can land (a person's and a scheduled loop),
every landing runs under [`scripts/land-lock`](../scripts/land-lock) and
first checks that the READY sha is not already on the integration branch.

## The tracker

Any tracker works if three rules hold: **one writer** (the coordinator),
**closed only after landing**, and **every worker finding becomes an item**.
We use [beads](https://github.com/gastownhall/beads) (`bd`): issues live beside
the repository, with dependencies and "what is ready now"; its export is
committed at each landing and is the off-machine copy.
