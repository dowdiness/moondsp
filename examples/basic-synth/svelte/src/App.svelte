<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import { createAudio } from "../../core/audio";
  import { controlView, cutoffFromInput, cutoffPosition, volumeFromInput, type ControlState } from "../../core/controls";
  import {
    EDITABLE_SELECTOR,
    createDeferredReleases,
    createNoteInput,
    createPointerSessions,
    interpretActivationClick,
    interpretComputerKeyDown,
    interpretComputerKeyUp,
    interpretFocusedBlur,
    interpretFocusedKeyDown,
    interpretFocusedKeyUp,
    type Gesture,
  } from "../../core/input";
  import { EMPTY_KEYBOARD, keyboardView, navigationView } from "../../core/keyboard";
  import {
    NOTES,
    activeNoteName,
    noteAriaLabel,
    noteDescription,
  } from "../../core/notes";
  import { DEFAULT_SETTINGS } from "../../core/synth";

  let controls = $state.raw<ControlState>({ phase: "idle", errorText: "" });
  let keyboard = $state.raw(EMPTY_KEYBOARD);
  let volume = $state<number>(DEFAULT_SETTINGS.volume);
  let cutoff = $state<number>(DEFAULT_SETTINGS.cutoff);
  let keyboardScroll: HTMLElement | undefined;
  let keyboardElement: HTMLElement | undefined;
  let navigation = $state.raw(navigationView(0, 0, 0));

  const control = $derived(controlView(controls));
  const keyboardState = $derived(keyboardView(keyboard));

  function tryPointerCapture(button: HTMLButtonElement, pointerId: number): void {
    try {
      button.setPointerCapture(pointerId);
    } catch {
      // Browsers without capture still deliver pointerup/cancel.
    }
  }

  function releasePointerCapture(button: HTMLButtonElement, pointerId: number): void {
    try {
      if (button.hasPointerCapture(pointerId)) button.releasePointerCapture(pointerId);
    } catch {
      // Capture may already be gone during page teardown.
    }
  }

  const pointers = createPointerSessions<HTMLButtonElement>({
    capture: tryPointerCapture,
    releaseCapture: releasePointerCapture,
  });

  const deferredReleases = createDeferredReleases();

  const audioBridge = {
    press(_midi: number): void {},
    release(_nextMidi: number | null): void {},
  };

  const notes = createNoteInput({
    onChange(state) {
      keyboard = state;
    },
    onAction(action) {
      if (action.type === "press") audioBridge.press(action.midi);
      else audioBridge.release(action.nextMidi);
    },
  });

  function handle(gesture: Gesture | null, event?: Event): void {
    if (notes.handle(gesture) && event && "preventDefault" in event) event.preventDefault();
    if (gesture?.releaseAfterMs !== undefined) {
      const release = gesture.events[0];
      if (release?.type === "press") {
        deferredReleases.after(release.id, gesture.releaseAfterMs, () => {
          notes.apply({ type: "release", id: release.id });
        });
      }
    }
  }

  const audio = createAudio(
    {
      render(state) {
        controls = state;
        notes.setEnabled(state.phase === "running");
      },
      clearNotes() {
        deferredReleases.clear();
        pointers.clear();
        notes.clear();
      },
    },
    DEFAULT_SETTINGS,
  );
  audioBridge.press = midi => audio.press(midi);
  audioBridge.release = nextMidi => audio.release(nextMidi);

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
    handle(interpretComputerKeyDown({
      key: event.key,
      repeat: event.repeat,
      altKey: event.altKey,
      ctrlKey: event.ctrlKey,
      metaKey: event.metaKey,
      targetIsEditable: event.target instanceof HTMLElement && !!event.target.closest(EDITABLE_SELECTOR),
      enabled: keyboard.enabled,
    }), event);
  }

  function handleWindowKeyUp(event: KeyboardEvent): void {
    handle(interpretComputerKeyUp(event.key));
  }

  function handleVisibilityChange(): void {
    if (document.hidden) audio.stopNotes();
  }

  function handlePointerDown(event: PointerEvent, midi: number): void {
    if (event.button !== 0 || !keyboard.enabled) return;
    event.preventDefault();
    const button = event.currentTarget as HTMLButtonElement;
    const { replaceId, pressId } = pointers.begin(event.pointerId, button);
    if (replaceId) notes.apply({ type: "release", id: replaceId });
    notes.apply({ type: "press", id: pressId, midi });
  }

  function finishPointer(event: PointerEvent): void {
    const id = pointers.end(event.pointerId);
    if (id) notes.apply({ type: "release", id });
  }

  function updateNavigation(): void {
    if (!keyboardScroll) return;
    navigation = navigationView(keyboardScroll.scrollLeft, keyboardScroll.scrollWidth, keyboardScroll.clientWidth);
  }

  function scrollNotes(direction: -1 | 1): void {
    keyboardScroll?.scrollBy({ left: direction * keyboardScroll.clientWidth * 0.8, behavior: "auto" });
  }

  onMount(() => {
    updateNavigation();
    const observer = new ResizeObserver(updateNavigation);
    if (keyboardScroll) observer.observe(keyboardScroll);
    if (keyboardElement) observer.observe(keyboardElement);
    return () => observer.disconnect();
  });

  onDestroy(() => {
    deferredReleases.clear();
    audio.powerOff();
  });
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
            {activeNoteName(keyboardState.activeMidi)}
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
            aria-label={noteAriaLabel(note)}
            aria-pressed={keyboardState.heldMidis.has(note.midi)}
            aria-describedby={`note-description-${note.midi}`}
            disabled={!keyboard.enabled}
            onkeydown={(event) => handle(interpretFocusedKeyDown(event.key, note.midi, event.repeat), event)}
            onkeyup={(event) => handle(interpretFocusedKeyUp(event.key, note.midi), event)}
            onblur={() => handle(interpretFocusedBlur(note.midi))}
            onclick={(event) => handle(interpretActivationClick(event.detail, note.midi))}
            onpointerdown={(event) => handlePointerDown(event, note.midi)}
            onpointerup={finishPointer}
            onpointercancel={finishPointer}
            onlostpointercapture={finishPointer}
          >
            <span class="note-name">{note.name}</span><kbd>{note.computerKey}</kbd>
            <span id={`note-description-${note.midi}`} class="sr-only">{noteDescription(note.midi, keyboardState.activeMidi, keyboardState.heldMidis)}</span>
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
