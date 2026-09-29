# The Claude plugin

control-room is also a plugin for Claude: `noetic-control-room`, in
[`plugin/`](../plugin/). Whoever installs it gets that folder only, not the
repository: four skills that make Claude the coordinator, two small shell
scripts, and the texts the skills fill in.

## What is in it

| Skill | What Claude does with it | Written from |
|---|---|---|
| `brief-worker` | Writes a brief in the fixed shape and sends it as a user message in the worker's session; the status question for a silent worker; the brief that returns a logic conflict | [The protocol](protocol.md) (one epic's life, the lines, model and effort), [`prompts/en/brief.md`](../prompts/en/brief.md) |
| `land-ready` | Checks a READY pull request and lands it by the landing checklist, including several at once and the clean merges that are still wrong | [The protocol](protocol.md) (landing checklist) |
| `run-desk` | Keeps the decision desk as GitHub issues and does the hourly check | [The decision desk](desk.md), [`desk/github-issues.md`](../desk/github-issues.md) |
| `start-cloud-worker` | Writes the cloud environment's setup, the worker section of `CLAUDE.md` and the opening message for a Claude Code cloud worker | [Claude Code cloud](../runners/claude-code-cloud/README.md), [`prompts/en/worker-opening.md`](../prompts/en/worker-opening.md) |

The scripts, run by the skills as `sh ${CLAUDE_PLUGIN_ROOT}/scripts/<name>`:

- `ready-check`: the mechanical half of the landing checklist. For a READY
  sha and a branch it says whether the sha is already landed, whether the
  branch moved past it (and whether only by merging the integration
  branch), which files are outside the brief's scope or fenced, whether it
  merges cleanly, and how many landings behind it is. It reads git and
  changes nothing. Tests: `tests/ready-check.bats`.
- `gh-desk`: the same file as [`desk/gh-desk`](../desk/gh-desk).

`scripts/cloud-setup.sh` is the same file as
[`runners/claude-code-cloud/setup.sh`](../runners/claude-code-cloud/setup.sh),
for the person to paste into a cloud environment.

What this version leaves out, on purpose: hooks (so no worker guard; install
[`scripts/guard`](../scripts/README.md) from the repository on the workers'
side), MCP servers, commands and agents. Everything a skill does it does
through `git`, `gh` and, to send a brief to a cloud session, `claude -p
--cloud`. The plugin's [README](../plugin/README.md) lists each command and
where it sends data.

## Install it

In Claude Code, from a clone of this repository, for a session:

    claude --plugin-dir ./plugin

Once it is listed in Anthropic's plugin directory, add it from
**Customize > Plugins** on claude.ai, or in Claude Code with `/plugin`.

## Keep it right

- **Copies stay copies.** `tests/plugin.bats` fails when a text the plugin
  carries (`gh-desk`, the setup script, the brief template, the worker's
  opening message, the licence) differs from its original. Change the
  original, then copy it.
- **The version** in `plugin/.claude-plugin/plugin.json` starts at the
  repository's release (0.2.1) and is raised with every release; the tests
  fail when it is behind the latest `v*` tag.
- **The directory's checks** that can be checked here are in
  `tests/plugin.bats`: the manifest, no hooks or servers, regular files
  under the size and count limits, portable names, a README of 40 words or
  more, spec-only skill frontmatter, no launchers and no credentials.
- **`claude plugin validate ./plugin --strict`** runs in CI (the `plugin`
  job in `.github/workflows/check.yml`) with a pinned Claude Code.
- **Evals** (`claude plugin eval`) compare Claude with and without the
  plugin on real prompts. The cases are in `tests/plugin-evals/`, outside
  the plugin so that nobody who installs it downloads them; run them with
  `tests/plugin-evals/run`, which copies the plugin and the cases into a
  scratch directory. They call the model on your account, so CI does not
  run them.

## Submitting it to the directory

The person submits it from the developer portal
(<https://claude.ai/directory/manage>, **Submit new**, **Plugin bundle**):
repository `NoeticEcho/control-room`, plugin path `plugin`, tracked branch
`main`. The portal's **Validate** runs checks that `claude plugin validate`
does not (whether the name is taken, among them); fix every finding it marks
**Blocking** and validate again. The steps and the checks are Anthropic's:
<https://claude.com/docs/plugins/submit> and
<https://claude.com/docs/plugins/pre-submission-checklist> (read
2026-09-30).
