// Imperative shell for Help's music: draws the starting-sound cards and the
// example buttons from the catalogue in examples.ts.
import { EXAMPLES, STARTING_SOUNDS } from "./examples";
import type { Disposable } from "./scope";

export type HelpExamplesHost = Readonly<{
  /** The starting-sound cards. */
  sounds: HTMLElement;
  /** Featured examples, and those listed under More examples. */
  featured: HTMLElement;
  more: HTMLElement;
}>;

export type HelpExamples = Disposable & {
  /** Marks the starting sound, if any, whose score the editor holds. */
  show(score: string): void;
};

/** `choose` receives the chosen score and whether it should play at once. */
export function mountHelpExamples(host: HelpExamplesHost, choose: (source: string, plays: boolean) => void): HelpExamples {
  const abort = new AbortController();
  const button = (className: string, onClick: () => void): HTMLButtonElement => {
    const element = document.createElement("button");
    element.type = "button";
    element.className = className;
    element.addEventListener("click", onClick, { signal: abort.signal });
    return element;
  };

  const cards = STARTING_SOUNDS.map(sound => {
    const card = button("scene", () => choose(sound.source, true));
    card.setAttribute("aria-label", `Explore ${sound.title}`);
    card.title = sound.title;
    card.innerHTML = `<svg class="scene-art ${sound.artClass}" viewBox="0 0 100 64" aria-hidden="true">${sound.art}</svg>`;
    return { card, source: sound.source };
  });
  host.sounds.replaceChildren(...cards.map(({ card }) => card));

  host.featured.replaceChildren();
  host.more.replaceChildren();
  for (const example of EXAMPLES) {
    const list = example.more ? host.more : host.featured;
    const choice = button("example", () => choose(example.source, false));
    choice.textContent = example.label;
    list.append(choice);
    if (example.note) {
      const note = document.createElement("p");
      note.className = "cheat-note";
      note.textContent = example.note;
      list.append(note);
    }
  }

  return {
    show(score) {
      for (const { card, source } of cards) card.setAttribute("aria-pressed", String(source === score));
    },
    dispose: () => abort.abort(),
  };
}
