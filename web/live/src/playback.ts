import type { AudioEngine, AudioEvent, AudioSession, AudioStatus } from "./audio";
import { Draft, PlaybackInput, playerWindow, type DraftState, type PlayerWindow, type SourceProblem } from "./authoring";
import { sameDraftVersion, type DraftVersion } from "./draft-version";
import { RequestId } from "./playback-protocol";
import type { PlayerOperation, PlayerReceipt, PlayerSnapshot, SampleStatus } from "./playback-protocol";
/** The player's answer that it would not take a draft. */
type Refusal = Readonly<{ kind: "refused"; message: string }>;
/** Why the current draft cannot play: its own problem, or the player's refusal of it. */
export type DraftDiagnostic = SourceProblem | Refusal;
export type DraftStatus = "unsubmitted" | "queued" | "submitting" | "accepted" | "rejected" | "invalid" | "over-limit" | "internal";
/** The status a draft's own problem gives it, whatever the player has said. */
const PROBLEM_STATUS: Readonly<Record<SourceProblem["kind"], DraftStatus>> = {
  mistake: "invalid", "over-limit": "over-limit", internal: "internal",
};
export type PlaybackView = Readonly<{
  status: AudioStatus;
  state: PlayerSnapshot["state"] | "Starting";
  currentSource: string | null;
  acceptedVersion: DraftVersion | null;
  draftVersion: DraftVersion;
  inFlightVersions: readonly DraftVersion[];
  draftStatus: DraftStatus;
  /** Accepted tempo in BPM; null until the engine first reports one. */
  tempo: number | null;
  samplePosition: number;
  mode: PlayerSnapshot["mode"];
  cyclePosition: number;
  pendingCount: number;
  skippedCount: number;
  /** The error the log shows, if any. */
  feedback: string | null;
  /** The engine's latest report on its sample bank: what is loading and what failed. */
  samples: SampleStatus;
  diagnostic: DraftDiagnostic | null;
}>;
type Pending = {
  operation: PlayerOperation;
  input: PlaybackInput | undefined;
  resolve: (receipt: PlayerReceipt) => void;
  reject: (error: Error) => void;
};
/** The engine's latest report, or the empty state before it reports a tempo. */
type HeldSnapshot = Omit<PlayerSnapshot, "tempo"> & Readonly<{ tempo: number | null }>;
const EMPTY: HeldSnapshot = { state: "Empty", mode: "none", cyclePosition: 0, tempo: null, samplePosition: 0, pendingCount: 0, skippedCount: 0 };
const NO_SAMPLES: SampleStatus = { loading: [], failed: [], overLimit: [], unknown: [] };

/** The player's newest answer about one draft version, by receipt order. */
type Verdict = Readonly<{ version: DraftVersion; receipt: number; refusal: Refusal | null }>;

type Connection =
  | { kind: "closed" }
  | { kind: "opening"; promise: Promise<AudioSession>; retirement: () => Promise<void>; controller: AbortController }
  | { kind: "open"; session: AudioSession };
export class Player {
  private connection: Connection = { kind: "closed" };
  private snapshot: HeldSnapshot = EMPTY;
  private samples: SampleStatus = NO_SAMPLES;
  private readonly draft: Draft;
  private currentSource: string | null = null;
  private acceptedVersion: DraftVersion | null = null;
  private latestAcceptedSourceId = 0;
  private verdict: Verdict | null = null;
  /** An audio or program error, shown until the draft changes or the player answers for it. */
  private notice: string | null = null;
  /** The version whose editing or preparation failed inside moondsp, until the draft moves on. */
  private failedVersion: DraftVersion | null = null;
  private next = RequestId.first();
  private epoch = 0;
  private intent = 0;
  private lastReceipt = 0;
  private pending = new Map<number, Pending>();
  private debounce: ReturnType<typeof setTimeout> | undefined;
  private automaticInFlight: symbol | undefined;
  private latestUnsent: PlaybackInput | undefined;
  private queuedVersion: DraftVersion | null = null;
  private draftState: DraftState;

