export type DraftHandle = object;
export function create_draft(text: string, onCreated: (handle: DraftHandle) => void, onError: (message: string) => void): void;
export function draft_state(handle: DraftHandle): string;
export function edit_draft(handle: DraftHandle, transaction: string): string;
export function prepare_playback(handle: DraftHandle): string;
export function dispose_draft(handle: DraftHandle): void;
