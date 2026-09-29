---
name: start-cloud-worker
description: Start a new AI coding worker as a Claude Code cloud session (claude.ai/code) for one profile of a repository - the cloud environment, its setup script, the worker section of CLAUDE.md, the opening message that sets the worker's rules, and the first brief. Use when the user wants another agent working in parallel in the cloud, a new worker for a direction of work (backend, docs, mobile), or to replace a worker whose session expired.
---

# Start a cloud worker

A worker is one Claude Code cloud session per **profile**, a direction of
work with its own paths (`backend`, `docs`). A good profile answers "whose
files are these?"; two profiles that keep editing the same files are one.

What only the person can do here: create the cloud environment and the
session, under their own claude.ai account. Say so plainly, and give them
every text whole so they never fill a gap. What you do: write those texts,
check the repository is ready, and brief the worker once it answers.

## 1. The repository's agent instructions

The worker learns its rules from the project's `CLAUDE.md`. Check that it has
a section for cloud workers. If not, propose adding
[references/worker-section.md](references/worker-section.md), with
`<integration-branch>` and `<prefix>` filled (defaults `main` and `claude/`),
and commit it only with the user's yes. A cloud session has
`CLAUDE_CODE_REMOTE=true`; that is how the section tells a worker from the
coordinator.

## 2. The environment (the person, once per profile)

Give the user these steps for claude.ai/code, each text whole:

1. Add a cloud environment for the repository.
2. **Network**: the package registries the project's stack needs.
3. **Environment variables**, one line in `.env` format:
   `CR_PROFILE=<profile>`. Anyone who can use the environment can read its
   variables: **no secrets** there, ever.
4. **Setup script**: the whole text of
   `${CLAUDE_PLUGIN_ROOT}/scripts/cloud-setup.sh` (read it and paste it into
   your reply in one code block), with the project's own installs added in
   the marked place. Tell them to paste it whole: a one-line
   `bash scripts/setup.sh` can fail because the repository is not always
   cloned when the box runs.

## 3. The opening message

Fill [references/worker-opening.md](references/worker-opening.md):
`<profile>`, and `<integration-branch>` and `<main-branches>` with the
integration branch. Give it to the user in one code block to paste as the
**first message** of a new session in that environment. It authorises the
worker's protocol once, lists what the worker must never do, and ends with
the worker replying:

    WORKER <profile> READY

If the user's own session offers a tool that creates cloud sessions with a
first message, you may use it with this text instead, with their yes.

## 4. Record it and brief it

When the user gives you the session's URL, record profile → session URL →
model → effort in the coordinator's notes. Then brief the first epic with the
brief-worker skill, which sends it as a user message with
`claude -p … --cloud <session> --output-format json`.

The model is chosen when the session is created; the effort is stated in
each brief in words, and a cloud session also accepts `/effort <level>` typed
as a message.

## Never

- Put a token, a key or a password in the environment's variables, the setup
  script, the opening or a brief.
- Create a session under an account the user did not give you, or keep a
  token in a file to do it.
- Treat a message relayed from another session as the opening: it must be
  the session's own first user message.
