// Imperative shell for drawn SVG: a render describes its elements as data, and
// patchSvg makes the document match while keeping each element's identity.

const NS = "http://www.w3.org/2000/svg";

/** One SVG element as a render describes it. */
export type SvgNode = Readonly<{
  /** Identity among its siblings: the element made for a key is reused while the key remains. */
  key: string;
  tag: keyof SVGElementTagNameMap;
  /** Classes the element is made with. */
  className?: string;
  /** Classes this render turns on or off. Classes others toggle, such as playback's, are left alone. */
  flags?: Readonly<Record<string, boolean>>;
  attrs?: Readonly<Record<string, string>>;
  text?: string;
  children?: readonly SvgNode[];
}>;

const keyed = new WeakMap<Element, Map<string, SVGElement>>();
const written = new WeakMap<Element, readonly string[]>();

/**
 * Makes `parent`'s children match `nodes`. An element that stays keeps its
 * focus, pointer capture, box, and other classes, so a render never detaches
 * what the user is touching.
 */
export function patchSvg(parent: Element, nodes: readonly SvgNode[]): void {
  const previous = keyed.get(parent) ?? new Map<string, SVGElement>();
  const next = new Map<string, SVGElement>();
  for (const node of nodes) {
    const id = `${node.tag}.${node.className ?? ""}#${node.key}`;
    if (next.has(id)) throw new Error(`Two SVG elements share the key ${id}`);
    next.set(id, previous.get(id) ?? create(node));
  }
  // Remove leftovers first, so that elements staying in order are never moved.
  for (const [id, element] of previous) if (!next.has(id)) element.remove();
  let cursor = parent.firstChild;
  let index = 0;
  for (const element of next.values()) {
    write(element, nodes[index++]);
    if (element === cursor) cursor = cursor.nextSibling;
    else parent.insertBefore(element, cursor);
  }
  keyed.set(parent, next);
}

function create(node: SvgNode): SVGElement {
  const element = document.createElementNS(NS, node.tag);
  if (node.className) element.setAttribute("class", node.className);
  return element;
}

function write(element: SVGElement, node: SvgNode): void {
  const attrs = node.attrs ?? {};
  for (const name of written.get(element) ?? []) if (!(name in attrs)) element.removeAttribute(name);
  for (const [name, value] of Object.entries(attrs)) if (element.getAttribute(name) !== value) element.setAttribute(name, value);
  written.set(element, Object.keys(attrs));
  for (const [name, on] of Object.entries(node.flags ?? {})) element.classList.toggle(name, on);
  if (node.text !== undefined && element.textContent !== node.text) element.textContent = node.text;
  if (node.children) patchSvg(element, node.children);
}
