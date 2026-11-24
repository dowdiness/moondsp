///|
/// A control the engine applies to a voice (ADR-0020 Decision 1). The set is
/// closed: text names a control only where it enters, in Mini's method names.
#derive(Eq, Debug)
pub(all) enum Control {
  /// MIDI note number. The scheduler sets it from a note's pitch at note-on;
  /// scores choose what to play with `@score.Sound`, never with a control
  /// (ADR-0022).
  Note
  Gain
  Pan
  /// Send level to the shared reverb.
  Room
  Lpf
  LpfResonance
  Hpf
  HpfResonance
  /// Seconds.
  Attack
  /// Seconds.
  Decay
  /// Level, 0 to 1.
  Sustain
  /// Seconds.
  Hold
  /// Where a sample starts, as a fraction of its waveform (0–1). Fixed at
  /// onset (ADR-0026 Decision 4).
  Begin
  /// Where a sample stops, as a fraction of its waveform (0–1). Fixed at
  /// onset.
  End
  /// A sample's playback-rate multiplier; a negative speed plays backwards.
  Speed
  /// The number of the sample a sampler voice plays. Like `Note`, the
  /// scheduler sets it from the event's sound at note-on and no score method
  /// names it (ADR-0026 Decision 1).
  SampleNumber
  /// Seconds.
  Release
}

///|
/// The name text uses for this control.
pub fn Control::name(self : Control) -> String {
  match self {
    Note => "note"
    Gain => "gain"
    Pan => "pan"
    Room => "room"
    Lpf => "lpf"
    LpfResonance => "lpf_resonance"
    Hpf => "hpf"
    HpfResonance => "hpf_resonance"
    Attack => "attack"
    Decay => "decay"
    Sustain => "sustain"
    Hold => "hold"
    Begin => "begin"
    End => "end"
    Speed => "speed"
    SampleNumber => "sample_number"
    Release => "release"
  }
}

///|
pub impl Show for Control with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
/// Maps keyed by `Control` hash its variant's position directly: a derived
/// hash runs the full `Hasher` and made those maps slower than `String`-keyed
/// ones on the pattern query path.
pub impl Hash for Control with fn hash(self) {
  match self {
    Note => 0
    Gain => 1
    Pan => 2
    Room => 3
    Lpf => 4
    LpfResonance => 5
    Hpf => 6
    HpfResonance => 7
    Attack => 8
    Decay => 9
    Sustain => 10
    Hold => 11
    Begin => 12
    End => 13
    Speed => 14
    SampleNumber => 15
    Release => 16
  }
}

///|
pub impl Hash for Control with fn hash_combine(self, hasher) {
  hasher.combine_int(Hash::hash(self))
}

///|
/// Every control, in declaration order. `Release` stays the last variant,
/// so its hash bounds this list (see the test).
pub fn Control::all() -> FixedArray[Control] {
  [
    Note,
    Gain,
    Pan,
    Room,
    Lpf,
    LpfResonance,
    Hpf,
    HpfResonance,
    Attack,
    Decay,
    Sustain,
    Hold,
    Begin,
    End,
    Speed,
    SampleNumber,
    Release,
  ]
}

///|
/// How nested occurrences of one control combine (ADR-0019, decision 8).
pub(all) enum Nesting {
  /// The outer value replaces the inner one.
  Override
  /// The outer value multiplies the inner one.
  Multiply
}

///|
/// The name text uses for this rule.
pub fn Nesting::name(self : Nesting) -> String {
  match self {
    Override => "override"
    Multiply => "multiply"
  }
}

///|
/// This control's nesting rule; the only place that names one.
pub fn Control::nesting(self : Control) -> Nesting {
  match self {
    Gain => Multiply
    Note
    | Pan
    | Room
    | Lpf
    | LpfResonance
    | Hpf
    | HpfResonance
    | Attack
    | Decay
    | Sustain
    | Hold
    | Begin
    | End
    | Speed
    | SampleNumber
    | Release => Override
  }
}

///|
/// Whether a sounding voice keeps following this control when its value
/// varies (ADR-0026 Decision 4); the only place that states it. A control
/// that does not follow keeps its onset value: moving where a sample starts
/// or stops, or which sample plays, would jump within or between waveforms.
pub fn Control::follows(self : Control) -> Bool {
  match self {
    Begin | End | SampleNumber => false
    Note
    | Gain
    | Pan
    | Room
    | Lpf
    | LpfResonance
    | Hpf
    | HpfResonance
    | Attack
    | Decay
    | Sustain
    | Hold
    | Speed
    | Release => true
  }
}

///|
/// The longest duration a seconds control (`attack`, `hold`, `release`) takes.
pub const MAX_SECONDS : Double = 86400.0

///|
/// Whether `value` lies in this control's domain; the only place that states
/// one. Mini checks it for the keys it parses with a range, and a voice where
/// it reads one it relies on (`hold`, `attack`). `NaN` is in no domain.
pub fn Control::admits(self : Control, value : Double) -> Bool {
  match self {
    Attack | Hold | Release => value >= 0.0 && value <= MAX_SECONDS
    Room | Begin | End => value >= 0.0 && value <= 1.0
    Speed => !value.is_nan() && !value.is_inf()
    LpfResonance | HpfResonance => value > 0.0 && !value.is_inf()
    Note | Gain | Pan | Lpf | Hpf | Decay | Sustain => !value.is_nan()
    SampleNumber => value >= 0.0 && value == value.floor() && !value.is_inf()
  }
}
