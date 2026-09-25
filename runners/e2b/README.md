# e2b sandboxes

`cr-e2b` starts a worker in an [e2b](https://e2b.dev) sandbox: an isolated
cloud machine, one per worker, created through e2b's SDK.

```sh
export E2B_API_KEY=...        # from your e2b account; never in a file here
export ANTHROPIC_API_KEY=...   # the agent's model key
export GITHUB_TOKEN=...        # optional: private clone, and pushing the branch

cr-e2b start --repo https://github.com/you/project.git --profile backend \
  --brief brief.md --template your-template --timeout 3600
cr-e2b log   --sandbox <id>                    # what the agent printed
cr-e2b brief --sandbox <id> --brief answer.md  # a follow-up, same session
cr-e2b kill  --sandbox <id>
```

`start`:

1. creates a sandbox from `--template` (default: e2b's base template), with
   `CR_PROFILE`, `ANTHROPIC_API_KEY` and, if set, `GITHUB_TOKEN` in its
   environment, living `--timeout` seconds (e2b caps this by plan);
2. if `GITHUB_TOKEN` is set, configures a git credential helper that reads it
   from the environment at each use, so the token is never written to disk;
3. sets the git identity (`--git-name`, `--git-email`, or your local ones);
4. clones the repository on the integration branch into `/home/user/repo`;
5. installs Claude Code (`--install`, default the documented
   `curl -fsSL https://claude.ai/install.sh | bash`);
6. writes the opening message ([`opening.md`](opening.md), filled in), the
   brief and a new session id under `/home/user/.cr/`, and starts the agent
   detached: `claude -p <opening> --session-id <uuid>`, then
   `claude -p <brief> --resume <uuid>`, output appended to
   `/home/user/.cr/log`.

It returns as soon as the agent is started. The worker pushes its branch and
opens its pull request like any other; nothing in the sandbox matters to the
protocol after that. `--agent-args` (default
`--permission-mode acceptEdits`) goes on every turn: a headless session
cannot ask for approval, so pick the mode and allow rules your project needs
(see `runners/local/README.md` § Permissions).

## Keys

No key is in this repository or in any file the runner writes. `E2B_API_KEY`
is read by the SDK from your environment. The model key and `GITHUB_TOKEN` go
into the sandbox's environment at creation, which the agent can read: give it
keys scoped to this use (a fine-grained token for this one repository). The
opening message tells the worker never to print, commit or write them.

## What is verified

- **Against the SDK:** the calls follow the e2b Python SDK 2.51.0 source
  (`Sandbox.create(template, timeout, metadata, envs)`, `Sandbox.connect`,
  `commands.run(cmd, cwd, timeout)`, `files.write`, `files.read`, `kill`,
  `CommandExitException`). `tests/fixtures/e2b-contract.py` checks the
  installed SDK still has each call and parameter; CI installs e2b 2.51.0
  and runs it.
- **Against a fake SDK:** `tests/cr-e2b.bats` runs every command against
  `tests/fixtures/fake-e2b`, which records the calls: the order (clone,
  install, start), the session flags, the brief delivered unchanged, and that
  no key reaches a file or a command line.
- **The live path is unverified here:** no e2b key was available. That the
  base template has `git` and `curl`, that the installer works there, that a
  process started with `nohup … &` outlives the command that started it, and
  that Claude Code authenticates headless from `ANTHROPIC_API_KEY` alone, are
  all still to be seen in a first real run.

Needs Python 3 and `pip install e2b`. Python rather than JavaScript: both
SDKs exist, and the Python one runs as a single file with no build step.
