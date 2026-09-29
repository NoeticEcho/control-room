# local-ci: checks on your own machine, verdicts on GitHub

`ci/local-ci` runs a repository's check on a machine you own and posts the
result on the commit as a **commit status**: a green tick or a red cross in
GitHub's UI, beside the pull request and on the branch. It uses no GitHub
Actions minutes. A commit status is a plain REST call, available on private
repositories with no billing at all.

## Why it exists

The setup this repository was extracted from ran CI on GitHub Actions for a
private repository. One morning GitHub refused to start any job: «recent
account payments have failed or your spending limit needs to be increased».
Every job ended in two seconds with zero steps and no log. That tells you
nothing about the code, and it turned every worker's pull request red.

Two things were already true:
- Every worker runs the full check in its own VM before it says READY (the
  lane, `docs/protocol.md`). That is the pull request's check.
- The coordinator's machine can run the same check after a landing.

What was missing was a way to put the second verdict where people look. That
is local-ci.

## The protocol with local-ci

- **Before a landing:** the worker's lane passed at S. This is unchanged.
- **After a landing:** the coordinator runs `local-ci run <repo> <integration
  branch>`, or lets `local-ci poll` find the new head. It reads the status
  before the next landing. **Red means the landing is reverted and the epic
  returned**, exactly as with hosted CI.
- **Pull requests:** `local-ci poll --prs` checks open pull requests from the
  same repository too, when the machine has room. It takes nothing from a
  fork.
- **Several landings, one check.** When the coordinator lands several ready
  pull requests together (`docs/protocol.md`, "Several ready pull requests,
  one heavy check"), local-ci checks the last merge. That verdict covers
  them all. If it is red, the coordinator finds which merge broke it and
  returns that epic.
- **Deploy and health.** Every landing is deployed to the test environment,
  and its health is checked. Make both part of the configured `check`, for
  example `make check && ./deploy-test && ./health-test`. That way the one
  status local-ci posts on the commit says whether the landing is built,
  deployed and alive. Red means revert and return, as above.

## What the configured check must do

- **Build what the release builds.** Tests that pass prove nothing about a
  file no test reads. A stylesheet, a bundle, an image or a documentation
  site that only the release builds can be broken by a clean-looking merge:
  a closing brace lost while two appended blocks were joined, with every
  test green. So the configured `check` runs the release build too, for
  example `make check && make build`, or whatever the release pipeline
  runs. See `docs/protocol.md`, "Clean merges that are still wrong".
- **Say what the machine lacks, first.** A workstation is not the hosted
  runner: a tool or a library module the runner installs may be missing.
  The suites then fail one test at a time with no reason (dozens of
  `not ok` lines, while hosted CI is green). Start the check with a
  preflight that names each missing piece and how to install it, and
  fails before any suite runs. This repository's own `make check` does
  that with [`scripts/preflight`](../scripts/preflight); run `make
  preflight` alone to see the list.

## Setting it up

1. A checkout that nothing else edits, one per repository. A worktree is
   cheapest, and it keeps its dependency caches and build output between
   runs:

       git -C ~/src/app worktree add --detach ~/.local/state/local-ci/work/app

2. `~/.config/local-ci/config.json`:

       {"context": "local-ci",
        "repos": [{"name": "app", "slug": "owner/app",
                   "workdir": "~/.local/state/local-ci/work/app",
                   "branches": ["main"], "check": "make check",
                   "timeout": 3600}]}

3. `gh auth status`: the account needs write access to the repository.
   Statuses are written with `gh api`.
4. Call it after each landing, or on a timer:

       */10 * * * *  /path/to/control-room/ci/local-ci poll

   One check runs at a time on the machine. A `poll` that finds one running
   exits 0, so a frequent timer is harmless.

To make the status required, add `local-ci` as a required status check in
the branch protection rules. Only do that if the machine is reliably on:
otherwise nothing can merge while it is off.

## What it records

- `<state>/<repo>/results.tsv`: time, sha, verdict, seconds, ref and log
  path, one line per check.
- `<state>/<repo>/<sha>.log`: the check's whole output.
- `local-ci status` prints the last five verdicts per repository.

A status says where the log is (`<repo>/<sha>.log`) and never the machine's
paths, because other people read statuses.

## What it does not do

- **Isolation.** The check runs as you, with your credentials in reach.
  - Watch only branches whose authors you trust.
  - `--prs` skips pull requests from forks. On a public repository even that
    is not enough, so do not use `--prs` there.
- **A clean clone.** The workdir keeps ignored files between runs; that is
  what makes a run fast. A check that must start from nothing should clean
  up itself (`git clean -fdx` first), and pay for it.
- **Parallelism.** One check at a time is deliberate: on a small machine,
  two test suites at once turn green into red.

## Verified

`tests/local-ci.bats` covers:
- success, failure and timeout (`error`);
- a refused dirty workdir;
- ignored files kept between runs;
- the lock, and a stale lock taken over;
- posting turned off, and a post that fails;
- `poll` checking a new head once and never again;
- `--prs` skipping a fork's pull request;
- no local path in any status.

They run against a real git origin and a fake `gh`. It has also been used on
the setup this came from, against GitHub's real statuses API.
