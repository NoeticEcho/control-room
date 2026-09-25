# Runners: where a worker runs, and how it is briefed

The protocol is the same everywhere. What changes per runner is only:
- how a session is created;
- how it learns its profile;
- how the brief reaches it as a user message.

Each section says what has been used in practice and what has not. The
scripts and the details for each runner are in [`runners/`](../runners/).

## Claude Code cloud sessions: used daily

- **Environment, once per profile.** On claude.ai/code, add a cloud
  environment for the repository:
  - network allowlist: the package registries of your stack;
  - an environment variable naming the profile;
  - the setup script pasted **whole**.

  When the setup box runs, the repository may not be cloned yet, so a
  one-line `bash scripts/setup.sh` can fail to start.
- **Knowing it is a worker.** Claude Code sets `CLAUDE_CODE_REMOTE=true` in a
  cloud session. The agent instructions branch on it: coordinator or worker.
- **Session.** The owner opens a session with the opening message
  (`prompts/en/worker-opening.md`). The worker replies
  `WORKER <profile> READY`. The owner gives the coordinator the session URL
  **and says which profile it is**.
- **Brief.**

      claude -p "$(cat brief.md)" --cloud <session-url> < /dev/null

  It arrives in the running session as a user message
  (`runners/claude-code-cloud/cr-cloud brief` runs it). A message relayed
  from another session is not a brief.
- **Pull requests.** The cloud VM may have no `gh`. The worker opens pull
  requests through its GitHub tools. The guard judges both forms.

## Codex cloud tasks: not yet used here

Mapped from Codex's documentation in
[`runners/codex/`](../runners/codex/README.md), with links:
- one cloud environment per profile, the profile as an environment variable;
  the setup script runs after the checkout, and secrets are gone before the
  agent starts;
- the opening message and the brief are the chat's prompt
  (`codex cloud exec --env <id>`); follow-ups reach a running chat only
  through the web UI;
- the person opens the pull request from the chat;
- no pre-command hook is documented for Codex cloud, so the guard's rules go
  into `AGENTS.md` ([`AGENTS-worker.md`](../runners/codex/AGENTS-worker.md))
  and the landing check enforces them on the coordinator's side.

## e2b sandboxes: not yet used here

[e2b](https://e2b.dev) gives isolated cloud sandboxes through an SDK.
[`runners/e2b/cr-e2b`](../runners/e2b/README.md) does the following, tested
against a fake SDK; the live path is unverified:
1. create a sandbox from a template with the repository's toolchain;
2. clone the repository;
3. install the agent CLI;
4. set the profile variable;
5. start the agent headless with the opening message and the brief;
6. keep the sandbox alive while the agent works.

The worker still pushes its branch and opens a pull request. The sandbox's
state never matters to the protocol. Secrets for the agent's model API are
passed at sandbox creation and never written to the repository.

## Local worktrees: many agents on one machine

For owners without cloud sessions, or alongside them:
- **One git worktree per worker**, each on its own epic branch:

      git worktree add ../w-backend -b <prefix>/<epic>-<slug> origin/<integration>

- **One agent session per worktree**, started with the profile variable set,
  so that its instructions take the worker branch. The brief is its first
  user message; follow-ups resume the same session.
  [`runners/local/cr-worker`](../runners/local/README.md) does both with
  Claude Code's headless mode (`-p` with `--session-id`, then `--resume`),
  verified by a real run.
- **Shared-machine hazards:**
  - the git stash is shared between worktrees, so never use a bare
    `git stash`;
  - stage explicit paths only, never `git add -A`;
  - heavy jobs run one at a time: parallel test suites on a small machine
    turn green into red.
- **The coordinator** is one more session, in its own worktree, and merges in
  a throwaway checkout.

## Choosing

| You have | Use |
|---|---|
| Claude Code with cloud sessions | cloud sessions: the most tested path |
| Codex | Codex cloud tasks, and verify the follow-up path first |
| An API key and no cloud sessions | e2b sandboxes, or local worktrees |
| One strong machine | local worktrees. Parallelism is bounded by cores and by the coordinator's landing checks |
