<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import { createAudio, type AudioActions } from "./audio";
  import { controlView, cutoffFromInput, cutoffPosition, volumeFromInput, type ControlState } from "./controls";
  import {
    EMPTY_KEYBOARD,
    keyboardView,
    navigationView,
    updateKeyboard,
    type KeyboardEvent as KeyboardTransition,
    type KeyboardState,
    type NoteAction,
  } from "./keyboard";
  import { DEFAULT_SETTINGS } from "./synth";

  interface Note {
    readonly midi: number;
    readonly name: string;
    readonly computerKey: string;
    readonly black: boolean;
  }

  const NOTES: readonly Note[] = [
    { midi: 60, name: "C4", computerKey: "A", black: false },
    { midi: 61, name: "C♯4", computerKey: "W", black: true },
    { midi: 62, name: "D4", computerKey: "S", black: false },
    { midi: 63, name: "D♯4", computerKey: "E", black: true },
    { midi: 64, name: "E4", computerKey: "D", black: false },
    { midi: 65, name: "F4", computerKey: "F", black: false },
    { midi: 66, name: "F♯4", computerKey: "T", black: true },
    { midi: 67, name: "G4", computerKey: "G", black: false },
    { midi: 68, name: "G♯4", computerKey: "Y", black: true },
    { midi: 69, name: "A4", computerKey: "H", black: false },
    { midi: 70, name: "A♯4", computerKey: "U", black: true },
    { midi: 71, name: "B4", computerKey: "J", black: false },
    { midi: 72, name: "C5", computerKey: "K", black: false },
  ];

  const NOTE_BY_MIDI = new Map(NOTES.map((note) => [note.midi, note]));
  const MIDI_BY_KEY = new Map(NOTES.map((note) => [note.computerKey.toLowerCase(), note.midi]));

  let controls = $state.raw<ControlState>({ phase: "idle", errorText: "" });
  let keyboard = $state.raw<KeyboardState>(EMPTY_KEYBOARD);
  let volume = $state<number>(DEFAULT_SETTINGS.volume);
  let cutoff = $state<number>(DEFAULT_SETTINGS.cutoff);
  let keyboardScroll: HTMLElement | undefined;
  let keyboardElement: HTMLElement | undefined;
  let navigation = $state.raw(navigationView(0, 0, 0));

  const control = $derived(controlView(controls));
  const keyboardState = $derived(keyboardView(keyboard));
  const pointerNotes = new Map<number, { readonly id: string; readonly button: HTMLButtonElement }>();

  function transition(event: KeyboardTransition): NoteAction | null {
    const next = updateKeyboard(keyboard, event);
    keyboard = next.state;
    return next.action;
  }

  function dispatch(event: KeyboardTransition): void {
    const action = transition(event);
    if (action?.type === "press") audio.press(action.midi);
    else if (action?.type === "release") audio.release(action.nextMidi);
  }

  function release(id: string): void {
    dispatch({ type: "release", id });
  }

  function releaseCapture(button: HTMLButtonElement, pointerId: number): void {
    try {
      if (button.hasPointerCapture(pointerId)) button.releasePointerCapture(pointerId);
    } catch {
      // Capture may already be gone during page teardown.
    }
  }

  function clearNotes(): void {
    for (const [pointerId, note] of pointerNotes) releaseCapture(note.button, pointerId);
    pointerNotes.clear();
    transition({ type: "clear" });
  }

  const audio: AudioActions = createAudio(
    {
      render(state) {
        controls = state;
        transition({ type: "enable", enabled: state.phase === "running" });
      },
      clearNotes,
    },
    DEFAULT_SETTINGS,
  );

  function handlePower(): void {
    if (control.powerAction === "on") audio.powerOn();
    else audio.powerOff();
  }

  function handleVolume(event: Event): void {
    const input = event.currentTarget as HTMLInputElement;
    volume = volumeFromInput(input.valueAsNumber);
    audio.volumeChanged(volume);
  }

  function handleCutoff(event: Event): void {
    const input = event.currentTarget as HTMLInputElement;
    cutoff = cutoffFromInput(input.valueAsNumber);
    audio.cutoffChanged(cutoff);
  }

  function handleWindowKeyDown(event: KeyboardEvent): void {
    if (event.repeat || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.target instanceof HTMLElement && event.target.closest("input, select, textarea, [contenteditable=\"true\"]")) return;
    const key = event.key.toLowerCase();
    const midi = MIDI_BY_KEY.get(key);
    if (midi === undefined || !keyboard.enabled) return;
    event.preventDefault();
    dispatch({ type: "press", id: `keyboard:${key}`, midi });
  }

  function handleWindowKeyUp(event: KeyboardEvent): void {
    const key = event.key.toLowerCase();
    if (MIDI_BY_KEY.has(key)) release(`keyboard:${key}`);
  }

  function handleVisibilityChange(): void {
    if (document.hidden) audio.stopNotes();
  }

  function handleFocusedKeyDown(event: KeyboardEvent, midi: number): void {
    if (event.key !== " " && event.key !== "Enter") return;
    event.preventDefault();
    if (!event.repeat) dispatch({ type: "press", id: `focus:${midi}`, midi });
  }

  function handleFocusedKeyUp(event: KeyboardEvent, midi: number): void {
    if (event.key !== " " && event.key !== "Enter") return;
    event.preventDefault();
    release(`focus:${midi}`);
  }

  function handleKeyboardActivation(event: MouseEvent, midi: number): void {
    if (event.detail !== 0) return;
    const id = `activation:${midi}`;
    dispatch({ type: "press", id, midi });
    window.setTimeout(() => release(id), 150);
  }

  function handlePointerDown(event: PointerEvent, midi: number): void {
    if (event.button !== 0 || !keyboard.enabled) return;
    event.preventDefault();
    const button = event.currentTarget as HTMLButtonElement;
    const existing = pointerNotes.get(event.pointerId);
    if (existing) release(existing.id);
    const id = `pointer:${event.pointerId}`;
    pointerNotes.set(event.pointerId, { id, button });
    try {
      button.setPointerCapture(event.pointerId);
    } catch {
      // Browsers without capture still deliver pointerup/cancel.
    }
    dispatch({ type: "press", id, midi });
  }

  function finishPointer(event: PointerEvent): void {
    const note = pointerNotes.get(event.pointerId);
    if (!note) return;
    pointerNotes.delete(event.pointerId);
    releaseCapture(note.button, event.pointerId);
    release(note.id);
  }

  function updateNavigation(): void {
    if (!keyboardScroll) return;
    navigation = navigationView(keyboardScroll.scrollLeft, keyboardScroll.scrollWidth, keyboardScroll.clientWidth);
  }

  function scrollNotes(direction: -1 | 1): void {
    keyboardScroll?.scrollBy({ left: direction * keyboardScroll.clientWidth * 0.8, behavior: "auto" });
  }

  function noteDescription(midi: number): string {
    if (keyboardState.activeMidi === midi) return "Active note";
    return keyboardState.heldMidis.has(midi) ? "Held; another note is active" : "Hold to play";
  }

  onMount(() => {
    updateNavigation();
    const observer = new ResizeObserver(updateNavigation);
    if (keyboardScroll) observer.observe(keyboardScroll);
    if (keyboardElement) observer.observe(keyboardElement);
    return () => observer.disconnect();
  });

  onDestroy(() => audio.powerOff());
