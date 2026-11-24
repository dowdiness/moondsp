///|
pub fn[A] sequence(pats : Array[Pat[A]]) -> Pat[A] {
  let n = pats.length()
  if n == 0 {
    return Pat::silence()
  }
  let pats = pats.copy()
  let map = TimeMap::sequence(n)
  make_pat(
    arc => map.query(pats, arc),
    map.period(periods_lcm(pats)),
    Opaque([]),
    Anonymous,
    combine_signature("sequence", pats),
  )
}

///|
/// Sequence patterns whose positive integer weights determine their cycle shares.
/// In cycle c each child plays its own cycle c over its entire slot.
/// Weights must be 1–16 and their sum at most 256; invalid inputs yield silence.
pub fn[A] sequence_weighted(
  pats : Array[Pat[A]],
  weights : Array[Int32],
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
  let map = TimeMap::weighted(weights)
  let signature = combine_signature(
    "weighted_sequence:\{weights.map(weight => "\{weight}").join(",")}",
    pats,
  )
  make_pat(
    arc => map.query(pats, arc),
    map.period(periods_lcm(pats)),
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
        Material | Addressed(_) => result.push(pat)
      }
    Overlay(children) =>
      match pat.metadata.scope {
        Anonymous =>
          for child in children {
            append_overlay(child, result)
          }
        Material | Addressed(_) => result.push(pat)
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
    periods_lcm(normalized),
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
fn bjorklund(k : Int32, n : Int32) -> Array[Bool] {
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
  k : Int32,
  n : Int32,
  rotation~ : Int32 = 0,
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
fn hash_unit(num : Int64, den : Int64, seed : Int32) -> Double {
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
  seed~ : Int32 = 42,
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
pub fn[A] every(n : Int32, f : (Pat[A]) -> Pat[A], pat : Pat[A]) -> Pat[A] {
  every_known(n, f, pat, "")
}

///|
fn[A] every_known(
  n : Int32,
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
  let n64 = n.to_int64()
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
