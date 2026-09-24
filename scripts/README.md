# scripts

Two scripts that work in any repository, whatever its language.

| Script | What | Needs |
|---|---|---|
| `guard` | The worker guard: a hook that runs before each of a worker's commands and refuses what `docs/protocol.md` § The guard forbids | POSIX sh, git, jq |
| `validate-handoff` | Checks `handoff/<epic>.json` against `schemas/handoff.schema.json`, and what a schema cannot state | Python 3, jsonschema |

Both read `control-room.json` at the repository root, if there is one:

```json
{"integration_branch": "main", "branch_prefix": "claude/"}
```

Both keys are optional; those are the defaults. The file may hold other keys
(the project's profiles, for example); the scripts ignore them.

## guard

### What it refuses

| Rule | Examples it denies |
|---|---|
| A push to anything but the current branch | `git push origin claude/other`, `git push origin HEAD:main`, `git -C ../x push origin main` |
| A push to the integration branch, or to a branch outside the prefix | `git push origin main` even while on `main` |
| A push with no explicit refspec | `git push`, `git push -u origin` |
| Force pushes | `--force`, `-f`, `--force-with-lease`, `--force-if-includes`, `+branch` |
| Tags | `git push --tags`, `--follow-tags`, `refs/tags/...`, `git tag v1`, `gh release create` |
| Branch deletions | `git push origin :branch`, `--delete`, `-d`, `--prune`, `git branch -d/-D` |
| Merging a pull request | `gh pr merge`, `gh api .../pulls/N/merge`, MCP `merge_pull_request`, `enable_pr_auto_merge` |
| A pull request against another base | MCP `create_pull_request` or `update_pull_request` with `base` other than the integration branch, `gh pr create --base other` |
| MCP writes to another branch | `push_files`, `create_or_update_file`, `delete_file` with `branch` other than the current one; `delete_branch` |

It reads chains (`&&`, `||`, `;`, `|`, subshells, `$(...)` and backquotes),
`sh -c '...'`, `bash -lc '...'` and `eval`, and follows a `cd <dir>`,
`git -C <dir>` or `git switch -c <branch>` / `git checkout -b <branch>`
earlier in the same command. Everything else passes through, including
commands that only mention a forbidden one (`echo "git push origin main"`).

A denial is one line on stderr, exit status 2:

```text
guard: denied: a push to the integration branch main. Instead: push your own branch by name (git push origin claude/cr-1-x); the coordinator lands it
```

and the same reason on stdout as a PreToolUse `permissionDecision` of `deny`.

### Wiring it into Claude Code

Copy `scripts/guard` into the project (here, `scripts/guard`) and add this to
the project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/guard"
          }
        ]
      }
    ]
  }
}
```

What this relies on, checked against the Claude Code hooks reference
(<https://code.claude.com/docs/en/hooks>, read 2026-09-24):

- a PreToolUse hook gets the event as JSON on stdin, with `tool_name`,
  `tool_input` (for Bash, `tool_input.command`) and `cwd`;
- MCP tools are named `mcp__<server>__<tool>`, and `matcher` is a regular
  expression over the tool name;
- exit status 2 blocks the tool call, and the blocking message is the JSON
  decision's reason when there is one and stderr otherwise;
- `$CLAUDE_PROJECT_DIR` is the project root.

Not verified by a run in a live session yet: that is CR-2's pilot.

### Where a runner has no pre-command hook

Use the same script as a git `pre-push` hook. It then sees only pushes (not
`gh pr merge` or MCP tools), but it sees every push, however it was typed:

```sh
mkdir -p .githooks
printf '#!/bin/sh\nexec "$(git rev-parse --show-toplevel)/scripts/guard" --git-pre-push "$@"\n' >.githooks/pre-push
chmod +x .githooks/pre-push
git config core.hooksPath .githooks
```

In this mode it refuses a push to anything but the current worker branch, a
tag, a deletion, and a push that is not a fast-forward of the remote branch.

### What it does not do

It is a guard against confusion, not a permission system: the session holds
the owner's credentials, and a worker set on getting around it can. It reads
commands the way a careful person would, not the way a shell does, so it does
not see through:

- git aliases (`git -c alias.p=push p ...`, or a `[alias]` in the config);
- variables and functions (`$GIT push`, `f() { git push "$@"; }; f`);
- a command substitution inside double quotes (`echo "$(git push origin main)"`);
- scripts it runs (`./deploy.sh` that pushes);
- raw API calls other than the merge endpoint (`curl`, `gh api` to `git/refs`).

The pre-push fallback closes the first four for pushes, unless the push says
`--no-verify`, which skips git's hooks. A worker the guard
stops records the question in its handoff and ends `BLOCKED`; it does not
route around it.

## validate-handoff

```sh
scripts/validate-handoff handoff/proj-12.json
scripts/validate-handoff --config control-room.json --schema schemas/handoff.schema.json handoff/*.json
```

Beyond the schema it checks:

- the file is named for its `epic`;
- `branch` starts with the configured prefix;
- a `ready` handoff has a `lane` whose verdict is `passed`, and no child is
  `open`;
- a `deferred` child has a non-blank `note`, and a `reparented` child a `to`;
- every sha (`base`, `lane.head`, `children[].commits`) is 40 lowercase hex
  characters.

It prints one line per problem, `FILE: $.json.path: message`, and exits 1 if
there was any, 0 if every file is valid, and 2 on a usage error or when
`jsonschema` is missing.

**Why Python and jsonschema, not sh and jq.** The schema is the contract, so a
real JSON Schema implementation checks it. Rewriting in jq the keywords the
schema happens to use today would be a second, partial implementation that
drifts from the schema without anyone noticing. The cost is Python 3 and one
package (`pip install jsonschema`, or `python3-jsonschema` on Debian and
Ubuntu).

## Checks

`make check` runs shellcheck on the guard and the tests, both bats suites,
and the guard's suite again under bash. `.github/workflows/check.yml` runs it
on every pull request and on `main`.
