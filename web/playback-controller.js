// Audio-owner adapter for the unified source/player ABI. All replies are
// immediate owner receipts; render is only used to refresh diagnostics.
const RESTART_REQUIRED = 2;
// Mirror Mini's admission bound at transport ingress, before per-character FFI.
// MoonBit still enforces the same limit for callers that bypass this adapter.
const MAX_SOURCE_CODE_UNITS = 8192;

export class PlaybackController {
  constructor(wasm, post) {
    this.wasm = wasm;
    this.post = post;
  }

  errorMessage() {
    const codes = [];
    for (let i = 0; i < this.wasm.get_playback_error_length(); i++) {
      codes.push(this.wasm.get_playback_error_char(i));
    }
    return codes.map(code => String.fromCharCode(code)).join("") || "playback request failed";
  }

  snapshot() {
    return {
      state: this.wasm.player_state(),
      samplePosition: this.wasm.scheduler_sample_position(),
      tempo: this.wasm.scheduler_bpm(),
      pendingCount: this.wasm.player_pending_count(),
      skippedCount: this.wasm.player_skipped_count(),
    };
  }

  receipt(id, operation, status, message) {
    const snapshot = this.snapshot();
    this.post({ type: "player-receipt", id, operation, accepted: status === 0,
      restartRequired: status === RESTART_REQUIRED, message, ...snapshot });
  }

  update(data, restart) {
    if (typeof data.text !== "string" || data.text.length > MAX_SOURCE_CODE_UNITS) {
      this.receipt(data.id, restart ? "restart" : "update", 1,
        typeof data.text !== "string" ? "invalid source payload" : "playback source exceeds 8192 characters");
      return;
    }
    this.wasm.clear_playback_input();
    for (let i = 0; i < data.text.length; i++) this.wasm.push_playback_char(data.text.charCodeAt(i));
    const status = this.wasm[restart ? "player_restart_input" : "player_update_input"]();
    this.receipt(data.id, restart ? "restart" : "update", status, status === 0 ? "" : this.errorMessage());
  }

  handle(data) {
    if (!data || typeof data !== "object") return;
    if ((data.type === "player-update" || data.type === "player-restart" ||
         data.type === "player-play" || data.type === "player-pause") &&
        (!Number.isSafeInteger(data.id) || data.id <= 0)) {
      this.post({ type: "error", message: "invalid Player request id" });
      return;
    }
    switch (data.type) {
      case "player-update": this.update(data, false); break;
      case "player-restart": this.update(data, true); break;
      case "player-play": {
        const status = this.wasm.player_play();
        this.receipt(data.id, "play", status, status === 0 ? "" : this.errorMessage());
        break;
      }
      case "player-pause": {
        const status = this.wasm.player_pause();
        this.receipt(data.id, "pause", status, status === 0 ? "" : this.errorMessage());
        break;
      }
      case "set-scheduler-bpm": {
        const status = this.wasm.set_scheduler_bpm(data.bpm);
        this.post(status === 0
          ? { type: "tempo-updated", revision: data.revision, tempo: this.wasm.scheduler_bpm() }
          : { type: "tempo-error", revision: data.revision, tempo: this.wasm.scheduler_bpm(), message: this.errorMessage() });
        break;
      }
    }
  }

}