  constructor(
    private readonly engine: Pick<AudioEngine, "openSession" | "plannedFormat">,
    initial: { draft: Draft },
    private readonly present: (view: PlaybackView) => void,
  ) {
    this.draft = initial.draft;
    this.draftState = this.draft.state();
    // A configured format no player can run gets no early check; opening audio reports it.
    const planned = engine.plannedFormat === undefined ? undefined : playerWindow(engine.plannedFormat);
    if (planned?.kind === "runs") this.checkDraftWithin(planned.window);
    this.render();
  }

  /** From now on the draft also reports what the player, running in `format`, would refuse. */
  private checkDraftWithin(window: PlayerWindow): void {
    this.draftState = this.draft.checkWithin(window);
    this.notice = null;
  }

  /** The player's refusal of the current draft, if its newest answer was one. */
  private refusal(): Refusal | null {
    const verdict = this.verdict;
    return verdict !== null && sameDraftVersion(verdict.version, this.draftState.version) ? verdict.refusal : null;
  }

  view(): PlaybackView {
    const state = this.connection.kind === "opening" ? "Starting" : this.snapshot.state;
    const draftState = this.draftState;
    const refusal = this.refusal();
    const diagnostic = draftState.problem ?? refusal;
    const feedback = this.notice ?? diagnostic?.message ?? null;
    const status: AudioStatus = state === "Starting" ? { kind: "starting" }
      : state === "Fault" ? { kind: "error", message: feedback ?? "Audio failed" }
      : this.connection.kind === "open" ? { kind: "running" } : { kind: "idle" };
    const inFlightVersions: DraftVersion[] = [];
    for (const pending of this.pending.values()) {
      if (pending.input !== undefined) inFlightVersions.push(pending.input.draftVersion);
    }
    let draftStatus: DraftStatus = "unsubmitted";
    if (draftState.problem !== null) draftStatus = PROBLEM_STATUS[draftState.problem.kind];
    else if (sameDraftVersion(this.failedVersion, draftState.version)) draftStatus = "internal";
    else if (inFlightVersions.some(version => sameDraftVersion(version, draftState.version))) draftStatus = "submitting";
    else if (sameDraftVersion(this.queuedVersion, draftState.version)) draftStatus = "queued";
    else if (refusal !== null) draftStatus = "rejected";
    else if (sameDraftVersion(this.acceptedVersion, draftState.version)) draftStatus = "accepted";
    return { ...this.snapshot, state, status, currentSource: this.currentSource,
      draftVersion: draftState.version, acceptedVersion: this.acceptedVersion, inFlightVersions, draftStatus,
      feedback, diagnostic, samples: this.samples };
  }
  private render(): void { this.present(this.view()); }
  /**
   * Follows the draft to its latest version. Within one version only
   * `checkDraftWithin` changes what the draft reports, so the state already
   * held stays, and so does the identity of the problem it carries.
   */
  private refreshDraft(): void {
    const state = this.draft.state();
    if (sameDraftVersion(state.version, this.draftState.version)) return;
    this.draftState = state;
    this.notice = null;
  }
  private cancelAutomatic(): void {
    clearTimeout(this.debounce);
    this.debounce = undefined;
    this.latestUnsent = undefined;
    this.queuedVersion = null;
  }

  /** Every committed edit invalidates unsent work, even equal-text replacements. */
  editDraft(): void {
    this.cancelAutomatic();
    this.refreshDraft();
    const state = this.draftState;
    if (state.problem === null && this.connection.kind === "open") {
      this.queuedVersion = state.version;
      this.debounce = setTimeout(() => {
        this.debounce = undefined;
        try {
          this.latestUnsent = this.draft.prepare();
          this.flushAutomatic();
        } catch (error) {
          this.reportDraftFailure(error);
        }
      }, 200);
    }
    this.render();
  }

  private flushAutomatic(): void {
    if (this.automaticInFlight !== undefined || this.latestUnsent === undefined || this.connection.kind !== "open") return;
    const input = this.latestUnsent;
    this.latestUnsent = undefined;
    this.queuedVersion = null;
    const flight = Symbol();
    this.automaticInFlight = flight;
    void this.send("update", input).catch(error => this.report(error)).finally(() => {
      if (this.automaticInFlight !== flight) return;
      this.automaticInFlight = undefined;
      this.flushAutomatic();
    });
  }

