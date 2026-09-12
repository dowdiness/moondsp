import type { AudioEngine, AudioEvent, AudioSession, AudioStatus, SchedulerSession } from "./audio";
import { RequestId, ScoreSource } from "./playback-protocol";
import type { Draft, PlaybackMode, PlaybackReceipt, ScoreRequest } from "./playback-protocol";
import { Tempo, committedTempo, tempoText, editTempo, commitTempo, receiveTempo } from "./tempo";
import type { TempoField } from "./tempo";

type Feedback = Readonly<{ message: string; kind: "ok" | "error" | "info" }>;
type Diagnostic = Readonly<{ message: string; documentLength: number }>;
export type PlaybackView = Readonly<{
  status: AudioStatus;
  mode: PlaybackMode;
  tempoText: string;
  feedback: Feedback | null;
  diagnostic: Diagnostic | null;
}>;

type Scheduled = { kind: "none" } | { kind: "queued"; timer: ReturnType<typeof setTimeout> };
type SchedulerRun = {
  run: symbol;
  session: SchedulerSession;
  requests: Map<number, ScoreRequest>;
  latest: RequestId | null;
  tempoRequest: RequestId;
  scheduled: Scheduled;
};
type SchedulerState =
  | (SchedulerRun & { kind: "awaiting-acceptance" })
  | (SchedulerRun & { kind: "playing"; accepted: ScoreSource });
type PlaybackState =
  | { kind: "stopped" }
  | { kind: "opening"; run: symbol }
  | SchedulerState
  | { kind: "compiled"; run: symbol; session: Extract<AudioSession, { kind: "compiled" }> }
  | { kind: "closing"; run: symbol; session: AudioSession }
  | { kind: "failed"; message: string };

type SubmissionOutcome = "submitted" | "unchanged" | "empty" | "stored";
type ReceiptOutcome = "accepted-current" | "accepted-stale" | "rejected-current" |
  "rejected-stale" | "superseded" | "untracked-request" | "obsolete-session" | "failed" |
  "tempo-accepted" | "tempo-rejected";
type ToggleOutcome = "started" | "stopped" | "busy" | "empty" | "failed" | "obsolete";

const DEBOUNCE_MS = 200;

/** The page's playback owner. Views are projections, never writable domain state. */
export class LivePlayback {
  private state: PlaybackState = { kind: "stopped" };
  private draft: Draft;
  private tempo: TempoField = { kind: "displaying", tempo: Tempo.DEFAULT };
  private feedback: Feedback | null = null;
  private diagnostic: Diagnostic | null = null;
  private nextRequest = RequestId.first();

  constructor(
    private readonly engine: Pick<AudioEngine, "mode" | "openSession">,
    initial: { text: string },
    private readonly present: (state: PlaybackView) => void,
  ) {
    this.draft = ScoreSource.parse("pattern", initial.text);
    this.render();
  }

  private mode(): PlaybackMode {
    return this.draft.kind === "score" ? this.draft.score.mode : this.draft.mode;
  }

  private text(): string {
    return this.draft.kind === "score" ? this.draft.score.text : this.draft.text;
  }

  private status(): AudioStatus {
    switch (this.state.kind) {
      case "stopped": return { kind: "idle" };
      case "opening": return { kind: "starting" };
      case "awaiting-acceptance": case "playing": case "compiled": return { kind: "running" };
      case "closing": return { kind: "stopping" };
      case "failed": return { kind: "error", message: this.state.message };
    }
  }

  private render(): void {
    this.present({ status: this.status(), mode: this.mode(), tempoText: tempoText(this.tempo),
      feedback: this.feedback, diagnostic: this.diagnostic });
  }

  edit(text: string): "stored" | "scheduled" {
    this.draft = ScoreSource.parse(this.mode(), text);
    switch (this.state.kind) {
      case "awaiting-acceptance": case "playing": {
        const state = this.state;
        this.cancelScheduled(state);
        state.scheduled = { kind: "queued", timer: setTimeout(() => {
          state.scheduled = { kind: "none" };
          this.submitCurrent();
        }, DEBOUNCE_MS) };
        return "scheduled";
      }
      case "stopped": case "opening": case "closing": case "failed": case "compiled":
        return "stored";
    }
  }

  selectMode(mode: PlaybackMode): SubmissionOutcome {
    this.draft = ScoreSource.parse(mode, this.text());
    this.feedback = { message: `${mode} mode selected`, kind: "info" };
    this.render();
    return this.submitCurrent();
  }

