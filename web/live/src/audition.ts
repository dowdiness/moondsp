import { AudioEngine } from "./audio";
import { Draft, PlaybackInput } from "./authoring";
import { Player } from "./playback";

export type AuditionState = { kind: "idle" | "loading" | "playing" } | { kind: "error"; message: string };
type Request = { report: (state: AuditionState) => void; timer?: number | NodeJS.Timeout };

/** A separate Player owns preview audio; it never submits to the score's transport. */
export class Audition {
  private readonly draft = new Draft("");
  private readonly player: Player;
  private current: Request | undefined;
  private latest: Request | undefined;
  private disposed = false;

  constructor(engine: Pick<AudioEngine, "openSession"> = new AudioEngine()) {
    this.player = new Player(engine, { draft: this.draft }, state => {
      if (state.state === "Fault" && this.current) {
        this.finish(this.current, { kind: "error", message: state.feedback?.message ?? "Preview audio failed" });
      }
    });
  }

  play(source: string, report: (state: AuditionState) => void): void {
    if (this.disposed) {
      this.notify(report, { kind: "error", message: "Audition is disposed" });
      return;
    }
    this.stop();
    const request: Request = { report };
    this.current = this.latest = request;
    this.notify(report, { kind: "loading" });
    // Player serializes retirement, cancels stale opens, and validates receipts.
    void this.player.restart(PlaybackInput.text(source)).then(receipt => {
      if (this.current !== request) return;
      if (receipt.kind !== "accepted") {
        this.finish(request, { kind: "error", message: receipt.message });
        return;
      }
      this.notify(report, { kind: "playing" });
      request.timer = setTimeout(() => this.finish(request, { kind: "idle" }), 700);
    }).catch(error => {
      if (this.current === request) this.finish(request, { kind: "error", message: this.message(error) });
    });
  }

  stop(): void {
    if (this.current) this.finish(this.current, { kind: "idle" });
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.stop();
    void this.player.close().finally(() => this.draft.dispose()).catch(error => {
      console.warn("Preview audio disposal failed", error);
    });
  }

  private finish(request: Request, state: AuditionState): void {
    if (this.current !== request) return;
    this.current = undefined;
    clearTimeout(request.timer);
    void this.player.close().catch(error => {
      if (this.latest === request && !this.disposed) {
        this.notify(request.report, { kind: "error", message: this.message(error) });
      }
    });
    this.notify(request.report, state);
  }

  private message(error: unknown): string { return error instanceof Error ? error.message : String(error); }

  private notify(report: (state: AuditionState) => void, state: AuditionState): void {
    try { report(state); } catch (error) { console.warn("Preview status callback failed", error); }
  }
}
