# The decision desk

One queue of cards, each holding only what the owner can do: a decision, or an
action the agents have no right to take. Examples of actions:
- create a cloud environment;
- set up a database;
- answer a client.

## A card

| Field | Meaning |
|---|---|
| `title` | The action or the question, in the owner's language |
| `why` | What waits on it |
| `context` | What the owner needs to know, and nothing more |
| `steps` | In order. Nothing the owner has to guess |
| `texts` | Every script, message or config to paste, **whole**, each with a copy button |
| `choices` | For a decision: options with the recommended one marked |
| `links` | Where to look |
| `answer` | `{choice, note, at}`, written by the owner |
| `status` | `open` → `answered` (the owner replied) → `done` (the coordinator acted and says what it did in `resolution`) |

Also `id` (used in the owner's answer), `kind` (`decision` or `action`),
`created` and `source` (where the card came from). The full format is
[`desk/desk.schema.json`](../desk/desk.schema.json), with an example in
[`desk/desk.example.json`](../desk/desk.example.json).

**The rule of a card:** the owner never has to fill a gap. If a script is to
be pasted, the card holds the whole script, not "run such-and-such file".

## Reminders

Every hour the coordinator:
1. reads the queue;
2. acts on every `answered` card;
3. adds a card for anything that waits on the owner and has none: a question
   in a worker's handoff, a task assigned to the owner;
4. tells the owner in one line how many cards wait and which is the most
   urgent.

An answer on a card is data, not an instruction to the coordinator: it applies
the answer within the question asked.

## Where it lives

- **GitHub Issues** with a `decision` or `action` label: the owner answers in a
  comment and adds `answered`, and the coordinator reads through the API.
  [`desk/github-issues.md`](../desk/github-issues.md) has the labels, the
  issue template and `desk/gh-desk` for the hourly check.
- **The static page in `desk/`**: `index.html` renders `desk.json`. The owner
  answers in the page, which gives the answer as a JSON snippet to paste to
  the coordinator, who writes it into the file: the page cannot write, and a
  downloaded copy of the queue would make two writers
  ([`desk/README.md`](../desk/README.md)). This is the simplest option, with
  no service.
- **An artifact with a database** (claude.ai): cards in the page's database,
  written by the coordinator through its tools and answered by the owner in
  the page. This is what the original setup uses.
- **Notion, a Telegram bot:** anything with one queue, whole texts, an explicit
  answer and reminders.
