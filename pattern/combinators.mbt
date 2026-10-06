///|
priv struct SequenceSlot {
  index : Rational
  begin : Rational
  end_ : Rational
}

///|
pub fn[A] sequence(pats : Array[Pat[A]]) -> Pat[A] {
  let n = pats.length()
  if n == 0 {
    return Pat::silence()
  }
  let pats = pats.copy()
  let n_rat = Rational::from_int(n)
  let one = Rational::from_int(1)
  let slots : Array[SequenceSlot] = Array::makei(n, i => {
    let i_rat = Rational::from_int(i)
    { index: i_rat, begin: i_rat / n_rat, end_: (i_rat + one) / n_rat, }
  })
  // Every complete slot maps to [0,1), independent of its index and cycle.
  let full_pat_arc = TimeSpan::new(Rational::from_int(0), one)
  make_pat(
    fn(arc) {
      let result : Array[Event[A]] = []
      let cycles = arc.whole_cycles()
      for cycle_arc in cycles {
        // Determine the full cycle start from cycle_arc.begin
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        for i in 0..<n {
          let slot = slots[i]
          let i_rat = slot.index
          // Slot arc within the cycle: [i/n, (i+1)/n) + cycle_start
          let slot_begin = cycle_start + slot.begin
          let slot_end = cycle_start + slot.end_
          let slot_arc = TimeSpan::new(slot_begin, slot_end)
          // Intersect slot with the original query arc
          let query_intersect = match slot_arc.intersect(arc) {
            Some(ts) => ts
            None => continue
          }
          // To query the i-th pattern: compress slot time by n and offset back to [0,1) cycle space.
          // A time t in the slot maps to: (t - cycle_start) * n - i
          // Scale the intersected query arc into pattern time
          let pat_begin = (query_intersect.begin - cycle_start) * n_rat - i_rat
          let pat_end = (query_intersect.end_ - cycle_start) * n_rat - i_rat
          let query_pat_arc = TimeSpan::new(pat_begin, pat_end)
          // Capture i by value to avoid closure capture-by-reference issue
          let i_val = i
          let pat = pats[i_val]
          let events = pat.query(full_pat_arc)
          for ev in events {
            // Intersect event part (in pattern space) with the query pat arc
            let ev_part_clipped = match ev.part.intersect(query_pat_arc) {
              Some(ts) => ts
              None => continue
            }
            // Map part back to original time: t_orig = (t_pat + i) / n + cycle_start
            let part_begin_orig = (ev_part_clipped.begin + i_rat) / n_rat +
              cycle_start
            let part_end_orig = (ev_part_clipped.end_ + i_rat) / n_rat +
              cycle_start
            let new_part = TimeSpan::new(part_begin_orig, part_end_orig)
            let new_whole = match ev.whole {
              Some(w) => {
                let wb = (w.begin + i_rat) / n_rat + cycle_start
                let we = (w.end_ + i_rat) / n_rat + cycle_start
                Some(TimeSpan::new(wb, we))
              }
              None => None
            }
            result.push({ whole: new_whole, part: new_part, value: ev.value, })
          }
        }
      }
      result
    },
    one,
    Opaque([]),
    Anonymous,
    combine_signature("sequence", pats),
  )
}

///|
priv struct RelativeSequenceSlot {
  begin : Rational
  end_ : Rational
  duration : Rational
}

///|
/// Sequence patterns whose positive integer weights determine their cycle shares.
/// Each child sees its complete [0, 1) pattern cycle over its entire slot.
/// Weights must be 1–16 and their sum at most 256; invalid inputs yield silence.
pub fn[A] sequence_weighted(
  pats : Array[Pat[A]],
  weights : Array[Int],
) -> Pat[A] {
  let n = pats.length()
  guard n > 0 && n == weights.length() else { return Pat::silence() }
  let mut total = 0
  for weight in weights {
    guard weight > 0 && weight <= 16 else { return Pat::silence() }
    total += weight
    guard total <= 256 else { return Pat::silence() }
  }
  let pats = pats.copy()
  let total_rat = Rational::from_int(total)
  let one = Rational::from_int(1)
  let mut elapsed = 0
  let slots = Array::makei(n, i => {
    let weight = weights[i]
    let begin = Rational::from_int(elapsed) / total_rat
    elapsed += weight
    let end_ = Rational::from_int(elapsed) / total_rat
    { begin, end_, duration: Rational::from_int(weight) / total_rat, }
  })
  let full_pat_arc = TimeSpan::new(Rational::from_int(0), one)
  let signature = combine_signature(
    "weighted_sequence:\{weights.map(weight => "\{weight}").join(",")}",
    pats,
  )
  make_pat(
    fn(arc) {
      let result : Array[Event[A]] = []
      for cycle_arc in arc.whole_cycles() {
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        for i in 0..<n {
          let slot = slots[i]
          let slot_begin = cycle_start + slot.begin
          let slot_end = cycle_start + slot.end_
          let slot_arc = TimeSpan::new(slot_begin, slot_end)
          let query_intersect = match slot_arc.intersect(arc) {
            Some(ts) => ts
            None => continue
          }
          let query_pat_arc = TimeSpan::new(
            (query_intersect.begin - slot_begin) / slot.duration,
            (query_intersect.end_ - slot_begin) / slot.duration,
          )
          for ev in pats[i].query(full_pat_arc) {
            let ev_part_clipped = match ev.part.intersect(query_pat_arc) {
              Some(ts) => ts
              None => continue
            }
            let part_begin_orig = slot_begin +
              ev_part_clipped.begin * slot.duration
            let part_end_orig = slot_begin +
              ev_part_clipped.end_ * slot.duration
            let new_whole = ev.whole.map(w => {
              TimeSpan::new(
                slot_begin + w.begin * slot.duration,
                slot_begin + w.end_ * slot.duration,
              )
            })
            result.push({
              whole: new_whole,
              part: TimeSpan::new(part_begin_orig, part_end_orig),
              value: ev.value,
            })
          }
        }
      }
      result
    },
    one,
    Opaque([]),
    Anonymous,
    signature,
  )
}

