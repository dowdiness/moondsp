///|
const MAX_GATE_FACTOR_DENOMINATOR = 1000000000L

///|
/// Shorten each discrete event to a fraction of its authored duration without
/// moving its onset or changing the pattern period. Factors below zero become
/// zero; factors above one become one. Fractions finer than one billionth are
/// rounded to keep later-cycle endpoints representable. Continuous events are
/// unchanged.
pub fn[A] Pat::gate(self : Pat[A], factor : Rational) -> Pat[A] {
  guard !(self.body is Silence) else { return self }
  let factor = normalize_gate_factor(factor)
  let inner = self
  let children = self.transform_children(pat => pat.gate(factor))
  make_pat(
    fn(arc) { inner.query(arc).filter_map(event => gate_event(event, factor)) },
    self.metadata.period,
    Opaque(children),
    self.metadata.scope,
    transformed_signature(
      self.entry_signature(),
      "gate:\{factor.num}:\{factor.den}",
    ),
  )
}

///|
fn normalize_gate_factor(factor : Rational) -> Rational {
  let zero = Rational::from_int(0)
  let one = Rational::from_int(1)
  let factor = if factor < zero {
    zero
  } else if factor > one {
    one
  } else {
    factor
  }
  if factor.den <= MAX_GATE_FACTOR_DENOMINATOR {
    factor
  } else {
    Rational::new(
      (factor.to_double() * MAX_GATE_FACTOR_DENOMINATOR.to_double() + 0.5).to_int64(),
      MAX_GATE_FACTOR_DENOMINATOR,
    )
  }
}

///|
fn[A] gate_event(event : Event[A], factor : Rational) -> Event[A]? {
  match event.whole {
    None => Some(event)
    Some(whole) => {
      let gated_whole = TimeSpan::new(
        whole.begin,
        whole.begin + whole.duration() * factor,
      )
      gated_whole
      .intersect(event.part)
      .map(part => { whole: Some(gated_whole), part, value: event.value, })
    }
  }
}