  update(input: PlaybackInput): Promise<PlayerReceipt> {
    this.cancelAutomatic();
    return this.send("update", input);
  }

  /** Play the current draft from the beginning. It is prepared once audio is open, so the player's limits apply. */
  async restart(): Promise<PlayerReceipt> {
    this.cancelAutomatic();
    const intent = ++this.intent;
    const session = await this.open();
    if (intent !== this.intent) throw new DOMException("Restart cancelled", "AbortError");
    const result = await this.send("restart", this.playableDraft());
    if (result.kind === "accepted" && intent === this.intent) session.fadeIn();
    return result;
  }
  async play(): Promise<PlayerReceipt> {
    const intent = ++this.intent;
    const session = await this.open();
    if (intent !== this.intent) throw new DOMException("Play cancelled", "AbortError");
    const result = this.currentSource === null
      ? await this.send("restart", this.playableDraft())
      : await this.send("play");
    if (result.kind === "accepted" && intent === this.intent) session.fadeIn();
    return result;
  }

  /** The current draft as player input; a draft with a problem refuses with it. */
  private playableDraft(): PlaybackInput {
    this.refreshDraft();
    const problem = this.draftState.problem;
    if (problem !== null) throw new Error(problem.message);
    try {
      return this.draft.prepare();
    } catch (error) {
      this.reportDraftFailure(error);
      throw error;
    }
  }

  async pause(): Promise<PlayerReceipt> {
    // While opening, cancel initialization and reclaim its resources. Pause
    // is a local cancellation, not a command to an Empty session.
    if (this.connection.kind === "opening") {
      ++this.intent;
      ++this.epoch;
      const opening = this.connection;
      this.connection = { kind: "closed" };
      opening.controller.abort();
      const retirement = this.retire(opening);
      this.render();
      await retirement;
      throw new DOMException("Pause cancelled startup", "AbortError");
    }
    ++this.intent;
    return this.send("pause");
  }

  async close(): Promise<void> {
    const retirement = this.endRun(new DOMException("Player closed", "AbortError"));
    this.snapshot = EMPTY;
    this.notice = null;
    this.refreshDraft();
    this.render();
    await retirement;
  }

  /**
   * Ends the current run, whether it is open or still starting: its pending
   * commands fail with `reason`, its accepted score is forgotten, and its
   * connection is closed in the background.
   */
  private endRun(reason: Error): Promise<void> {
    ++this.epoch;
    ++this.intent;
    this.cancelAutomatic();
    this.automaticInFlight = undefined;
    const previous = this.connection;
    this.connection = { kind: "closed" };
    if (previous.kind === "opening") previous.controller.abort();
    this.rejectPending(reason);
    // The next session reports its own samples when it becomes active.
    this.samples = NO_SAMPLES;
    this.currentSource = null;
    this.acceptedVersion = null;
    this.latestAcceptedSourceId = 0;
    this.verdict = null;
    return this.retire(previous);
  }

