import { isolateHistory } from "@codemirror/commands";
import type { EditorView } from "@codemirror/view";
import type { Notice } from "./notice";
import type { Disposable } from "./scope";

// A score link carries the plain-text score in the URL fragment, compressed with
// deflate-raw and base64url-encoded. Fragments are never sent to a server.
// Opening a link behaves like Open: one undoable replacement of the draft.

const PREFIX = "#score=";
// The same bound as Import: a decoded score larger than 1 MiB is not opened.
const MAX_SCORE_BYTES = 1024 * 1024;
// Deflate output exceeds its input by at most a few bytes per 64 KiB block, so a fragment
// longer than base64 of 1 MiB plus 1% cannot decode to an acceptable score.
const MAX_FRAGMENT_CHARS = Math.ceil(MAX_SCORE_BYTES * 1.01 * 4 / 3) + PREFIX.length;
const LONG_LINK_CHARS = 8000;

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function encodeScoreLink(source: string, base: string): Promise<string> {
  const output = new Blob([new TextEncoder().encode(source)]).stream().pipeThrough(new CompressionStream("deflate-raw"));
  const compressed = new Uint8Array(await new Response(output).arrayBuffer());
  return `${base}${PREFIX}${toBase64Url(compressed)}`;
}

/** Inflates at most `limit` bytes; returns null as soon as the output would exceed it. */
async function inflateLimited(bytes: Uint8Array<ArrayBuffer>, limit: number): Promise<Uint8Array | null> {
  const reader = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

export async function decodeScoreFragment(fragment: string): Promise<string | null> {
  if (!fragment.startsWith(PREFIX) || fragment.length > MAX_FRAGMENT_CHARS) return null;
  const bytes = await inflateLimited(fromBase64Url(fragment.slice(PREFIX.length)), MAX_SCORE_BYTES);
  return bytes === null ? null : new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

/** Pure: the warning appended to a share message for a link of `length` characters. */
export function longLinkNote(length: number): string {
  return length > LONG_LINK_CHARS ? " This score is long; some apps may shorten the link, so Download is safer." : "";
}

export type ScoreLinkElements = {
  button: HTMLButtonElement;
};

export function mountScoreLink(elements: ScoreLinkElements, deps: { view: EditorView; notice: Notice }): Disposable {
  const { button } = elements;
  const { view, notice } = deps;
  let disposed = false;
  const base = (): string => `${location.origin}${location.pathname}${location.search}`;

  // Clipboard writes must begin inside the click: Safari rejects a write that
  // follows an await. The clipboard receives the link as a pending item instead.
  // Insecure (plain HTTP) pages have no Clipboard API at all, so the write can
  // also fail before it returns a promise.
  const share = (): void => {
    const failed = (): void => notice.say("Could not copy a link to the clipboard. Download keeps this score exactly.");
    const link = encodeScoreLink(view.state.doc.toString(), base());
    let written: Promise<void>;
    try {
      const item = new ClipboardItem({ "text/plain": link.then(text => new Blob([text], { type: "text/plain" })) });
      written = navigator.clipboard.write([item]);
    } catch {
      failed();
      return;
    }
    written.then(async () => {
      const long = longLinkNote((await link).length);
      notice.say(`Link copied to the clipboard. Opening it loads this score; nothing is uploaded.${long}`, { transient: !long });
    }, failed);
  };

  const openFromFragment = async (): Promise<void> => {
    const fragment = location.hash;
    if (!fragment.startsWith(PREFIX)) return;
    const before = view.state.doc;
    let source: string | null = null;
    try {
      source = await decodeScoreFragment(fragment);
    } catch {
      source = null;
    }
    if (disposed || location.hash !== fragment) return;
    history.replaceState(null, "", base());
    if (source === null) {
      notice.say("That score link could not be read. Your score is unchanged.");
      return;
    }
    if (view.state.doc !== before) {
      notice.say("The linked score was not opened because your text changed while it loaded. Open the link again.");
      return;
    }
    if (source === before.toString()) return;
    view.dispatch({
      changes: { from: 0, to: before.length, insert: source },
      annotations: isolateHistory.of("full"),
    });
    notice.say("Opened a shared score. Undo restores your previous score.", { transient: true });
  };

  const onHashChange = (): void => { void openFromFragment(); };
  button.addEventListener("click", share);
  window.addEventListener("hashchange", onHashChange);
  void openFromFragment();
  return {
    dispose(): void {
      disposed = true;
      button.removeEventListener("click", share);
      window.removeEventListener("hashchange", onHashChange);
    },
  };
}
