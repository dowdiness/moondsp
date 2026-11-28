// The AudioWorklet reads observations as flat rows of doubles
// (`web/playback-observations.js`). Counting a kind encodes the player's
// typed observations into these preallocated rows; the field readers return
// them. An observation whose ids or sample a JavaScript number cannot hold
// exactly is left out and counted as dropped.

///|
const WIRE_CAPACITY : Int32 = 256

///|
/// `[sample, epoch, atom serial, frame serial, local start, pitch, binding
/// count, then reference/binding/definition serial triples]`.
const ONSET_ROW_WIDTH : Int32 = 103

///|
const ONSET_MAX_BINDINGS : Int32 = 32

///|
/// `[sample, source epoch, source serial, material time in cycles, value]`.
const SIGNAL_ROW_WIDTH : Int32 = 5

///|
/// Encoded rows of one kind, and how many observations it left out.
priv struct WireRows {
  rows : Array[Double]
  mut count : Int32
  mut left_out : Int32
}

///|
let onset_wire : WireRows = {
  rows: Array::make(WIRE_CAPACITY * ONSET_ROW_WIDTH, 0.0),
  count: 0,
  left_out: 0,
}

///|
let signal_wire : WireRows = {
  rows: Array::make(WIRE_CAPACITY * SIGNAL_ROW_WIDTH, 0.0),
  count: 0,
  left_out: 0,
}

///|
fn WireRows::reset(self : WireRows) -> Unit {
  self.count = 0
  self.left_out = 0
}

///|
fn is_wire_safe(value : Int64) -> Bool {
  value >= 0L && value <= 9007199254740991L
}

///|
/// Encode `onsets` into `onset_wire`.
fn encode_onsets(onsets : @player.Onsets) -> Unit {
  onset_wire.reset()
  for index in 0..<onsets.count() {
    if encode_onset(
        onset_wire.count,
        onsets.sample(index),
        onsets.source(index),
      ) {
      onset_wire.count += 1
    } else {
      onset_wire.left_out += 1
    }
  }
}

///|
/// Write the onset of `source` at `sample` as row `row`; false, writing no
/// field, when the wire cannot carry it. A missing frame is serial 0 with
/// start -1, and a drum hit has no pitch, which is NaN.
fn encode_onset(
  row : Int32,
  sample : Int64,
  source : @pattern.EventWithOrigin[@score.ScoreEvent],
) -> Bool {
  let origin = source.origin()
  let epoch = origin.atom().epoch()
  guard is_wire_safe(sample) &&
    is_wire_safe(epoch.serial()) &&
    is_wire_safe(origin.atom().serial()) else {
    return false
  }
  if source.source_frame() is Some(frame) &&
    (frame.epoch() != epoch || !is_wire_safe(frame.serial())) {
    return false
  }
  let rows = onset_wire.rows
  let base = row * ONSET_ROW_WIDTH
  let bindings = origin.write_binding_serials(
    rows,
    base + 7,
    ONSET_MAX_BINDINGS,
  )
  guard bindings >= 0 else { return false }
  rows[base] = sample.to_double()
  rows[base + 1] = epoch.serial().to_double()
  rows[base + 2] = origin.atom().serial().to_double()
  match source.source_frame() {
    Some(frame) => {
      rows[base + 3] = frame.serial().to_double()
      rows[base + 4] = source.source_start()
    }
    None => {
      rows[base + 3] = 0.0
      rows[base + 4] = -1.0
    }
  }
  rows[base + 5] = match source.event().value.sound {
    Note(_, pitch~) | Play(_, pitch~) => pitch
    Hit(_) => @double.not_a_number
  }
  rows[base + 6] = bindings.to_double()
  true
}

///|
/// Field `field` of encoded onset row `index`; 0 outside the row.
fn onset_field(index : Int32, field : Int32) -> Double {
  guard index >= 0 &&
    index < onset_wire.count &&
    field >= 0 &&
    field < ONSET_ROW_WIDTH else {
    return 0.0
  }
  let base = index * ONSET_ROW_WIDTH
  guard field < 7 || field < 7 + onset_wire.rows[base + 6].to_int() * 3 else {
    return 0.0
  }
  onset_wire.rows[base + field]
}

///|
/// Encode `signals` into `signal_wire`.
fn encode_signals(signals : @player.SignalValues) -> Unit {
  signal_wire.reset()
  for index in 0..<signals.count() {
    let sample = signals.sample(index)
    let signal = signals.signal(index)
    guard is_wire_safe(sample) &&
      is_wire_safe(signal.epoch().serial()) &&
      is_wire_safe(signal.serial()) else {
      signal_wire.left_out += 1
      continue
    }
    let base = signal_wire.count * SIGNAL_ROW_WIDTH
    signal_wire.rows[base] = sample.to_double()
    signal_wire.rows[base + 1] = signal.epoch().serial().to_double()
    signal_wire.rows[base + 2] = signal.serial().to_double()
    signal_wire.rows[base + 3] = signals.material(index)
    signal_wire.rows[base + 4] = signals.value(index)
    signal_wire.count += 1
  }
}

///|
/// Field `field` of encoded signal row `index`; 0 outside the row.
fn signal_field(index : Int32, field : Int32) -> Double {
  guard index >= 0 &&
    index < signal_wire.count &&
    field >= 0 &&
    field < SIGNAL_ROW_WIDTH else {
    return 0.0
  }
  signal_wire.rows[index * SIGNAL_ROW_WIDTH + field]
}