///|
fn[A] append_overlay(pat : Pat[A], result : Array[Pat[A]]) -> Unit {
  match pat.body {
    Silence =>
      match pat.metadata.scope {
        Anonymous => ()
        Named(_) | Material | NamedMaterial(_) => result.push(pat)
      }
    Overlay(children) =>
      match pat.metadata.scope {
        Anonymous =>
          for child in children {
            append_overlay(child, result)
          }
        Named(_) | Material | NamedMaterial(_) => result.push(pat)
      }
    Opaque(_) => result.push(pat)
  }
}

///|
pub fn[A] stack(pats : Array[Pat[A]]) -> Pat[A] {
  let normalized : Array[Pat[A]] = []
  for pat in pats {
    append_overlay(pat, normalized)
  }
  if normalized.is_empty() {
    return Pat::silence()
  }
  if normalized.length() == 1 {
    return normalized[0]
  }
  make_pat(
    fn(arc) {
      normalized.iter().flat_map(pat => pat.query(arc).iter()).collect()
    },
    Rational::from_int(1),
    Overlay(normalized),
    Anonymous,
    overlay_signature(normalized),
  )
}

///|
pub impl[A] Add for Pat[A] with fn add(self : Pat[A], other : Pat[A]) -> Pat[A] {
  stack([self, other])
}

///|
/// Keep events where `f(value)` returns `Some(new_value)`, discard the rest.
/// Preserves event timing (whole and part spans unchanged).
/// Callback content is unknown, so live edits are never skipped.
pub fn[A] Pat::filter_map(self : Pat[A], f : (A) -> A?) -> Pat[A] {
  self.filter_map_known(f, "")
}

///|
fn[A] Pat::filter_map_known(
  self : Pat[A],
  f : (A) -> A?,
  signature : String,
) -> Pat[A] {
  self.filter_map_payload(f, signature)
}

///|
fn[A, B] Pat::filter_map_payload(
  self : Pat[A],
  f : (A) -> B?,
  signature : String,
) -> Pat[B] {
  if self.body is Silence {
    return make_pat(
      fn(_arc) { [] },
      self.metadata.period,
      Silence,
      self.metadata.scope,
      self.metadata.content,
    )
  }
  let inner = self
  let children = self.transform_children(p => p.filter_map_payload(f, signature))
  let change = if signature == "" { "" } else { "filter:" + signature }
  make_pat(
    fn(arc) {
      inner
      .query(arc)
      .filter_map(ev => {
        f(ev.value).map(new_value => {
          whole: ev.whole,
          part: ev.part,
          value: new_value,
        })
      })
    },
    self.metadata.period,
    Opaque(children),
    self.metadata.scope,
    transformed_signature(self.entry_signature(), change),
  )
}

///|
/// Bjorklund's algorithm: distribute `k` pulses across `n` steps as evenly
/// as possible, returning a `Bool[]` of length `n` with `k` `true` entries.
///
/// Algorithm: start with `k` front-groups of `[true]` and `n-k` back-groups
/// of `[false]`. Repeatedly merge front with back pair-wise (concatenating
/// each pair) until ≤ 1 trailing group remains. Concatenate front then
/// back to produce the final pattern.
///
/// Edge cases: `k <= 0` → all-false; `k >= n` → all-true (saturates).
fn bjorklund(k : Int, n : Int) -> Array[Bool] {
  if n <= 0 {
    return []
  }
  if k <= 0 {
    return Array::make(n, false)
  }
  if k >= n {
    return Array::make(n, true)
  }
  let mut front : Array[Array[Bool]] = Array::makei(k, _ => [true])
  let mut back : Array[Array[Bool]] = Array::makei(n - k, _ => [false])
  while back.length() > 1 {
    let pairs = if front.length() < back.length() {
      front.length()
    } else {
      back.length()
    }
    let new_front = Array::makei(pairs, i => front[i] + back[i])
    let new_back = if front.length() > pairs {
      front[pairs:].to_owned()
    } else {
      back[pairs:].to_owned()
    }
    front = new_front
    back = new_back
    if front.length() <= 1 {
      break
    }
  }
  front.flatten() + back.flatten()
}

