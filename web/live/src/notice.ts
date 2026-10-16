// The one writer of the shared session message line. Confirmations fade;
// problems stay until replaced or retracted by the shell that raised them.

const TRANSIENT_MS = 4000;

export type Notice = {
  say(text: string, options?: { transient?: boolean }): void;
  /** Clears the line only if it still shows `text`, so one shell cannot erase another's message. */
  retract(text: string): void;
  dispose(): void;
};

export function mountNotice(element: HTMLElement): Notice {
  let timer = 0;
  const show = (text: string): void => {
    window.clearTimeout(timer);
    element.textContent = text;
    element.hidden = text.length === 0;
  };
  const retract = (text: string): void => {
    if (element.textContent === text) show("");
  };
  return {
    say(text, options) {
      show(text);
      if (options?.transient) timer = window.setTimeout(() => retract(text), TRANSIENT_MS);
    },
    retract,
    dispose: () => window.clearTimeout(timer),
  };
}
