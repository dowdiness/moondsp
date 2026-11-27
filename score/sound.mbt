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
/// `all`, as for `Drum`. `ping` and `burst` are generated in code; the others
/// are recordings from the Versilian Community Sample Library (CC0), named
/// after their instrument and their measured root (`fs5` is F#5).
#derive(Eq, Debug)
pub enum Sample {
  Ping
  Burst
  PianoC2
  PianoC4
  PianoC6
  UprightA4
  MbiraE3
  MbiraB4
  MbiraFs5
  KalimbaCs5
  KalimbaG5
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
  [
    Ping,
    Burst,
    PianoC2,
    PianoC4,
    PianoC6,
    UprightA4,
    MbiraE3,
    MbiraB4,
    MbiraFs5,
    KalimbaCs5,
    KalimbaG5,
  ]
}

///|
pub fn Sample::name(self : Sample) -> String {
  match self {
    Ping => "ping"
    Burst => "burst"
    PianoC2 => "piano_c2"
    PianoC4 => "piano_c4"
    PianoC6 => "piano_c6"
    UprightA4 => "upright_a4"
    MbiraE3 => "mbira_e3"
    MbiraB4 => "mbira_b4"
    MbiraFs5 => "mbira_fs5"
    KalimbaCs5 => "kalimba_cs5"
    KalimbaG5 => "kalimba_g5"
  }
}

///|
/// What the sample sounds like, for people choosing one.
pub fn Sample::description(self : Sample) -> String {
  match self {
    Ping => "decaying sine ping"
    Burst => "short noise burst"
    PianoC2 => "grand piano, C2"
    PianoC4 => "grand piano, C4"
    PianoC6 => "grand piano, C6"
    UprightA4 => "upright piano, A4"
    MbiraE3 => "mbira, E3"
    MbiraB4 => "mbira, B4"
    MbiraFs5 => "mbira, F#5"
    KalimbaCs5 => "kalimba, C#5"
    KalimbaG5 => "kalimba, G5"
  }
}

///|
/// The sample's number in a host's sample store: its position in `all`.
/// A match, so the audio thread reads it without building `all`.
pub fn Sample::number(self : Sample) -> Int32 {
  match self {
    Ping => 0
    Burst => 1
    PianoC2 => 2
    PianoC4 => 3
    PianoC6 => 4
    UprightA4 => 5
    MbiraE3 => 6
    MbiraB4 => 7
    MbiraFs5 => 8
    KalimbaCs5 => 9
    KalimbaG5 => 10
  }
}

///|
/// The MIDI pitch the sample was recorded at, which `s("name")` plays it at.
/// A host registers the sample's waveform with this root.
pub fn Sample::root_pitch(self : Sample) -> Double {
  match self {
    Ping => 69.0
    Burst => 60.0
    PianoC2 => 36.0
    PianoC4 => 60.0
    PianoC6 => 84.0
    UprightA4 => 69.0
    MbiraE3 => 52.0
    MbiraB4 => 71.0
    MbiraFs5 => 78.0
    KalimbaCs5 => 73.0
    KalimbaG5 => 79.0
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