  /** Closes a connection the player has already let go of. */
  private async retire(previous: Connection): Promise<void> {
    if (previous.kind === "open") await previous.session.close();
    else if (previous.kind === "opening") await previous.retirement();
  }
  private open(): Promise<AudioSession> {
    if (this.connection.kind === "open") return Promise.resolve(this.connection.session);
    if (this.connection.kind === "opening") return this.connection.promise;
    const epoch = ++this.epoch;
    const controller = new AbortController();
    // Called within the user's gesture, which a browser requires to start
    // audio; the engine lets a retiring session give way rather than wait.
    const raw = this.engine.openSession(event => {
      if (epoch === this.epoch) this.receive(event);
    }, controller.signal);
    let retirement: Promise<void> | undefined;
    const retireOpening = (): Promise<void> => {
      if (retirement !== undefined) return retirement;
      retirement = raw.then(async opened => {
        if (opened.kind === "opened") await opened.session.close();
      }, () => undefined);
      return retirement;
    };
    const promise = raw.then(async opened => {
      if (epoch !== this.epoch) throw new DOMException("Player closed during startup", "AbortError");
      if (opened.kind !== "opened") {
        throw new Error(opened.kind === "failed" ? opened.message : "Audio owner is busy");
      }
      // The worklet built its player for this format, so a player can run it.
      const running = playerWindow(opened.session.format);
      if (running.kind === "unsupported") throw new Error(`Worklet reported an unplayable format: ${running.message}`);
      this.connection = { kind: "open", session: opened.session };
      this.checkDraftWithin(running.window);
      this.render();
      return opened.session;
    }).catch(error => {
      if (epoch === this.epoch && !(error instanceof DOMException && error.name === "AbortError")) {
        this.fail(error instanceof Error ? error.message : String(error));
      } else if (epoch === this.epoch && this.connection.kind === "opening") {
        this.connection = { kind: "closed" };
        this.render();
      }
      throw error;
    });
    this.connection = { kind: "opening", promise, retirement: retireOpening, controller };
    this.render();
    return promise;
  }
  private send(operation: PlayerOperation, input?: PlaybackInput): Promise<PlayerReceipt> {
    if (input !== undefined) this.refreshDraft();
    if (this.connection.kind !== "open") return Promise.reject(new Error("Player is not open"));
    const session = this.connection.session;
    const id = this.next;
    this.next = id.next();
    return new Promise((resolve, reject) => {
      this.pending.set(id.value, { operation, input, resolve, reject });
      this.render();
      try {
        const result = operation === "update" ? session.update(id, input!)
          : operation === "restart" ? session.restart(id, input!)
          : operation === "play" ? session.play(id) : session.pause(id);
        if (result === "session-expired") {
          this.pending.delete(id.value);
          reject(new Error("Player session expired"));
          this.render();
        }
      } catch (error) {
        this.pending.delete(id.value);
        reject(error);
        this.render();
      }
    });
  }

  report(error: unknown): void {
    if (error instanceof Error && error.name === "AbortError") return;
    this.notice = error instanceof Error ? error.message : String(error);
    this.render();
  }
  /** Editing or preparing the draft failed: a program error, not a problem in the score. */
  reportDraftFailure(error: unknown): void {
    if (error instanceof Error && error.name === "AbortError") return;
    this.cancelAutomatic();
    this.refreshDraft();
    this.failedVersion = this.draftState.version;
    this.notice = error instanceof Error ? error.message : String(error);
    this.render();
  }
  private rejectPending(error: Error): void {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
  private fail(message: string): void {
    const retirement = this.endRun(new Error(message));
    this.snapshot = { ...this.snapshot, state: "Fault" };
    this.notice = message;
    this.render();
    void retirement.catch(error => this.report(error));
  }
  private receive(event: AudioEvent): void {
    if (event.kind === "failed") { this.fail(event.message); return; }
    if (event.kind === "status") { this.snapshot = event; this.render(); return; }
    if (event.kind === "samples") {
      const { kind: _, ...samples } = event;
      this.samples = samples;
      this.render();
      return;
    }
    const receipt = event.receipt;
    const pending = this.pending.get(receipt.id.value);
    if (!pending) return;
    this.pending.delete(receipt.id.value);
    if (receipt.operation !== pending.operation ||
        !sameDraftVersion(receipt.draftVersion, pending.input?.draftVersion ?? null)) {
      const error = new Error("Player receipt operation/version mismatch");
      pending.reject(error);
      this.fail(error.message);
      return;
    }
    if (receipt.id.value > this.lastReceipt) {
      this.lastReceipt = receipt.id.value;
      this.snapshot = receipt;
      if (receipt.kind === "rejected" && pending.input === undefined) {
        this.notice = receipt.message;
      }
    }
    if (pending.input !== undefined) {
      const version = pending.input.draftVersion;
      if (receipt.kind === "accepted" && receipt.id.value > this.latestAcceptedSourceId) {
        this.latestAcceptedSourceId = receipt.id.value;
        this.currentSource = pending.input.source;
        this.acceptedVersion = version;
      }
      const answered = this.verdict !== null && sameDraftVersion(this.verdict.version, version) ? this.verdict.receipt : 0;
      if (sameDraftVersion(version, this.draftState.version) && receipt.id.value > answered) {
        this.verdict = { version, receipt: receipt.id.value, refusal: receipt.kind === "rejected" ? { kind: "refused", message: receipt.message } : null };
        this.notice = null;
      }
    }
    pending.resolve(receipt);
    this.render();
  }
}
