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
pub fn Drum::parse(name : String) -> Drum? {
  Drum::all().iter().find_first(drum => drum.name() == name)
}

///|
/// An instrument that plays pitches. Constructed only by `all`, as for
/// `Drum`.
#derive(Eq, Debug)
pub enum Instrument {
  Triangle
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
  [Triangle]
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
  }
}

///|
/// What a score event plays: a drum hit, or an instrument note at a pitch
/// (a MIDI note number).
#derive(Eq, Debug)
pub(all) enum Sound {
  Hit(Drum)
  Note(Instrument, pitch~ : Double)
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
  }
}
