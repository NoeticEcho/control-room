// Tests for desk/index.html: the page's own script, run in a bare JavaScript
// context (no browser, no dependencies), renders desk/desk.example.json.
// Run with: node --test tests/desk.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const page = read("../desk/index.html");
const example = JSON.parse(read("../desk/desk.example.json"));
const schema = JSON.parse(read("../desk/desk.schema.json"));
const cardFields = Object.keys(schema.definitions.card.properties);

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
const esc = desk.esc;

test("the page is one file: no external script, stylesheet or framework", () => {
  assert.doesNotMatch(page, /<script[^>]+src=/i);
  assert.doesNotMatch(page, /<link[^>]+stylesheet/i);
  assert.match(page, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
});

test("the page has light and dark themes", () => {
  assert.match(page, /@media \(prefers-color-scheme: dark\)/);
  assert.match(page, /:root\[data-theme="dark"\]/);
  assert.match(page, /:root:not\(\[data-theme="light"\]\)/);
});

test("the example renders without errors or problems", () => {
  const result = desk.renderDesk(example);
  assert.equal(result.count, 3);
  assert.deepEqual(plain(result.problems), []);
  assert.deepEqual(plain(result.counts), { open: 1, answered: 1, done: 1 });
});

test("the example uses every card field in the schema", () => {
  const used = new Set(example.cards.flatMap((c) => Object.keys(c)));
  assert.deepEqual(cardFields.filter((f) => !used.has(f)), []);
});

test("every card field in the schema appears in the rendered page", () => {
  const { html } = desk.renderDesk(example);
  for (const f of cardFields) {
    assert.ok(html.includes(`data-field="${f}"`), `field ${f} is rendered`);
  }
});

test("every value of every card appears, escaped", () => {
  const { html } = desk.renderDesk(example);
  for (const card of example.cards) {
    for (const s of [card.title, card.why, card.context, card.resolution, card.source, card.id, card.kind]) {
      if (s) assert.ok(html.includes(esc(s)), `${card.id}: "${s.slice(0, 40)}"`);
    }
    for (const s of card.steps || []) assert.ok(html.includes(esc(s)), `${card.id} step`);
    for (const t of card.texts || []) {
      assert.ok(html.includes(esc(t.label)), `${card.id} text label`);
      assert.ok(html.includes(esc(t.text)), `${card.id} text "${t.label}" is whole`);
    }
    for (const c of card.choices || []) {
      assert.ok(html.includes(esc(c.label)), `${card.id} choice`);
      if (c.consequence) assert.ok(html.includes(esc(c.consequence)), `${card.id} consequence`);
    }
    for (const l of card.links || []) {
      assert.ok(html.includes(`href="${esc(l.url)}"`), `${card.id} link url`);
      assert.ok(html.includes(esc(l.label)), `${card.id} link label`);
    }
    if (card.answer?.note) assert.ok(html.includes(esc(card.answer.note)), `${card.id} answer note`);
  }
});

test("every text has its own copy button", () => {
  const { html } = desk.renderDesk(example);
  const texts = example.cards.reduce((n, c) => n + (c.texts || []).length, 0);
  assert.equal((html.match(/data-action="copy"/g) || []).length, texts);
});

test("the recommended choice is marked, and preselected on an open card", () => {
  const card = { id: "d", kind: "decision", title: "t", why: "w", status: "open",
    choices: [{ id: "a", label: "A" }, { id: "b", label: "B", recommended: true }] };
  const html = desk.renderCard(card, 0);
  assert.match(html, /value="b" checked/);
  assert.doesNotMatch(html, /value="a" checked/);
  assert.equal((html.match(/>recommended</g) || []).length, 1);
});

test("only open cards can be answered", () => {
  const { html } = desk.renderDesk(example);
  assert.equal((html.match(/data-field="answer-form"/g) || []).length, 1);
  assert.match(html, /data-action="answer" data-card="env-docs"/);
});

test("card text cannot inject markup, and only web and mail links are followed", () => {
  const html = desk.renderCard({
    id: "x", kind: "action", title: '<img src=x onerror="alert(1)">', why: "<script>alert(1)</script>", status: "open",
    links: [{ label: "bad", url: "javascript:alert(1)" }, { label: "ok", url: "https://example.invalid/" }],
  }, 0);
  assert.doesNotMatch(html, /<img|<script/);
  assert.doesNotMatch(html, /href="javascript:/);
  assert.match(html, /link refused/);
  assert.match(html, /href="https:\/\/example\.invalid\/"/);
});

test("a desk that is not a desk is refused, and a card missing fields is reported", () => {
  assert.throws(() => desk.renderDesk({}), /cards/);
  assert.throws(() => desk.renderDesk(null), /cards/);
  const result = desk.renderDesk({ cards: [{ id: "a", status: "open" }] });
  assert.deepEqual(plain(result.problems), ["card a has no kind", "card a has no title", "card a has no why"]);
});

test("the answer snippet holds the card, the new status and {choice, note, at}", () => {
  const s = desk.answerSnippet("wc-3-unicode", "unicode-spaces", "yes", "2026-09-25T10:00:00.000Z");
  assert.deepEqual(plain(s), {
    card: "wc-3-unicode", status: "answered",
    answer: { choice: "unicode-spaces", note: "yes", at: "2026-09-25T10:00:00.000Z" },
  });
  const noteOnly = desk.answerSnippet("q", null, "no", "2026-09-25T10:00:00.000Z");
  assert.deepEqual(Object.keys(noteOnly.answer), ["note", "at"]);
  const allowed = Object.keys(schema.definitions.card.properties.answer.properties);
  for (const k of Object.keys(s.answer)) assert.ok(allowed.includes(k), `answer.${k} is in the schema`);
});
