///|
pub(all) suberror TransportError {
  InvalidTempo
  InvalidSampleRate
  TimeOutOfRange
} derive(Eq, Debug)

///|
/// Exact millibeats per minute, rounded to nearest (ties upward) on input.
/// Supported range: 0.001 through 1000 BPM.
pub struct Tempo {
  priv milli : Int64
} derive(Eq, Debug)

///|
pub fn Tempo::from_bpm(bpm : Double) -> Result[Tempo, TransportError] {
  if bpm.is_nan() || bpm.is_inf() || bpm < 0.001 || bpm > 1000.0 {
    Err(InvalidTempo)
  } else {
    Ok({ milli: (bpm * 1000.0 + 0.5).to_int64(), })
  }
}

///|
pub fn Tempo::bpm(self : Tempo) -> Double {
  self.milli.to_double() / 1000.0
}

///|
/// One affine segment anchored at the next unrendered sample. Position ticks
/// use sample_rate * 60000 per cycle, so edits do not accumulate denominators.
pub struct Clock {
  priv sample : Int64
  priv ticks : Int64
  priv scale : Int64
  priv tempo : Tempo
} derive(Eq, Debug)

///|
pub fn Clock::at_start(
  tempo : Tempo,
  sample_rate : Double,
) -> Result[Clock, TransportError] {
  if sample_rate.is_nan() ||
    sample_rate.is_inf() ||
    sample_rate < 1.0 ||
    sample_rate > 384000.0 ||
    sample_rate.to_int64().to_double() != sample_rate {
    return Err(InvalidSampleRate)
  }
  Ok({ sample: 0L, ticks: 0L, scale: sample_rate.to_int64() * 60000L, tempo, })
}

///|
fn checked_add(a : Int64, b : Int64) -> Int64 raise TransportError {
  if (b > 0L && a > 9223372036854775807L - b) ||
    (b < 0L && a < -9223372036854775807L - b) {
    raise TimeOutOfRange
  }
  a + b
}

///|
fn checked_mul(a : Int64, b : Int64) -> Int64 raise TransportError {
  // Exclude Int64::min so abs and negation are representable.
  if a == -9223372036854775807L - 1L || b == -9223372036854775807L - 1L {
    raise TimeOutOfRange
  }
  let aa = if a < 0L { -a } else { a }
  let bb = if b < 0L { -b } else { b }
  if bb != 0L && aa > 9223372036854775807L / bb {
    raise TimeOutOfRange
  }
  a * b
}

///|
fn gcd(a : Int64, b : Int64) -> Int64 {
  for a = a, b = b; b != 0L; {
    continue b, a % b
  } nobreak {
    a
  }
}

///|
pub fn Clock::tempo(self : Clock) -> Tempo {
  self.tempo
}

///|
pub fn Clock::sample(self : Clock) -> Int64 {
  self.sample
}

///|
fn Clock::ticks_at(self : Clock, sample : Int64) -> Int64 raise TransportError {
  if sample < 0L {
    raise TimeOutOfRange
  }
  checked_add(self.ticks, checked_mul(sample - self.sample, self.tempo.milli))
}

///|
pub fn Clock::position(
  self : Clock,
  sample : Int64,
) -> Result[@pattern.Rational, TransportError] {
  Ok(@pattern.Rational::new(self.ticks_at(sample), self.scale)) catch {
    e => Err(e)
  }
}

///|
pub fn Clock::advance(
  self : Clock,
  count : Int,
) -> Result[Clock, TransportError] {
  try {
    if count < 0 {
      raise TimeOutOfRange
    }
    let sample = checked_add(self.sample, count.to_int64())
    let ticks = self.ticks_at(sample)
    Ok({ ..self, sample, ticks, })
  } catch {
    e => Err(e)
  }
}

///|
pub fn Clock::with_tempo(self : Clock, tempo : Tempo) -> Clock {
  { ..self, tempo, }
}

///|
pub fn Clock::reset(self : Clock) -> Clock {
  { ..self, sample: 0L, ticks: 0L, }
}

///|
/// Convert on the current affine segment, including endpoints of existing
/// notes. Cancel common factors before checked multiplication; never wrap.
pub fn Clock::sample_at(
  self : Clock,
  position : @pattern.Rational,
) -> Result[Int64, TransportError] {
  try {
    if position.den <= 0L || position.num == -9223372036854775807L - 1L {
      raise TimeOutOfRange
    }
    let g = gcd(self.scale, position.den)
    let den = position.den / g
    let num = checked_add(
      checked_mul(position.num, self.scale / g),
      -checked_mul(self.ticks, den),
    )
    let abs_num = if num < 0L { -num } else { num }
    let cancel = gcd(abs_num, self.tempo.milli)
    let numerator = num / cancel
    let denominator = checked_mul(den, self.tempo.milli / cancel)
    let quotient = numerator / denominator
    let ceil = if numerator % denominator > 0L {
      quotient + 1L
    } else {
      quotient
    }
    Ok(checked_add(self.sample, ceil))
  } catch {
    e => Err(e)
  }
}
