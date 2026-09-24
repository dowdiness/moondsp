// Audio-owner adapter for the unified source/player ABI. All replies are
// immediate owner receipts; render is only used to refresh diagnostics.
const RESTART_REQUIRED = 2;
const MAX_WIRE_CODE_UNITS = 2097152;
const PLAYBACK_STATES = ["Empty", "Ready", "Playing", "Paused", "Ended", "Fault"];
const PLAYBACK_MODES = ["none", "pattern", "song"];

function decodeAbiValue(value, values) {
  return Number.isInteger(value) && value >= 0 && value < values.length ? values[value] : undefined;
}

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
      state: decodeAbiValue(this.wasm.player_state(), PLAYBACK_STATES),
      mode: decodeAbiValue(this.wasm.player_mode(), PLAYBACK_MODES),
      cyclePosition: this.wasm.scheduler_cycle_position(),
      samplePosition: this.wasm.scheduler_sample_position(),
      tempo: this.wasm.scheduler_bpm(),
      pendingCount: this.wasm.player_pending_count(),
      skippedCount: this.wasm.player_skipped_count(),
    };
  }

  receipt(id, operation, status, message, draftVersion = null) {
    const snapshot = this.snapshot();
    this.post({ type: "player-receipt", id, operation, accepted: status === 0,
      restartRequired: status === RESTART_REQUIRED, message, draftVersion, ...snapshot });
  }

  validateWire(wire) {
    if (typeof wire !== "string") return { error: "invalid playback input payload" };
    if (wire.length > MAX_WIRE_CODE_UNITS) return { error: "playback input exceeds 2097152 UTF-16 code units" };
    for (let i = 0; i < wire.length; i++) {
      const code = wire.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff) {
        if (i + 1 >= wire.length || wire.charCodeAt(i + 1) < 0xdc00 || wire.charCodeAt(i + 1) > 0xdfff) {
          return { error: "invalid UTF-16 surrogate pair" };
        }
        i++;
      } else if (code >= 0xdc00 && code <= 0xdfff) {
        return { error: "invalid UTF-16 surrogate pair" };
      }
    }
    let envelope;
    try { envelope = JSON.parse(wire); } catch (_) { return { error: "invalid playback input wire" }; }
    if (!envelope || typeof envelope !== "object" || envelope.schema !== 1 ||
        !["pattern", "song", "text"].includes(envelope.kind) || typeof envelope.text !== "string") {
      return { error: "invalid playback input header" };
    }
    if (envelope.kind === "text") {
      if (Object.prototype.hasOwnProperty.call(envelope, "version") ||
          Object.prototype.hasOwnProperty.call(envelope, "sourceMap")) {
        return { error: "text playback input cannot carry draft metadata" };
      }
      return { wire, version: null };
    }
    if (!Array.isArray(envelope.version) || envelope.version.length !== 2 ||
        !Number.isSafeInteger(envelope.version[0]) || envelope.version[0] <= 0 ||
        !Number.isSafeInteger(envelope.version[1]) || envelope.version[1] < 0) {
      return { error: "invalid playback draft version" };
    }
    return { wire, version: envelope.version };
  }

  update(data, restart) {
    const operation = restart ? "restart" : "update";
    const checked = this.validateWire(data.input);
    if (checked.error) {
      this.receipt(data.id, operation, 1, checked.error);
      return;
    }
    this.wasm.clear_playback_input();
    for (let i = 0; i < checked.wire.length; i++) this.wasm.push_playback_char(checked.wire.charCodeAt(i));
    const status = this.wasm[restart ? "player_restart_input" : "player_update_input"]();
    this.receipt(data.id, operation, status, status === 0 ? "" : this.errorMessage(), checked.version);
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
