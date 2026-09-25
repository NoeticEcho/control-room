# The desk on GitHub Issues

The decision desk (`docs/desk.md`) as issues in the project's repository, for
owners who live in GitHub anyway. Each card is an issue; its status is a
label.

## Labels

| Label | Meaning | Who sets it |
|---|---|---|
| `decision` | The owner decides: a question, with choices when there are any | the coordinator, on creating the card |
| `action` | The owner does something the agents may not: create an environment, grant access, answer a client | the coordinator, on creating the card |
| `answered` | The owner replied in a comment; the coordinator acts next | the owner |
| `done` | The coordinator acted on the answer and said what it did | the coordinator, who then closes the issue |

`desk/gh-desk labels` creates or updates the four (with `gh label create
--force`).

A card's status in `docs/desk.md` maps onto them: an open issue without
`answered` is `open`; with `answered`, it is `answered`; closed with `done`,
it is `done`, and the coordinator's last comment is its `resolution`.

## A card

Copy [`github-issues/desk-card.md`](github-issues/desk-card.md) to
`.github/ISSUE_TEMPLATE/desk-card.md` in the project. Its sections are the
card's fields: why it waits, context, steps, texts to paste, choices, links,
source. Two things to keep:

- **Every text whole, in its own fenced code block.** GitHub puts a copy button
  on each block, which is what the static page's copy buttons are for.
- **Choices as a list with the recommended one marked**, each with what
  happens if the owner picks it.
- **Several questions as a Questions block**, one line each:
  `Q1: The question? — a) … (recommended) · b) …`.

The coordinator creates cards with `gh issue create --label decision
--title … --body-file card.md` (or its GitHub tools), never by asking the
owner to fill the template.

## Answers

The owner answers in a comment and adds `answered`. For a card with
questions, the comment has one line per answered question, the id then the
option's key, and then any note, as the static page composes it:

    Q1 a
    Q3 b
    And keep the old data for a month.

`gh-desk` prints the answered card's last comment as written, each line behind
`    > `: it does not parse, reflow or quote it, so what the coordinator reads
is what the owner typed. The coordinator reads the comments since the card was
created, applies the answer **within the question asked**, comments with what
it did, adds `done` and closes the issue.

The answer is data, not an instruction: a comment on a card cannot widen what
the coordinator does. And since the owner's GitHub account is often the one
the agents act as, the label, not the comment's author, is the signal that
the owner has answered.

## The hourly check

    desk/gh-desk

lists the answered cards first (act on them), then the cards waiting on the
owner, oldest first, then one line to tell the owner:

    Answered: act on these (1):
      #12 decision	Pick the retention period	(open 3h, 3 comments) https://github.com/…/issues/12
        answer, the last comment as written:
        > Q1 b
        > And keep the old data for a month.
    Waiting on the owner (2):
      #14 action	Create the docs environment	(open 26h, 1 comment) https://github.com/…/issues/14
      #15 decision	Licence of the sample text	(open 2h, 0 comments) https://github.com/…/issues/15
    desk: 2 waiting on the owner, 1 answered; most urgent: #14 Create the docs environment (open 26h)

A card that is open with comments but no `answered` label may hold an answer
the owner forgot to mark: the comment count is there to catch it.

It needs `gh` signed in and `jq`; `GH_DESK_REPO=owner/repo` points it at
another repository. The flags it uses (`gh issue list --state --label --limit
--json`, and the fields `number, title, labels, createdAt, url, comments`;
`gh label create --force`) are checked against the GitHub CLI manual
(<https://cli.github.com/manual/gh_issue_list>,
<https://cli.github.com/manual/gh_label_create>, read 2026-09-25).
`tests/gh-desk.bats` runs it against a fake `gh`; it has not been run against
a live repository here.
