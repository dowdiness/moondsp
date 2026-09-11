///|
/// Finite composition prototype: parser and queries run only in the Worker.
let wire : Array[Double] = []

///|
let error : @ref.Ref[String] = @ref.new("")

///|
pub fn prepare(source : String) -> Bool {
  wire.clear()
  error.val = ""
  let song = match @mini.parse_song(source) {
    Ok(song) => song
    Err(e) => {
      error.val = e
      return false
    }
  }
  let duration = song.duration()
  guard duration.num > 0L && duration.num <= 256L * duration.den else {
    error.val = "prototype duration must be within 256 beats"
    return false
  }
  let end = (duration.num * 24000L / duration.den).to_int()
  for sample = 0; sample < end; sample = sample + 128 {
    let arc = @pattern.TimeSpan(
      @pattern.Rational(sample.to_int64(), 24000L),
      @pattern.Rational((sample + 128).to_int64(), 24000L),
    )
    for event in song.query(arc) {
      match event.whole {
        Some(whole) =>
          if arc.contains(whole.begin) {
            guard wire.length() < 80000 else {
              error.val = "prototype event capacity"
              wire.clear()
              return false
            }
            let cm = event.value
            let mut supported = true
            cm.each(fn(key, _) {
              if key != "note" &&
                key != "sound" &&
                key != "gain" &&
                key != "pan" {
                supported = false
              }
            })
            guard supported else {
              error.val = "unsupported control"
              wire.clear()
              return false
            }
            wire.push(whole.begin.num.to_double())
            wire.push(whole.begin.den.to_double())
            wire.push(whole.end_.num.to_double())
            wire.push(whole.end_.den.to_double())
            wire.push(cm.get("note").unwrap_or(-1.0))
            wire.push(cm.get("sound").unwrap_or(-1.0))
            wire.push(cm.get("gain").unwrap_or(1.0))
            wire.push(cm.get("pan").unwrap_or(2.0))
          }
        None => ()
      }
    }
  }
  true
}

///|
pub fn length() -> Int {
  wire.length()
}

///|
pub fn value(i : Int) -> Double {
  wire[i]
}

///|
pub fn error_text() -> String {
  error.val
}

///|
fn main {
  ()
}