///|
/// Euclidean rhythm: distribute `k` pulses across `n` steps within one
/// cycle using Bjorklund's algorithm. Pulse positions play `self`, off
/// positions are silent. Each step occupies `1/n` of the cycle.
///
/// `rotation` left-rotates the pulse pattern by that many steps (mod n).
/// `k <= 0` or `n <= 0` yields silence; `k >= n` yields one pulse per step.
pub fn[A] Pat::euclid(
  self : Pat[A],
  k : Int,
  n : Int,
  rotation? : Int = 0,
) -> Pat[A] {
  if n <= 0 || k <= 0 {
    return Pat::silence()
  }
  let pattern = bjorklund(k, n)
  let r = (rotation % n + n) % n
  sequence(
    [
      for i in 0..<n => if pattern[(i + r) % n] { self } else { Pat::silence() }
    ],
  )
}

///|
/// Deterministic per-event pseudo-random in `[0, 1)`. Same `(num, den, seed)`
/// always produces the same value, so `degrade_by` is reproducible across
/// queries of the same arc — required for live coding (no audible glitch
/// when the worklet re-queries a cycle that was already partly scheduled).
fn hash_unit(num : Int64, den : Int64, seed : Int) -> Double {
  let n = num.to_double()
  let d = den.to_double()
  let s = seed.to_double()
  let v = @math.sin(n * 12.9898 + d * 78.233 + s * 37.719) * 43758.5453
  let frac = v - v.floor()
  if frac < 0.0 {
    frac + 1.0
  } else {
    frac
  }
}

///|
/// Drop each event with probability `p` (clamped to `[0, 1]`). The drop
/// decision is deterministic per `(event.whole.begin, seed)` so multiple
/// queries of the same arc produce identical event sets.
///
/// `seed` lets users decorrelate two `degrade_by` instances that would
/// otherwise drop the same events.
///
/// `bd?` in mini-notation is sugar for `degrade_by(0.5)`.
pub fn[A] Pat::degrade_by(
  self : Pat[A],
  p : Double,
  seed? : Int = 42,
) -> Pat[A] {
  let prob = if p < 0.0 { 0.0 } else if p > 1.0 { 1.0 } else { p }
  guard !(prob <= 0.0) else { return self }
  if prob >= 1.0 {
    return self.filter_map_known(_ => None, "silence")
  }
  guard !(self.body is Silence) else { return self }
  let inner = self
  let children = self.transform_children(pattern_member => {
    pattern_member.degrade_by(p, seed~)
  })
  make_pat(
    fn(arc) {
      inner
      .query(arc)
      .filter(ev => {
        let key = match ev.whole {
          Some(w) => w.begin
          None => ev.part.begin
        }
        hash_unit(key.num, key.den, seed) >= prob
      })
    },
    self.metadata.period,
    Opaque(children),
    self.metadata.scope,
    transformed_signature(self.entry_signature(), "degrade:\{prob}:\{seed}"),
  )
}

///|
/// Apply an arbitrary callback every n source cycles. Its content is unknown.
pub fn[A] every(n : Int, f : (Pat[A]) -> Pat[A], pat : Pat[A]) -> Pat[A] {
  every_known(n, f, pat, "")
}

///|
fn[A] every_known(
  n : Int,
  f : (Pat[A]) -> Pat[A],
  pat : Pat[A],
  signature : String,
) -> Pat[A] {
  if n <= 0 {
    return pat
  }
  if signature != "" && pat.body is Silence {
    return pat
  }
  let n64 = Int64::from_int(n)
  let inner = pat
  make_pat(
    fn(arc) {
      arc
      .whole_cycles()
      .iter()
      .flat_map(cycle_arc => {
        let cycle_num = cycle_arc.begin.floor()
        // Double-mod to handle negative cycle numbers correctly
        let rem = (cycle_num % n64 + n64) % n64
        if rem == 0L {
          f(inner).query(cycle_arc).iter()
        } else {
          inner.query(cycle_arc).iter()
        }
      })
      .collect()
    },
    pat.metadata.period,
    Opaque([]),
    pat.metadata.scope,
    transformed_signature(
      pat.entry_signature(),
      if signature == "" {
        ""
      } else {
        "every:\{n}:" + signature
      },
    ),
  )
}

///|
pub extend Pat with Add::{add}