</script>

<svelte:window
  onkeydown={handleWindowKeyDown}
  onkeyup={handleWindowKeyUp}
  onblur={audio.stopNotes}
  onpagehide={audio.powerOff}
/>
<svelte:document onvisibilitychange={handleVisibilityChange} />

<main class="app-shell">
  <header class="page-header">
    <h1 id="instrument-title">Svelte synth</h1>
    <span class="brand">moondsp</span>
  </header>

  <section class="instrument-panel" aria-labelledby="instrument-title">
    <div class="panel-heading">
      <div class="status-cluster">
        <span class="status-mark" aria-hidden="true"></span>
        <p class="status" role="status" aria-live="polite" aria-atomic="true" data-state={controls.phase}>
          {control.status}
        </p>
      </div>
      <button
        class="button button-primary"
        type="button"
        aria-label={control.name}
        aria-busy={control.busy}
        disabled={control.powerDisabled}
        onclick={handlePower}
      >
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v9M6.4 5.6a8 8 0 1 0 11.2 0" /></svg>
        <span>{control.label}</span>
      </button>
    </div>

    <div class="error-panel" role="alert" aria-live="assertive" hidden={!control.errorVisible}>
      <p>{controls.errorText}</p>
    </div>

    <div class="parameter-controls" role="group" aria-label="Synth controls">
      <label class="parameter" for="volume">
        <span class="parameter-label">
          <span class="parameter-name">
            <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10h4l5-4v12l-5-4H4ZM17 8a6 6 0 0 1 0 8" /></svg>
            Volume
          </span>
          <output for="volume">{Math.round(volume * 100)}%</output>
        </span>
        <input
          id="volume"
          type="range"
          min="0"
          max="1"
          step="0.01"
          value={volume}
          aria-valuetext={`${Math.round(volume * 100)}%`}
          disabled={control.inputsDisabled}
          oninput={handleVolume}
        />
      </label>
      <label class="parameter" for="cutoff">
        <span class="parameter-label">
          <span class="parameter-name">
            <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h7c6 0 3 12 11 12M3 21h18" /></svg>
            Filter
          </span>
          <output for="cutoff">{Math.round(cutoff).toLocaleString()} Hz</output>
        </span>
        <input
          id="cutoff"
          type="range"
          min="0"
          max="1"
          step="0.001"
          value={cutoffPosition(cutoff).toFixed(3)}
          aria-valuetext={`${Math.round(cutoff).toLocaleString()} Hz`}
          disabled={control.inputsDisabled}
          oninput={handleCutoff}
        />
      </label>
    </div>

    <div class="keyboard-toolbar">
      <div class="note-readout">
        <span class="voice-mode">Mono</span>
        <span class="active-note-display" data-active={keyboardState.activeMidi !== null}>
          <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10h4l5-4v12l-5-4H4ZM17 8a6 6 0 0 1 0 8" /></svg>
          <output aria-label="Active note" aria-live="off">
            {keyboardState.activeMidi === null ? "—" : NOTE_BY_MIDI.get(keyboardState.activeMidi)?.name ?? "—"}
          </output>
        </span>
      </div>
      {#if !navigation.hidden}
        <div class="keyboard-navigation" role="group" aria-label="Keyboard range">
          <button
            class="button button-icon"
            type="button"
            aria-label="Lower notes"
            aria-controls="piano-scroll"
            disabled={navigation.lowerDisabled}
            onclick={() => scrollNotes(-1)}
          >
            <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m14 6-6 6 6 6" /></svg>
          </button>
          <button
            class="button button-icon"
            type="button"
            aria-label="Higher notes"
            aria-controls="piano-scroll"
            disabled={navigation.higherDisabled}
            onclick={() => scrollNotes(1)}
          >
            <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m10 6 6 6-6 6" /></svg>
          </button>
        </div>
      {/if}
    </div>

    <!-- svelte-ignore a11y_no_noninteractive_tabindex (Scrollable keyboard region must be keyboard focusable.) -->
    <div
      id="piano-scroll"
      class="keyboard-scroll"
      role="region"
      tabindex="0"
      aria-label="Piano keyboard. Hold a note or use its letter key. Scroll for higher notes."
      bind:this={keyboardScroll}
      onscroll={updateNavigation}
    >
      <div class="keyboard" role="group" aria-label="C4 through C5" bind:this={keyboardElement}>
        {#each NOTES as note (note.midi)}
          <button
            class={[
              "key",
              {
                "is-natural": !note.black,
                "is-black": note.black,
                "is-held": keyboardState.heldMidis.has(note.midi),
                "is-active": keyboardState.activeMidi === note.midi,
              },
            ]}
            type="button"
            data-midi={note.midi}
            data-computer-key={note.computerKey}
            aria-label={`${note.name.replace("♯", " sharp ")}, computer key ${note.computerKey}`}
            aria-pressed={keyboardState.heldMidis.has(note.midi)}
            aria-describedby={`note-description-${note.midi}`}
            disabled={!keyboard.enabled}
            onkeydown={(event) => handleFocusedKeyDown(event, note.midi)}
            onkeyup={(event) => handleFocusedKeyUp(event, note.midi)}
            onblur={() => release(`focus:${note.midi}`)}
            onclick={(event) => handleKeyboardActivation(event, note.midi)}
            onpointerdown={(event) => handlePointerDown(event, note.midi)}
            onpointerup={finishPointer}
            onpointercancel={finishPointer}
            onlostpointercapture={finishPointer}
          >
            <span class="note-name">{note.name}</span><kbd>{note.computerKey}</kbd>
            <span id={`note-description-${note.midi}`} class="sr-only">{noteDescription(note.midi)}</span>
          </button>
        {/each}
      </div>
    </div>
  </section>

  <footer class="page-footer">
    <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 14v-2a8 8 0 0 1 16 0v2" /><rect x="3" y="12" width="4" height="8" rx="2" /><rect x="17" y="12" width="4" height="8" rx="2" /></svg>
    <p>Keep device volume low.</p>
  </footer>
</main>
