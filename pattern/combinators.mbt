///|
pub fn[A] sequence(pats : Array[Pat[A]]) -> Pat[A] {
  let n = pats.length()
  if n == 0 {
    return Pat::silence()
  }
  {
    query: fn(arc) {
      let n_rat = Rational::from_int(n)
      let one = Rational::from_int(1)
      let result : Array[Event[A]] = []
      let cycles = arc.whole_cycles()
      for cycle_arc in cycles {
        // Determine the full cycle start from cycle_arc.begin
        let cycle_start = Rational::new(cycle_arc.begin.floor(), 1L)
        for i in 0..<n {
          let i_rat = Rational::from_int(i)
          // Slot arc within the cycle: [i/n, (i+1)/n) + cycle_start
          let slot_begin = cycle_start + i_rat / n_rat
          let slot_end = cycle_start + (i_rat + one) / n_rat
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
          // Also compute the full slot in pattern space: [0,1) for this slot
          // We must use the cycle bounds to avoid querying outside [0,1)
          // Compute pattern-space arc for the full slot within cycle
          let cycle_pat_begin = (slot_arc.begin - cycle_start) * n_rat - i_rat
          let cycle_pat_end = (slot_arc.end_ - cycle_start) * n_rat - i_rat
          let full_pat_arc = TimeSpan::new(cycle_pat_begin, cycle_pat_end)
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
            result.push({ whole: new_whole, part: new_part, value: ev.value })
          }
        }
      }
      result
    },
  }
}

///|
pub fn[A] stack(pats : Array[Pat[A]]) -> Pat[A] {
  if pats.is_empty() {
    return Pat::silence()
  }
  {
    query: fn(arc) {
      let result : Array[Event[A]] = []
      for pat in pats {
        result.append(pat.query(arc))
      }
      result
    },
  }
}

///|
/// Keep events where `f(value)` returns `Some(new_value)`, discard the rest.
/// Preserves event timing (whole and part spans unchanged).
pub fn[A] Pat::filter_map(self : Pat[A], f : (A) -> A?) -> Pat[A] {
  let inner = self
  {
    query: fn(arc) {
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
  }
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
      front[pairs:].to_array()
    } else {
      back[pairs:].to_array()
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
  let pats : Array[Pat[A]] = []
  for i in 0..<n {
    let idx = (i + r) % n
    if pattern[idx] {
      pats.push(self)
    } else {
      pats.push(Pat::silence())
    }
  }
  sequence(pats)
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
  if prob <= 0.0 {
    return self
  }
  if prob >= 1.0 {
    return Pat::silence()
  }
  let inner = self
  {
    query: fn(arc) {
      let events = inner.query(arc)
      let result : Array[Event[A]] = []
      for ev in events {
        let key = match ev.whole {
          Some(w) => w.begin
          None => ev.part.begin
        }
        let r = hash_unit(key.num, key.den, seed)
        if r >= prob {
          result.push(ev)
        }
      }
      result
    },
  }
}

///|
pub fn[A] every(n : Int, f : (Pat[A]) -> Pat[A], pat : Pat[A]) -> Pat[A] {
  if n <= 0 {
    return pat
  }
  let n64 = Int64::from_int(n)
  let inner = pat
  {
    query: fn(arc) {
      let result : Array[Event[A]] = []
      let cycles = arc.whole_cycles()
      for cycle_arc in cycles {
        let cycle_num = cycle_arc.begin.floor()
        // Double-mod to handle negative cycle numbers correctly
        let rem = (cycle_num % n64 + n64) % n64
        let events = if rem == 0L {
          f(inner).query(cycle_arc)
        } else {
          inner.query(cycle_arc)
        }
        for ev in events {
          result.push(ev)
        }
      }
      result
    },
  }
}
