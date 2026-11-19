///|
/// A control the engine applies to a voice (ADR-0020 Decision 1). The set is
/// closed: text names a control only where it enters, in Mini's method names.
#derive(Eq, Debug)
pub(all) enum Control {
  /// MIDI note number.
  Note
  /// MIDI drum number.
  Sound
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
  /// Seconds.
  Release
}

///|
/// The name text uses for this control.
pub fn Control::name(self : Control) -> String {
  match self {
    Note => "note"
    Sound => "sound"
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
    Sound => 1
    Gain => 2
    Pan => 3
    Room => 4
    Lpf => 5
    LpfResonance => 6
    Hpf => 7
    HpfResonance => 8
    Attack => 9
    Decay => 10
    Sustain => 11
    Hold => 12
    Release => 13
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
    Sound,
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
    | Sound
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
    | Release => Override
  }
}
