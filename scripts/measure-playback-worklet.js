// Appended to the actual scheduler-processor.js module by measure-playback-api.cjs.
// Never imported by production pages. Storage is allocated before measurement.
class MeasuredSchedulerProcessor extends MoonDspSchedulerProcessor {
  constructor(options) {
    super(options);
    this.measureBlocks = new Float64Array(16384);
    this.measureGaps = new Float64Array(16384);
    this.measureUpdates = new Float64Array(256);
    this.measuring = false;
    this.measureBlockCount = 0;
    this.measureGapCount = 0;
    this.measureUpdateCount = 0;
    this.measurePreviousStart = null;
    this.measureBlockSize = 0;
  }

  dispatchCommand(data) {
    if (data.type === 'measurement-start') {
      this.measureBlockCount = 0;
      this.measureGapCount = 0;
      this.measureUpdateCount = 0;
      this.measurePreviousStart = null;
      this.measuring = true;
      this.port.postMessage({ type: 'measurement-started', id: data.id });
      return;
    }
    if (data.type === 'measurement-report') {
      this.measuring = false;
      this.port.postMessage({
        type: 'measurement-report', id: data.id,
        sampleRate, blockSize: this.measureBlockSize,
        overflow: this.measureBlockCount > this.measureBlocks.length ||
          this.measureGapCount > this.measureGaps.length ||
          this.measureUpdateCount > this.measureUpdates.length,
        blocks: Array.from(this.measureBlocks.subarray(0, this.measureBlockCount)),
        gaps: Array.from(this.measureGaps.subarray(0, this.measureGapCount)),
        updates: Array.from(this.measureUpdates.subarray(0, this.measureUpdateCount)),
      });
      return;
    }
    if (this.measuring && data.type === 'player-update') {
      const started = Date.now();
      try { super.dispatchCommand(data); }
      finally { this.measureUpdates[this.measureUpdateCount++] = Date.now() - started; }
    } else {
      super.dispatchCommand(data);
    }
  }

  process(inputs, outputs, parameters) {
    if (!this.measuring) return super.process(inputs, outputs, parameters);
    const started = Date.now();
    if (this.measurePreviousStart !== null) {
      this.measureGaps[this.measureGapCount++] = started - this.measurePreviousStart;
    }
    this.measurePreviousStart = started;
    this.measureBlockSize = outputs[0][0].length;
    try { return super.process(inputs, outputs, parameters); }
    finally { this.measureBlocks[this.measureBlockCount++] = Date.now() - started; }
  }
}

registerProcessor('measured-moondsp-scheduler', MeasuredSchedulerProcessor);
