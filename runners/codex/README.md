# Codex cloud: mapping the protocol

Not yet used in practice. Every statement below is checked against Codex's
documentation as it read on 2026-09-24 (the `developers.openai.com/codex`
pages now redirect to `learn.chatgpt.com/docs`), and each one links its page.
What the documentation does not say is marked **unverified**. Codex cloud
calls a task a *chat*.

## The pieces

| control-room | Codex cloud | Source |
|---|---|---|
| A worker profile | One cloud **environment** per profile: repository, setup script, environment variables | [cloud environments][env] |
| The profile variable | An environment variable of that environment (`CR_PROFILE=backend`): "set for the full duration of the chat (including setup scripts and the agent phase)" | [cloud environments][env] |
| The setup script | The environment's setup script. It runs after "Codex creates a container and checks out your repo", in "a separate Bash session from the agent, so commands like `export` do not persist into the agent phase" | [cloud environments][env] |
| Agent instructions | `AGENTS.md`, read from the repository root down to the working directory; files nearer the working directory come later and take precedence | [AGENTS.md][agents] |
| The opening message and the brief | One chat per epic. Its prompt is the opening message followed by the brief, sent from the web UI or with `codex cloud exec --env <ENV_ID> "<prompt>"` | [cloud][cloud], [CLI commands][cli] |
| A follow-up (a second brief, an answer) | A follow-up message in the chat, from the web UI ("You can open a PR or ask follow-up questions"). No CLI command sends a follow-up into an existing cloud chat: `codex cloud exec` starts a new one | [cloud environments][env], [CLI commands][cli] |
| READY: branch and pull request | When the agent finishes, Codex "shows its answer and a diff"; **the person** opens the pull request from the chat. The worker does not push its own branch, so the coordinator's landing check reads the pull request Codex opens | [cloud environments][env] |
| Secrets for the checks | Environment **secrets** "are only available to setup scripts... removed before the agent phase starts". Anything the checks need at run time must be a plain variable (so not a secret) or must not be needed | [cloud environments][env] |
| Network | Agent internet access "is off by default"; per environment it can be on with a domain allowlist | [internet access][net] |

## What changes in the protocol

- **The branch name is Codex's.** The documentation says nothing about
  choosing the branch or prefix of the pull request Codex opens
  (**unverified** whether it can be set). The brief still names
  `<prefix><epic>-<slug>`; the landing check accepts the pull request by its
  epic id in the title, and the coordinator records the branch it came on.
- **One chat per epic.** A follow-up reaches a running chat only through the
  web UI, so the coordinator cannot deliver a second brief by script. Start a
  new chat per epic with `codex cloud exec`, and put questions and answers in
  the chat by hand.
- **The handoff and the run file** are written by the worker as on every
  runner; they arrive in the pull request's diff.

## The guard, where there is no pre-command hook

Codex's **CLI** has hooks: a `PreToolUse` hook gets the event with
`tool_name` and `tool_input` (for Bash, `tool_input.command`) and can deny
with "exit code `2` and write the blocking reason to `stderr`", which is what
`scripts/guard` reads and does ([hooks][hooks]). Hooks live in
`~/.codex/hooks.json`, `<repo>/.codex/hooks.json` or the matching
`config.toml`, and project hooks load only when the project's `.codex/` layer
is trusted. Wiring the guard there for a local Codex worker is **unverified by
a run** here.

For **Codex cloud**, the documentation mentions no hooks, rules or approval
settings at all (**unverified**; treat them as absent). The guard's rules are
then enforced in two places instead:

1. **`AGENTS.md`.** Add the rules to the repository's `AGENTS.md` so the
   agent reads them in every chat: [`AGENTS-worker.md`](AGENTS-worker.md) is
   the section to paste. It is an instruction, not a barrier.
2. **The landing check** (`docs/protocol.md` § Landing checklist), on the
   coordinator's side, which is the real barrier: a pull request is landed
   only if its head matches the READY line, its files are inside the brief's
   scope, and its target is the integration branch. In Codex cloud the person
   opens the pull request, so a wrong base or a force-pushed branch shows up
   there, not in a hook.

Codex cloud's own shape covers part of the rest: by default the agent phase
has no internet access, so it cannot push, tag, delete a branch or merge
anything; the person does those from the chat. With internet access on and
git credentials in the container, that protection is gone and only
`AGENTS.md` and the landing check remain.

## A local Codex worker (not built)

`runners/local/cr-worker` speaks Claude Code's flags. Codex's CLI has the same
two moves: `codex exec "<prompt>"` for the first turn, and
`codex exec resume <SESSION_ID> "<prompt>"` for a follow-up in the same
session ([non-interactive mode][exec]). Adapting `cr-worker` needs the
session id from the first run's output, which is **unverified** here.

[env]: https://learn.chatgpt.com/docs/environments/cloud-environment
[agents]: https://learn.chatgpt.com/docs/agent-configuration/agents-md
[cloud]: https://learn.chatgpt.com/docs/cloud
[cli]: https://learn.chatgpt.com/docs/developer-commands?surface=cli
[net]: https://learn.chatgpt.com/docs/cloud/internet-access
[hooks]: https://learn.chatgpt.com/docs/hooks
[exec]: https://learn.chatgpt.com/docs/non-interactive-mode
