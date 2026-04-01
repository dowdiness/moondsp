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
  if pats.length() == 0 {
    return Pat::silence()
  }
  {
    query: fn(arc) {
      let result : Array[Event[A]] = []
      for pat in pats {
        let events = pat.query(arc)
        for ev in events {
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