  useExample(score: { mode: PlaybackMode; text: string; bpm?: string }): SubmissionOutcome {
    this.draft = ScoreSource.parse(score.mode, score.text);
    if (score.bpm !== undefined) this.commitBpm(score.bpm);
    this.render();
    return this.submitCurrent(true);
  }

  editBpm(text: string): void {
    this.tempo = editTempo(this.tempo, text);
    this.render();
  }

  commitBpm(text: string): "committed" | "restored" {
    const result = commitTempo(editTempo(this.tempo, text));
    this.tempo = result.field;
    switch (result.kind) {
      case "committed":
        this.applyTempo(result.tempo);
        this.feedback = { message: `Requested BPM ${result.tempo.value}`, kind: "info" };
        break;
      case "restored":
        this.feedback = { message: `${result.message} Restored BPM ${committedTempo(this.tempo).value}.`, kind: "info" };
        break;
    }
    this.render();
    return result.kind;
  }

  private applyTempo(tempo: Tempo): "sent" | "stored" {
    switch (this.state.kind) {
      case "awaiting-acceptance": case "playing":
        this.state.tempoRequest = this.allocateRequest();
        this.state.session.requestTempoChange(tempo, this.state.tempoRequest);
        return "sent";
      case "stopped": case "opening": case "closing": case "failed": case "compiled": return "stored";
    }
  }

  /** Call from a user gesture; openSession() begins browser audio activation synchronously. */
  async toggle(): Promise<ToggleOutcome> {
    switch (this.state.kind) {
      case "awaiting-acceptance": case "playing": case "compiled": {
        const outcome = await this.close(this.state);
        if (outcome === "stopped") {
          this.feedback = { message: "stopped", kind: "info" };
          this.render();
        }
        return outcome;
      }
      case "opening": case "closing": return "busy";
      case "stopped": case "failed": break;
    }
    if (this.engine.mode === "scheduler" && this.draft.kind === "empty") {
      this.emptyFeedback();
      return "empty";
    }
    const opening = { kind: "opening" as const, run: Symbol("playback run") };
    this.state = opening;
    this.render();
    const opened = await this.engine.openSession(event => this.receive(event, opening.run));
    if (this.state !== opening) {
      if (opened.kind === "opened") await opened.session.close();
      return "obsolete";
    }
    switch (opened.kind) {
      case "busy":
        this.fail("Audio owner is already in use");
        return "failed";
      case "failed": this.fail(opened.message); return "failed";
      case "opened": break;
    }
    const session = opened.session;
    switch (session.kind) {
      case "compiled":
        this.state = { kind: "compiled", run: opening.run, session };
        session.fadeIn();
        this.render();
        return "started";
      case "scheduler": {
        // The current draft, not the source captured before async startup, wins.
        if (this.draft.kind === "empty") {
          await this.close({ run: opening.run, session });
          this.emptyFeedback();
          return "empty";
        }
        const state: SchedulerState = { kind: "awaiting-acceptance", run: opening.run,
          session, requests: new Map(), latest: null, tempoRequest: this.allocateRequest(),
          scheduled: { kind: "none" } };
        this.state = state;
        session.requestTempoChange(committedTempo(this.tempo), state.tempoRequest);
        this.submit(state, this.draft.score, true);
        this.render();
        return "started";
      }
    }
  }

  private fail(message: string): void {
    if (this.state.kind === "awaiting-acceptance" || this.state.kind === "playing") {
      this.cancelScheduled(this.state);
    }
    this.state = { kind: "failed", message };
    this.diagnostic = null;
    this.feedback = { kind: "error", message: `Audio failed: ${message}` };
    this.render();
  }

  private cancelScheduled(state: SchedulerState): void {
    switch (state.scheduled.kind) {
      case "none": break;
      case "queued": clearTimeout(state.scheduled.timer); state.scheduled = { kind: "none" }; break;
    }
  }

  private async close(active: { run: symbol; session: AudioSession }): Promise<"stopped" | "obsolete"> {
    if (this.state.kind === "awaiting-acceptance" || this.state.kind === "playing") {
      this.cancelScheduled(this.state);
    }
    const closing = { kind: "closing" as const, run: active.run, session: active.session };
    this.state = closing;
    this.render();
    await active.session.close();
    if (this.state !== closing) return "obsolete";
    this.state = { kind: "stopped" };
    this.render();
    return "stopped";
  }

  private emptyFeedback(): void {
    this.feedback = { message: "Enter code, then press Play.", kind: "info" };
    this.render();
  }

