// Audio-owner adapter. Snapshots stay in WASM; only text, tokens and receipts
// cross boundaries. Both browser worklets use the same playback protocol.
const APPLY_RESTART_REQUIRED = 2;

export class PlaybackController {
  constructor(wasm, post) {
    this.wasm = wasm;
    this.post = post;
    this.pending = null;
    this.active = null;
    this.tempoRevision = null;
  }

  // Numeric range alone cannot prove transport representability. Report the
  // runtime's result instead of letting its primitive setter fail silently.
  setTempo({ bpm, revision }) {
    if (typeof bpm !== "number" || !Number.isFinite(bpm) ||
        !Number.isSafeInteger(revision) || revision <= 0) {
      this.post({ type: "playback-error", phase: "protocol", revision, recovery: "edit", message: "invalid tempo request" });
      return;
    }
    const status = this.wasm.set_scheduler_bpm(bpm);
    this.tempoRevision = revision;
    const tempo = this.wasm.scheduler_bpm();
    this.post(status === 0
      ? { type: "tempo-updated", revision, tempo }
      : { type: "tempo-error", revision, tempo, message: this.errorMessage() });
  }

  errorMessage() {
    const codes = [];
    for (let i = 0; i < this.wasm.get_playback_error_length(); i++) {
      codes.push(this.wasm.get_playback_error_char(i));
    }
    return codes.map(code => String.fromCharCode(code)).join("") || "playback request failed";
  }

  handle(data) {
    if (data.type === "restart-playback") {
      if (this.wasm.restart_playback() !== 0) {
        this.post({ type: "playback-error", phase: "restart", revision: data.revision, recovery: "edit", message: this.errorMessage() });
      } else {
        this.replacePending({ type: "playback-restarted", revision: data.revision,
          operation: "restart", score: this.active });
      }
      return;
    }
    if (data.type !== "apply-score") return;
    const { mode, policy, revision, text } = data;
    if ((mode !== "pattern" && mode !== "song") ||
        (policy !== "continue" && policy !== "restart") || typeof text !== "string") {
      this.post({ type: "playback-error", phase: "protocol", revision, recovery: "edit", message: "invalid playback request" });
      return;
    }
    this.wasm.clear_playback_input();
    for (let i = 0; i < text.length; i++) this.wasm.push_playback_char(text.charCodeAt(i));
    const token = this.wasm[`prepare_${mode}_input`]();
    const status = token === 0 ? 1 : this.wasm.apply_prepared_playback(token, policy === "restart");
    if (status !== 0) {
      const message = this.errorMessage();
      if (token !== 0) this.wasm.discard_prepared_playback(token);
      this.post({ type: `${mode}-error`, phase: token === 0 ? "prepare" : "apply", revision, message,
        recovery: status === APPLY_RESTART_REQUIRED ? "restart" : "edit" });
      return;
    }
    this.replacePending({ type: `${mode}-updated`, revision,
      operation: policy === "continue" ? "update" : "restart", score: { mode, revision } });
  }

  replacePending(next) {
    if (this.pending) {
      this.post({ type: "playback-superseded", revision: this.pending.revision });
    }
    this.pending = next;
  }

  // A receipt acknowledges the request committed by the render at the
  // acceptance boundary. Read tempo after rendering so deferred song BPM
  // changes are reflected by the authoritative scheduler.
  didRender(blockSize) {
    if (!this.pending) return;
    const { score, ...reply } = this.pending;
    this.active = score;
    this.pending = null;
    const samplePosition = this.wasm.scheduler_sample_position();
    const tempo = this.wasm.scheduler_bpm();
    this.post({ ...reply, mode: score?.mode, scoreRevision: score?.revision,
      tempo, tempoRevision: this.tempoRevision, samplePosition, acceptedAtSample: samplePosition - blockSize });
  }
}
