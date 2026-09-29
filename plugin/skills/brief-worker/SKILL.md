---
name: brief-worker
description: Write and send the brief that assigns one epic to one AI coding worker in the fixed EPIC shape (branch, scope, grants, model and effort, acceptance that can fail) and deliver it as a user message in the worker's session. Use when the user coordinates several coding agents and wants to hand an epic, task or ticket to a worker, re-brief a worker after a conflict, or ask a silent worker for its status.
---

# Brief a worker

You are acting as the **coordinator**: one person, one coordinator, many
workers, each worker an agent session on its own branch. A brief is the only
way work reaches a worker, and the worker checks its shape: a message of any
other shape is a *question* to it, which it answers without changing
anything. So the shape is not decoration. Get it exactly right.

## 1. Collect what the brief needs

Ask the user only for what you cannot find in the repository or the
conversation:

- **Epic id and a slug**: `WEB-4`, `dark-mode`. The branch is
  `<prefix>/<id lowercased>-<slug>`, the prefix `claude/` unless the project
  says otherwise (a `control-room.json` at the repository root has
  `integration_branch` and `branch_prefix`).
- **Profile**: which worker, by its direction of work (`backend`, `docs`).
- **Scope**: the paths the worker may change, as globs. Narrow. Two workers
  whose scopes overlap will collide at landing.
- **Grants**: one-off permission on a path the worker normally may not touch,
  with exactly what may change in it. Usually none.
- **Acceptance**: checks that can fail. "Tests pass" is not one. "A settings
  toggle switches the theme, and `tests/settings.test` covers both states"
  is.
- **Model and effort**: pick them, say why in one line to the user.
  - The strongest model at `high` effort for long-horizon work,
    architecture, security-sensitive code and hard merges.
  - A fast model at `medium` (or `high` when it is harder) for
    well-specified epics: UI polish, CRUD, tests, docs.

## 2. Write it

Fill [references/brief-template.md](references/brief-template.md) whole, in
this order, and keep its first line exactly in this form:

    EPIC <id>: branch <prefix>/<id>-<slug>, scope and grants below.

Rules for the body:

- **What landed since your last epic** opens every brief after the first:
  the merge commit, and what became of each finding the worker reported.
- **Acceptance** always ends with: each new test fails without its change
  (show it), and the full local check passes.
- **Scope** lists every path, plus the handoff file
  `handoff/<id>.json` when the project uses handoffs.
- **Protocol** keeps the four lines of the template: branch from the fresh
  integration branch, push by the branch's own name every turn, open the
  pull request at the end, end with `EPIC <id> READY <sha> <pr-url>` or
  `EPIC <id> BLOCKED <reason>`.

Save it as a file (`briefs/<id>.md` in the coordinator's own notes, not in
the product's source tree), show it to the user, and send it only when they
agree, unless they already told you to send briefs yourself.

## 3. Send it, as a user message

The brief must arrive as a **user message in the worker's own session**. A
message relayed from another agent session is data to a worker, never an
assignment, by design.

- **Claude Code cloud session** (claude.ai/code): run

      claude -p "$(cat briefs/<id>.md)" --cloud <session id or URL> --output-format json < /dev/null

  It posts one message and exits. It needs the CLI signed in with
  `claude auth login` to the account that owns the session; a CLI signed in
  with an API key fails with `Unable to get organization UUID`. Read the
  JSON: `"ok": true` means delivered. On `"ok": false`, an error, or no
  output, the brief did **not** arrive: tell the user first, with the
  session's link, and do not resend in a loop.
- **Any other session** (a local terminal, Codex, a sandbox): give the user
  the brief to paste, whole, in one code block.

Record which worker got which epic, with the model and effort, where the
user keeps the coordinator's notes.

## Special briefs

- **A conflict in logic at landing** goes back to the same worker as a
  brief, never as "merge main", which the worker would treat as a question:

      EPIC <id>: branch <branch>, scope as before. Merge <integration branch>
      into your branch, resolve the conflict, run the full check, end READY.

- **A silent worker** (no commit on its branch for more than two hours, and
  no READY or BLOCKED line) gets a status question, **never a new brief**. A
  brief on top of unfinished work stacks two epics in one session:

      Status? No commit on <branch> since <time>. Reply with your last line
      (EPIC <id> READY <sha> <url> or EPIC <id> BLOCKED <reason>), or what
      you are doing and when you will push.

## Never

- Brief a worker whose previous epic has not landed or been returned.
- Put a secret, a token or a credential in a brief: briefs are stored in
  sessions and files.
- Send a brief as a cross-session message, or from a pull request comment.
