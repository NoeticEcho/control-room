// Tests for desk/index.html: the page's own script, run in a bare JavaScript
// context (no browser, no dependencies), renders into a minimal DOM
// (tests/fixtures/desk/mini-dom.mjs) whose innerHTML throws.
// Run with: node --test tests/desk.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import vm from "node:vm";
import { doc, serialize, all, attr, tag, cls } from "./fixtures/desk/mini-dom.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = read("../desk/index.html");
const example = JSON.parse(read("../desk/desk.example.json"));
const schema = JSON.parse(read("../desk/desk.schema.json"));
const cardFields = Object.keys(schema.definitions.card.properties);
const cardsDir = new URL("./fixtures/desk/cards/", import.meta.url);
const fixtures = Object.fromEntries(readdirSync(cardsDir).filter((f) => f.endsWith(".json"))
  .map((f) => [f.replace(/\.json$/, ""), JSON.parse(readFileSync(new URL(f, cardsDir), "utf8"))]));

function loadDesk() {
  const scripts = [...page.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  assert.equal(scripts.length, 1, "one inline script");
  const context = vm.createContext({});
  vm.runInContext(scripts[0], context);
  assert.ok(context.ControlRoomDesk, "the script exposes ControlRoomDesk");
  return context.ControlRoomDesk;
}

const desk = loadDesk();
// Values made inside the vm context have that context's prototypes; compare
// them as plain JSON.
const plain = (value) => JSON.parse(JSON.stringify(value));
const render = (data) => desk.renderDesk(data, doc);
const cardNode = (node, id) => all(node, (e) => e.getAttribute("data-card") === id && e.localName === "article")[0];
const card = (extra) => ({ id: "c", kind: "decision", title: "T", why: "W", status: "open", ...extra });

// ---- the page ----------------------------------------------------------------

test("the page is one file, with no external script, stylesheet or framework, and no HTML sinks", () => {
  assert.doesNotMatch(page, /<script[^>]+src=/i);
  assert.doesNotMatch(page, /<link[^>]+stylesheet/i);
  assert.doesNotMatch(page, /innerHTML|outerHTML|insertAdjacentHTML|document\.write/);
  assert.match(page, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
});

test("the page has light and dark themes", () => {
  assert.match(page, /@media \(prefers-color-scheme: dark\)/);
  assert.match(page, /:root\[data-theme="dark"\]/);
  assert.match(page, /:root:not\(\[data-theme="light"\]\)/);
});

// ---- the example -------------------------------------------------------------

test("the example renders without errors, problems or malformed cards", () => {
  const result = render(example);
  assert.equal(result.count, 4);
  assert.equal(result.malformed, 0);
  assert.deepEqual(plain(result.problems), []);
  assert.deepEqual(plain(result.counts), { open: 2, answered: 1, done: 1 });
});

test("the page knows exactly the card fields of the schema, and the example uses them all", () => {
  assert.deepEqual(plain(desk.CARD_FIELDS), cardFields);
  const used = new Set(example.cards.flatMap((c) => Object.keys(c)));
  assert.deepEqual(cardFields.filter((f) => !used.has(f)), []);
});

test("every card field in the schema appears in the rendered page", () => {
  const { node } = render(example);
  for (const f of cardFields) {
    assert.ok(all(node, attr("data-field", f)).length > 0, `field ${f} is rendered`);
  }
});

test("every value of every card appears in its card", () => {
  const { node } = render(example);
  for (const c of example.cards) {
    const text = cardNode(node, c.id).textContent;
    const values = [c.title, c.why, c.resolution, c.source, c.id, c.kind, c.answer?.note,
      ...desk.paragraphs(c.context ?? []), ...(c.steps ?? []),
      ...(c.texts ?? []).flatMap((t) => [t.label, t.text]),
      ...(c.choices ?? []).flatMap((x) => [x.label, x.consequence]),
      ...(c.questions ?? []).flatMap((q) => [q.id, q.text, ...q.options.flatMap((o) => [o.key, o.label])]),
      ...(c.links ?? []).map((l) => l.label)];
    for (const v of values.filter(Boolean)) assert.ok(text.includes(v), `${c.id}: "${v.slice(0, 50)}"`);
    for (const l of c.links ?? []) {
      assert.ok(all(cardNode(node, c.id), (e) => e.getAttribute("href") === l.url).length === 1, `${c.id} link ${l.url}`);
    }
  }
});

test("every text has its own copy button, and is whole", () => {
  const { node } = render(example);
  const texts = example.cards.flatMap((c) => c.texts ?? []);
  assert.equal(all(node, attr("data-action", "copy")).length, texts.length);
  for (const t of texts) assert.ok(all(node, tag("pre")).some((p) => p.textContent === t.text), `"${t.label}" is whole`);
});

test("only open cards can be answered, and each has the live preview", () => {
  const { node } = render(example);
  const forms = all(node, attr("data-field", "answer-form"));
  assert.equal(forms.length, 2);
  for (const f of forms) assert.match(f.textContent, /This goes to the coordinator:/);
});

// ---- 1. a card that does not fit is shown, never dropped ----------------------

test("malformed: a card that does not fit is shown as malformed, with the field and its raw JSON", () => {
  const bad = fixtures["malformed-choices-strings"];
  const result = render({ cards: [fixtures["valid-minimal"], bad] });
  assert.equal(result.malformed, 1);
  const block = all(result.node, attr("data-malformed"))[0];
  assert.ok(block, "a malformed block is rendered");
  assert.match(block.textContent, /This card is malformed: choices\[0\] must be an object/);
  const raw = all(block, tag("pre"))[0].textContent;
  assert.deepEqual(JSON.parse(raw), bad);
  assert.equal(all(result.node, (e) => e.localName === "article" && !e.hasAttribute("data-malformed")).length, 1,
    "the valid card is still rendered");
  const sections = all(result.node, tag("section")).map((s) => s.getAttribute("data-status"));
  assert.equal(sections[0], "malformed", "malformed cards come first");
});

test("malformed: a field the page does not know is named, not ignored", () => {
  const result = render({ cards: [fixtures["malformed-options-field"]] });
  assert.match(all(result.node, attr("data-malformed"))[0].textContent, /This card is malformed: options is not a field the schema knows/);
  assert.equal(all(result.node, attr("data-field", "choices")).length, 0, "nothing is half-rendered");
});

test("malformed: even a card that is not an object is shown", () => {
  const result = render({ cards: ["just a string", 7, null] });
  assert.equal(result.malformed, 3);
  assert.match(result.node.textContent, /"just a string"/);
});

test("malformed: the page's check agrees with desk.schema.json on every fixture card", () => {
  const verdicts = JSON.parse(execFileSync("python3", ["-c", `
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
v = jsonschema.Draft7Validator(schema)
print(json.dumps({name: v.is_valid({"cards": [card]}) for name, card in json.loads(sys.stdin.read()).items()}))
`, new URL("../desk/desk.schema.json", import.meta.url).pathname], { input: JSON.stringify(fixtures) }).toString());
  assert.ok(Object.keys(fixtures).length >= 20);
  for (const [name, c] of Object.entries(fixtures)) {
    const page = plain(desk.checkCard(c));
    assert.equal(page.length === 0, verdicts[name], `${name}: page says ${JSON.stringify(page)}, jsonschema says ${verdicts[name]}`);
    assert.equal(verdicts[name], name.startsWith("valid-"), `${name}: its name says what it is`);
  }
});

// ---- 2. structured questions ---------------------------------------------------

test("questions: each renders as pills, with the key in monospace and the recommended one marked, not preselected", () => {
  const { node } = render(example);
  const q = all(node, attr("data-question", "Q2")).find((e) => e.localName === "fieldset");
  const pills = all(q, cls("pill"));
  assert.equal(pills.length, 2);
  assert.deepEqual(pills.map((p) => all(p, cls("key"))[0].textContent), ["a", "b"]);
  assert.ok(all(pills[0], cls("mono")).length === 1);
  assert.ok(cls("recommended")(pills[0]) && !cls("recommended")(pills[1]));
  assert.equal(all(q, (e) => e.localName === "input" && e.hasAttribute("checked")).length, 0);
});

test("questions: the note is one line per answered question, then the free text", () => {
  const questions = example.cards.find((c) => c.id === "release-0-2").questions;
  assert.equal(desk.composeNote(questions, { Q1: "a", Q3: "b" }, "  Ship it this week.  "), "Q1 a\nQ3 b\nShip it this week.");
  assert.equal(desk.composeNote(questions, { Q3: "a", Q1: "b" }, ""), "Q1 b\nQ3 a", "in the questions' order");
  assert.equal(desk.composeNote(questions, {}, "Only a note."), "Only a note.");
  assert.equal(desk.composeNote(undefined, {}, ""), "");
});

test("questions: the draft answer carries the choice and the composed note, and so does the snippet", () => {
  const c = card({ choices: [{ id: "x", label: "X" }], questions: [{ id: "Q1", text: "?", options: [{ key: "a", label: "A" }] }] });
  const draft = plain(desk.draftAnswer(c, { Q1: "a" }, "x", "and more"));
  assert.deepEqual(draft, { choice: "x", note: "Q1 a\nand more" });
  const s = plain(desk.answerSnippet("c", draft.choice, draft.note, "2026-09-25T10:00:00.000Z"));
  assert.deepEqual(s, { card: "c", status: "answered", answer: { choice: "x", note: "Q1 a\nand more", at: "2026-09-25T10:00:00.000Z" } });
  const allowed = Object.keys(schema.definitions.card.properties.answer.properties);
  for (const k of Object.keys(s.answer)) assert.ok(allowed.includes(k), `answer.${k} is in the schema`);
});

test("choices: the recommended choice is marked, and preselected on an open card", () => {
  const { node } = render({ cards: [card({ choices: [{ id: "a", label: "A" }, { id: "b", label: "B", recommended: true }] })] });
  const inputs = all(node, tag("input"));
  assert.deepEqual(inputs.map((i) => [i.getAttribute("value"), i.hasAttribute("checked")]), [["a", false], ["b", true]]);
  assert.equal(all(node, cls("rec")).length, 1);
});

// ---- 3. quoting a point into the answer ------------------------------------------

test("quote: a paragraph that starts with an id gives '<ID>: '", () => {
  assert.equal(desk.quoteLine("Q3 costs one run."), "Q3: ");
  assert.equal(desk.quoteLine("H1: the first hypothesis"), "H1: ");
  assert.equal(desk.quoteLine("ABC-12 is the ticket."), "ABC-12: ");
  assert.equal(desk.quoteLine("wc-3.1 (count words) has landed."), "wc-3.1: ");
});

test("quote: any other paragraph gives a quote of up to 80 characters and ' — '", () => {
  assert.equal(desk.quoteLine("Today it splits on spaces."), "“Today it splits on spaces.” — ");
  assert.equal(desk.quoteLine("e2b is a sandbox service."), "“e2b is a sandbox service.” — ", "e2b is not an id");
  const long = "A package registry means one more account for you to hold, and one more place to publish on every release.";
  const line = desk.quoteLine(long);
  const quote = line.slice(1, line.indexOf("”"));
  assert.equal(Array.from(quote).length, 80);
  assert.ok(quote.endsWith("…") && long.startsWith(quote.slice(0, -1)));
  assert.ok(line.endsWith("” — "));
});

test("quote: context is split into paragraphs on blank lines, or taken as a list; open cards get a quote button each", () => {
  assert.deepEqual(plain(desk.paragraphs("One.\n\nTwo\nstill two.\n \nThree.")), ["One.", "Two\nstill two.", "Three."]);
  assert.deepEqual(plain(desk.paragraphs(["a", "b"])), ["a", "b"]);
  const { node } = render(example);
  const release = cardNode(node, "release-0-2");
  assert.equal(all(release, attr("data-action", "quote")).length, 3);
  const done = cardNode(node, "licence-sample");
  assert.equal(all(done, attr("data-action", "quote")).length, 0, "no quote buttons without an answer form");
});

// ---- 4. the glossary --------------------------------------------------------------

const glossaryDesk = (text, extra = {}) => ({
  glossary: [
    { term: "CR", summary: "The prefix." },
    { term: "CR-2", summary: "The runners epic." },
    { term: "e2b", summary: "Sandboxes.", aliases: ["E2B"] },
    { term: "wc-3", summary: "Count words." },
  ],
  idPattern: "wc-\\d+(?:\\.\\d+)*",
  ...extra,
  cards: [card({ why: text })],
});

function terms(text, extra) {
  const data = glossaryDesk(text, extra);
  const { node, glossary } = render(data);
  const why = all(node, attr("data-field", "why"))[0];
  return all(why, cls("term")).map((b) => [b.textContent, glossary.entries[Number(b.getAttribute("data-term"))].term]);
}

test("glossary: the longest match wins", () => {
  assert.deepEqual(terms("CR-2 was merged, CR is the prefix."), [["CR-2", "CR-2"], ["CR", "CR"]]);
});

test("glossary: no match inside a word", () => {
  assert.deepEqual(terms("SCR, CRx, CR2, X-CR, e2bx and ae2b are not terms."), []);
});

test("glossary: a term may be followed by a dash, as the brief's boundary allows: CR in CR-20", () => {
  // (?![\p{L}\p{N}_]) after a term lets "-" follow it; CR-2 does not match CR-20.
  assert.deepEqual(terms("CR-20 is not CR-2."), [["CR", "CR"], ["CR-2", "CR-2"]]);
});

test("glossary: an alias resolves to its term", () => {
  assert.deepEqual(terms("Run it on E2B."), [["E2B", "e2b"]]);
});

test("glossary: the id pattern resolves an id to its entry, or its parent's", () => {
  assert.deepEqual(terms("wc-3.2 waits; wc-3 landed; wc-9 is unknown."), [["wc-3.2", "wc-3"], ["wc-3", "wc-3"]]);
});

test("glossary: terms are wrapped in title, why, context, steps, choices and questions, as focusable buttons", () => {
  const data = {
    glossary: [{ term: "e2b", summary: "Sandboxes." }],
    cards: [card({ title: "e2b", why: "e2b", context: "e2b", steps: ["e2b"],
      choices: [{ id: "a", label: "e2b", consequence: "e2b" }],
      questions: [{ id: "Q1", text: "e2b?", options: [{ key: "a", label: "e2b" }] }] })],
  };
  const { node } = render(data);
  for (const f of ["title", "why", "context", "steps", "choices", "questions"]) {
    const buttons = all(all(node, attr("data-field", f))[0], cls("term"));
    assert.ok(buttons.length >= 1, `${f} has a term`);
    for (const b of buttons) assert.equal(b.localName, "button");
    for (const b of buttons) assert.equal(b.getAttribute("type"), "button");
  }
  const q = all(node, attr("data-question", "Q1")).find((e) => e.localName === "fieldset");
  assert.equal(all(all(q, tag("legend"))[0], cls("term")).length, 1, "in the question's text");
  assert.equal(all(all(q, cls("pill"))[0], cls("term")).length, 1, "in an option's label");
  const c = all(node, attr("data-field", "choices"))[0];
  assert.equal(all(c, cls("term")).length, 2, "in a choice's label and its consequence");
});

test("glossary: a <script> in a summary or a term stays text", () => {
  const evil = "<script>alert(1)</script><img src=x onerror=alert(2)>";
  const data = { glossary: [{ term: "e2b", summary: evil }], cards: [card({ why: "on e2b" })] };
  const { node, glossary } = render(data);
  assert.equal(all(node, (e) => ["script", "img"].includes(e.localName)).length, 0);
  assert.ok(!node.textContent.includes("alert"), "the summary is not in the card at all");
  const tip = doc.createElement("div");
  for (const n of desk.tipContent(doc, glossary.entries[0])) tip.appendChild(n);
  assert.equal(all(tip, (e) => ["script", "img"].includes(e.localName)).length, 0);
  assert.equal(all(tip, tag("strong"))[0].textContent, "e2b");
  assert.ok(tip.textContent.endsWith(evil), "the summary is there, as text");
  assert.match(serialize(tip), /&lt;script&gt;/);
});

test("glossary: a broken id pattern or glossary entry is reported, not thrown", () => {
  const result = render({ glossary: [{ term: "x" }], idPattern: "(", cards: [card()] });
  assert.equal(result.problems.length, 2);
  assert.match(result.problems.join(" "), /glossary\[0\]/);
  assert.match(result.problems.join(" "), /idPattern is not a usable regular expression/);
  assert.match(render({ idPattern: "a*", cards: [card()] }).problems.join(" "), /matches the empty string/);
});

// ---- the rest ---------------------------------------------------------------------

test("card text cannot inject markup, and only web and mail links are followed", () => {
  const { node } = render({ cards: [card({ title: '<img src=x onerror="alert(1)">', why: "<script>alert(1)</script>",
    links: [{ label: "ok", url: "https://example.invalid/" }] })] });
  assert.equal(all(node, (e) => ["img", "script"].includes(e.localName)).length, 0);
  assert.match(serialize(node), /&lt;img src=x/);
  assert.equal(desk.safeUrl("javascript:alert(1)"), null);
  assert.equal(desk.safeUrl("https://example.invalid/"), "https://example.invalid/");
  const bad = render({ cards: [fixtures["malformed-link-javascript"]] });
  assert.equal(all(bad.node, (e) => e.hasAttribute("href")).length, 0, "a javascript: link makes the card malformed, never a link");
});

test("a desk that is not a desk is refused", () => {
  assert.throws(() => render({}), /cards/);
  assert.throws(() => render(null), /cards/);
  assert.throws(() => render([]), /cards/);
});
