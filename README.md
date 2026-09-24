# control-room

**One person, one AI coordinator, many AI programmers — and one desk where
every decision that needs the person waits, instead of getting lost across a
dozen chats.**

control-room is a protocol, a set of prompts and a few small scripts for
running several AI coding agents in parallel on one repository, each on its
own branch, with one coordinator that plans, briefs and lands their work. It
is stack-neutral: the agents can be Claude Code, Codex or any agent that works
in a git checkout, in the cloud, in an [e2b](https://e2b.dev) sandbox, or
locally in git worktrees.

It came out of daily use: one person, a local coordinator and six cloud
workers building one product. The rules below are the ones that survived.

## What you get

| Role | Does | Never does |
|---|---|---|
| **Owner** (a person) | Answers the desk. Creates the workers' sessions. Holds the credentials. | Pastes secrets into a chat or a worker's environment. |
| **Coordinator** (a local agent session) | Splits goals into epics, writes briefs, is the **only writer** of the task tracker and the **only lander** on the integration branch. Keeps the desk. | Lands a branch it did not check. Decides what only the owner may decide. |
| **Worker** (an agent session per profile) | Takes one epic from a brief, works on its own branch, pushes every turn, ends with a pull request and one line: `READY` or `BLOCKED`. | Merges, pushes an integration branch, writes the tracker, or edits outside its brief's scope. |

The work goes one way and comes back another:

```text
brief (coordinator → worker, as a user message)
  → branch + handoff/<epic>.json
  → the checks, recorded
  → pull request + "EPIC <id> READY <sha> <url>"
  → landing (coordinator: scope, checks, merge --no-ff, CI after push)
  → tracker closed, every finding filed, the next brief
```

## Start here

1. **Read [`docs/protocol.md`](docs/protocol.md).** It is the whole system in
   one page.
2. **Hand [`prompts/en/master.md`](prompts/en/master.md) to an AI programmer**
   in your repository (Claude Code or Codex). It interviews you, writes a
   design for your project, waits for your yes, builds the pieces for your
   stack, and pilots one worker before any other.
3. **Pick runners** from [`docs/runners.md`](docs/runners.md): cloud sessions,
   e2b sandboxes, or local worktrees.
4. **Pick a desk** from [`docs/desk.md`](docs/desk.md): GitHub Issues, or the
   static page in [`desk/`](desk/).

## What is in the box

| Path | What |
|---|---|
| `docs/protocol.md` | Roles, the brief, the handoff, the READY/BLOCKED lines, the landing checklist |
| `docs/runners.md` | How a worker is started and briefed on each runner |
| `docs/desk.md` | The decision desk: what a card holds, statuses, reminders |
| `docs/lessons.md` | What went wrong in practice, and the rule each failure produced |
| `prompts/en/`, `prompts/ru/` | The master prompt, the owner interview, the coordinator session, the worker's opening message, the brief template |
| `schemas/handoff.schema.json` | The handoff's JSON Schema, and an example |
| `desk/` | A static desk page that reads a JSON queue (CR-3, see ROADMAP) |
| `scripts/guard` | The worker guard: a pre-command hook (or git pre-push hook) that refuses pushes to other branches, force pushes, tags, branch deletions and merges |
| `scripts/validate-handoff` | Checks a handoff against the schema and the rules a schema cannot state |
| `scripts/README.md` | How to wire the guard into `.claude/settings.json`, and what it does not catch |
| `Makefile`, `tests/` | `make check`: shellcheck and the bats suites, also run in CI |

## Status

Early. The protocol and prompts are in daily use; the scripts and runners are
being generalised from the project they came from. See
[`ROADMAP.md`](ROADMAP.md).

## Licence

Apache-2.0. Made by [NoeticEcho](https://github.com/NoeticEcho).
