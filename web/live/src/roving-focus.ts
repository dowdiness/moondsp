// Functional core for arrow-key focus within a row or column of controls.

/** The index Left, Right, Home, or End moves to among `count` controls; null for any other key. */
export function columnFor(key: string, index: number, count: number): number | null {
  switch (key) {
    case "ArrowLeft": return Math.max(0, index - 1);
    case "ArrowRight": return Math.min(count - 1, index + 1);
    case "Home": return 0;
    case "End": return count - 1;
    default: return null;
  }
}

/** The index Up or Down moves to among `count` rows; null for any other key. */
export function rowFor(key: string, index: number, count: number): number | null {
  switch (key) {
    case "ArrowUp": return Math.max(0, index - 1);
    case "ArrowDown": return Math.min(count - 1, index + 1);
    default: return null;
  }
}