  private submitCurrent(restart = false): SubmissionOutcome {
    switch (this.state.kind) {
      case "stopped": case "opening": case "closing": case "failed": case "compiled": return "stored";
      case "awaiting-acceptance": case "playing": break;
    }
    const state = this.state;
    this.cancelScheduled(state);
    switch (this.draft.kind) {
      case "empty":
        state.latest = null;
        this.diagnostic = null;
        if (state.kind === "awaiting-acceptance") {
          void this.close(state);
          this.emptyFeedback();
        } else {
          this.feedback = { kind: "info", message: "(empty — keeping previous playback)" };
          this.render();
        }
        return "empty";
      case "score": return this.submit(state, this.draft.score, restart);
    }
  }

  private allocateRequest(): RequestId {
    const id = this.nextRequest;
    this.nextRequest = id.next();
    return id;
  }

  private submit(state: SchedulerState, score: ScoreSource, restart: boolean): SubmissionOutcome {
    if (!restart && state.kind === "playing" && state.requests.size === 0 &&
        state.accepted.mode === score.mode && state.accepted.text === score.text) return "unchanged";
    const id = this.allocateRequest();
    const request: ScoreRequest = { id, score, policy: restart || state.kind === "awaiting-acceptance" ||
      state.accepted.mode !== score.mode ? "restart" : "continue" };
    state.latest = id;
    state.requests.set(id.value, request);
    state.session.submitScore(request);
    return "submitted";
  }

  private receive(event: AudioEvent, run: symbol): ReceiptOutcome {
    const state = this.state;
    switch (state.kind) {
      case "stopped": case "failed": return "obsolete-session";
      case "opening": case "closing": case "compiled":
        if (state.run !== run) return "obsolete-session";
        if (event.kind === "failed") { this.fail(event.message); return "failed"; }
        return "obsolete-session";
      case "awaiting-acceptance": case "playing": break;
    }
    if (state.run !== run) return "obsolete-session";
    if (event.kind === "failed") { this.fail(event.message); return "failed"; }
    if (event.kind === "tempo") {
      const receipt = event.receipt;
      if (receipt.id.value !== state.tempoRequest.value) return "untracked-request";
      this.tempo = receiveTempo(this.tempo, receipt.tempo);
      if (receipt.kind === "rejected") {
        this.feedback = { kind: "error", message: `${receipt.message} — keeping BPM ${receipt.tempo.value}.` };
      }
      this.render();
      return receipt.kind === "accepted" ? "tempo-accepted" : "tempo-rejected";
    }
    return this.settle(state, event.receipt);
  }

  private settle(state: SchedulerState, receipt: PlaybackReceipt): ReceiptOutcome {
    const request = state.requests.get(receipt.id.value);
    if (request === undefined) return "untracked-request";
    state.requests.delete(receipt.id.value);
    if (receipt.kind === "superseded") return "superseded";
    const score = request.score;
    const current = state.latest?.value === receipt.id.value && this.draft.kind === "score" &&
      score.mode === this.draft.score.mode && score.text === this.draft.score.text;
    switch (receipt.kind) {
      case "accepted":
        // Acceptance advances playback even when the editor's diagnostic is stale.
        this.state = { ...state, kind: "playing", accepted: score };
        if (state.kind === "awaiting-acceptance") state.session.fadeIn();
        // A score receipt cannot undo a tempo command issued after that render.
        if (receipt.tempoRevision?.value === state.tempoRequest.value) {
          this.tempo = receiveTempo(this.tempo, receipt.tempo);
        }
        if (current) {
          this.diagnostic = null;
          this.feedback = { kind: "ok", message: receipt.operation === "update"
            ? `✓ ${score.mode} edit queued for the next pattern starts` : `✓ ${score.mode} updated` };
        }
        this.render();
        return current ? "accepted-current" : "accepted-stale";
      case "rejected":
        if (!current) return "rejected-stale";
        this.diagnostic = { message: receipt.message, documentLength: score.text.length };
        this.feedback = { kind: "error", message: `✗ ${receipt.message} — ${state.kind === "playing"
          ? "Your edit was not applied. The last working version keeps playing."
          : "Nothing is playing yet. Fix the code, then press Play."}${receipt.recovery === "restart"
          ? " Press Stop, then Play to apply this change from the beginning." : ""}` };
        this.render();
        if (state.kind === "awaiting-acceptance") void this.close(state);
        return "rejected-current";
    }
  }
}
