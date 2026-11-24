///|
/// A drum, played with `s("name")`. Other packages can match it but not
/// construct it, so `all` is the only place that constructs each drum: one
/// missing from `all` fails `moon check --deny-warn` with `unused_constructor`.
#derive(Eq, Debug)
pub enum Drum {
  Bd
  Sd
  Cp
  Hh
  Oh
}

///|
pub extend Drum with Eq::{not_equal, equal}

///|
pub extend Drum with Debug::{to_repr}

///|
/// Every drum, so a host can give each one a voice pool. Keep this the only
/// expression in the package that constructs a `Drum`.
pub fn Drum::all() -> Array[Drum] {
  [Bd, Sd, Cp, Hh, Oh]
}

///|
pub fn Drum::name(self : Drum) -> String {
  match self {
    Bd => "bd"
    Sd => "sd"
    Cp => "cp"
    Hh => "hh"
    Oh => "oh"
  }
}

///|
/// What the drum is, for people choosing one.
pub fn Drum::description(self : Drum) -> String {
  match self {
    Bd => "kick drum"
    Sd => "snare drum"
    Cp => "hand clap"
    Hh => "closed hi-hat"
    Oh => "open hi-hat"
  }
}

///|
pub fn Drum::parse(name : String) -> Drum? {
  Drum::all().iter().find_first(drum => drum.name() == name)
}

///|
/// An instrument that plays pitches, chosen with `.s("name")`. Constructed
/// only by `all`, as for `Drum`.
#derive(Eq, Debug)
pub enum Instrument {
  Triangle
  Bass
  Pad
  Pluck
  Sawtooth
}

///|
pub extend Instrument with Eq::{not_equal, equal}

///|
pub extend Instrument with Debug::{to_repr}

///|
/// Every instrument, the default first, so a host can give each one a voice
/// pool. Keep this the only expression in the package that constructs an
/// `Instrument`.
pub fn Instrument::all() -> Array[Instrument] {
  [Triangle, Bass, Pad, Pluck, Sawtooth]
}

///|
/// The instrument a note plays without `.s`.
pub fn Instrument::default() -> Instrument {
  Instrument::all()[0]
}

///|
pub fn Instrument::name(self : Instrument) -> String {
  match self {
    Triangle => "triangle"
    Bass => "bass"
    Pad => "pad"
    Pluck => "pluck"
    Sawtooth => "sawtooth"
  }
}

///|
/// What the instrument plays, for people choosing one.
pub fn Instrument::description(self : Instrument) -> String {
  match self {
    Triangle => "soft triangle tone"
    Bass => "bass line"
    Pad => "slow-swelling pad"
    Pluck => "short plucked note"
    Sawtooth => "bright sawtooth lead"
  }
}

///|
pub fn Instrument::parse(name : String) -> Instrument? {
  Instrument::all().iter().find_first(instrument => instrument.name() == name)
}

///|
/// A recorded sample of the built-in bank (ADR-0026). Constructed only by
/// `all`, as for `Drum`. The bank's material is generated in code until
/// recordings with an approved licence replace it.
#derive(Eq, Debug)
pub enum Sample {
  Ping
  Burst
}

///|
pub extend Sample with Eq::{not_equal, equal}

///|
pub extend Sample with Debug::{to_repr}

///|
/// Every sample, in sample-number order: a host registers each one's
/// waveform under its position here. Keep this the only expression in the
/// package that constructs a `Sample`.
pub fn Sample::all() -> Array[Sample] {
  [Ping, Burst]
}

///|
pub fn Sample::name(self : Sample) -> String {
  match self {
    Ping => "ping"
    Burst => "burst"
  }
}

///|
/// What the sample sounds like, for people choosing one.
pub fn Sample::description(self : Sample) -> String {
  match self {
    Ping => "decaying sine ping"
    Burst => "short noise burst"
  }
}

///|
/// The sample's number in a host's sample store: its position in `all`.
/// A match, so the audio thread reads it without building `all`.
pub fn Sample::number(self : Sample) -> Int32 {
  match self {
    Ping => 0
    Burst => 1
  }
}

///|
/// The MIDI pitch the sample was recorded at, which `s("name")` plays it at.
/// A host registers the sample's waveform with this root.
pub fn Sample::root_pitch(self : Sample) -> Double {
  match self {
    Ping => 69.0
    Burst => 60.0
  }
}

///|
pub fn Sample::parse(name : String) -> Sample? {
  Sample::all().iter().find_first(sample => sample.name() == name)
}

///|
/// What a score event plays: a drum hit, an instrument note at a pitch (a
/// MIDI note number), or a recorded sample at a pitch; a sample plays as
/// recorded at its `root_pitch` (ADR-0026 Decision 3).
#derive(Eq, Debug)
pub(all) enum Sound {
  Hit(Drum)
  Note(Instrument, pitch~ : Double)
  Play(Sample, pitch~ : Double)
}

///|
pub extend Sound with Eq::{not_equal, equal}

///|
pub extend Sound with Debug::{to_repr}

///|
/// Describes the sound for pattern content: equal content, equal sound.
pub fn Sound::content(self : Sound) -> String {
  match self {
    Hit(drum) => "hit:\{drum.name()}"
    Note(instrument, pitch~) => "note:\{instrument.name()}:\{pitch}"
    Play(sample, pitch~) => "play:\{sample.name()}:\{pitch}"
  }
}
