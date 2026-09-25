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
