// A minimal DOM for testing desk/index.html in node: just what the page's
// renderer uses (createElement, createTextNode, setAttribute, appendChild).
// Setting innerHTML throws, so a renderer that reached for HTML would fail.

class Text {
  constructor(data) { this.nodeType = 3; this.data = String(data); this.parentNode = null; }
  get textContent() { return this.data; }
}

class Element {
  constructor(tag) {
    this.nodeType = 1;
    this.localName = String(tag).toLowerCase();
    this.attributes = new Map();
    this.childNodes = [];
    this.parentNode = null;
  }
  setAttribute(name, value) { this.attributes.set(String(name), String(value)); }
  getAttribute(name) { return this.attributes.has(name) ? this.attributes.get(name) : null; }
  hasAttribute(name) { return this.attributes.has(name); }
  appendChild(node) {
    if (!(node instanceof Text || node instanceof Element)) throw new TypeError("appendChild: not a node");
    node.parentNode = this;
    this.childNodes.push(node);
    return node;
  }
  get children() { return this.childNodes.filter((n) => n instanceof Element); }
  get textContent() { return this.childNodes.map((n) => n.textContent).join(""); }
  set textContent(value) { this.childNodes = [new Text(value)]; }
  set innerHTML(_) { throw new Error("innerHTML is not allowed"); }
  get innerHTML() { throw new Error("innerHTML is not allowed"); }
}

export const doc = {
  createElement: (tag) => new Element(tag),
  createTextNode: (data) => new Text(data),
};

const VOID = new Set(["input", "br", "img", "meta", "link"]);
const escText = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escAttr = (s) => escText(s).replace(/"/g, "&quot;");

export function serialize(node) {
  if (node instanceof Text) return escText(node.data);
  const attrs = [...node.attributes].map(([k, v]) => ` ${k}="${escAttr(v)}"`).join("");
  if (VOID.has(node.localName)) return `<${node.localName}${attrs}>`;
  return `<${node.localName}${attrs}>${node.childNodes.map(serialize).join("")}</${node.localName}>`;
}

/* Every element under node (node included) for which test(el) holds. */
export function all(node, test) {
  const out = [];
  (function walk(n) {
    if (!(n instanceof Element)) return;
    if (test(n)) out.push(n);
    n.childNodes.forEach(walk);
  })(node);
  return out;
}

export const attr = (name, value) => (el) =>
  value === undefined ? el.hasAttribute(name) : el.getAttribute(name) === value;
export const tag = (name) => (el) => el.localName === name;
export const cls = (name) => (el) => (el.getAttribute("class") || "").split(/\s+/).includes(name);
