///|
/// Samples per bucket of a signal curve, so a bucket shows its extremes.
const SIGNAL_GRAPH_SUBSAMPLES : Int32 = 8

///|
/// The longest window a pattern's signal graph shows, in cycles.
const SIGNAL_GRAPH_MAX_CYCLES : Int32 = 64

///|
/// A signal argument written in the draft and the values the music gives it:
/// the curves the voices it controls follow, with every transform around it
/// and the song's placement of its sections applied.
pub struct SignalGraph {
  priv range : SourceRange
  priv window : @pattern.Rational
  priv song : Bool
  priv curves : Array[SignalCurve]
}

///|
pub fn SignalGraph::range(self : SignalGraph) -> SourceRange {
  self.range
}

///|
/// Cycles the graph spans from cycle 0: the song's length, or for a pattern
/// the whole cycles after which every curve repeats, at most 64.
pub fn SignalGraph::window(self : SignalGraph) -> @pattern.Rational {
  self.window
}

///|
pub fn SignalGraph::is_song(self : SignalGraph) -> Bool {
  self.song
}

///|
/// One curve per bus that follows the signal: one, unless a binding is used
/// more than once, `jux` copies it, or an inner setting of the same control
/// combines with it.
pub fn SignalGraph::curves(self : SignalGraph) -> Array[SignalCurve] {
  self.curves
}

///|
/// One use of a signal over a graph's window, split into equal buckets.
pub struct SignalCurve {
  priv lows : Array[@control.ControlValue]
  priv highs : Array[@control.ControlValue]
  priv spans : Array[@pattern.TimeSpan]
  priv first : @control.ControlValue
  priv last : @control.ControlValue
}

///|
/// The least value in each bucket; absent where the curve has no value.
pub fn SignalCurve::lows(self : SignalCurve) -> Array[@control.ControlValue] {
  self.lows
}

///|
/// The greatest value in each bucket; absent where the curve has no value.
pub fn SignalCurve::highs(self : SignalCurve) -> Array[@control.ControlValue] {
  self.highs
}

///|
/// Where the curve has a value: the whole window for a pattern, and each
/// section occurrence that plays it for a song.
pub fn SignalCurve::spans(self : SignalCurve) -> Array[@pattern.TimeSpan] {
  self.spans
}

///|
/// The value where the first span begins.
pub fn SignalCurve::first(self : SignalCurve) -> @control.ControlValue {
  self.first
}

///|
/// The value just before the last span ends.
pub fn SignalCurve::last(self : SignalCurve) -> @control.ControlValue {
  self.last
}

///|
/// The signal graphs of the current text, each curve split into `buckets`
/// buckets. Empty while the text does not parse.
pub fn Draft::signal_graphs(
  self : Draft,
  buckets~ : Int32,
) -> Array[SignalGraph] {
  guard self.analysis is Playable(source, _) && buckets > 0 else { return [] }
  let signals = self.sources.atoms.filter(atom => atom.kind == "signal")
  match source.body {
    Pattern(doc) => {
      let snapshot = doc.lower_tracked() catch { _ => return [] }
      signals.filter_map(signal => {
        let traces = snapshot.control_traces(signal.id)
        guard !traces.is_empty() else { return None }
        let window = signal_pattern_window(traces)
        let span = @pattern.TimeSpan(@pattern.Rational::from_int(0), window)
        Some({
          range: SourceRange(signal.span),
          window,
          song: false,
          curves: traces.map(trace => {
            signal_curve([(span, trace)], window, buckets)
          }),
        })
      })
    }
    // A tracked Draft lowers every song section with origins.
    UntrackedArrangement(_, _) => []
    TrackedArrangement(snapshot, _) => {
      let song = snapshot.song()
      let window = song.duration()
      signals.filter_map(signal => {
        // Curve i follows the i-th trace in every occurrence, placed as
        // playback places that occurrence's events.
        let curves : Array[Array[(@pattern.TimeSpan, @pattern.ControlTrace)]] = []
        for occurrence in song.occurrences() {
          let section = occurrence.section()
          let placement = @pattern.Placement(
            origin=occurrence.start(),
            rate=section.scope().rate(),
          )
          let snapshots = match section.section_body() {
            Single(snapshot) => [snapshot]
            Layers(layers) => layers.map(layer => layer.body())
          }
          let mut index = 0
          for snapshot in snapshots {
            for trace in snapshot.control_traces(signal.id) {
              if index == curves.length() {
                curves.push([])
              }
              curves[index].push((occurrence.span(), trace.placed(placement)))
              index += 1
            }
          }
        }
        guard !curves.is_empty() else { return None }
        Some({
          range: SourceRange(signal.span),
          window,
          song: true,
          curves: curves.map(segments => signal_curve(segments, window, buckets)),
        })
      })
    }
  }
}

///|
/// The whole cycles after which every trace repeats, at most 64.
fn signal_pattern_window(
  traces : Array[@pattern.ControlTrace],
) -> @pattern.Rational {
  let max = @pattern.Rational::from_int(SIGNAL_GRAPH_MAX_CYCLES)
  let mut window = @pattern.Rational::from_int(1)
  for trace in traces {
    guard trace.period() is Some(period) else { return max }
    window = window.lcm(period)
    guard window <= max else { return max }
  }
  window
}

///|
/// Sample `segments`, each a span and the trace it plays there, into `buckets`
/// buckets of `window`. Where segments overlap, the later one plays.
fn signal_curve(
  segments : Array[(@pattern.TimeSpan, @pattern.ControlTrace)],
  window : @pattern.Rational,
  buckets : Int32,
) -> SignalCurve {
  let absent = @control.ControlValue::absent()
  let lows = Array::make(buckets, absent)
  let highs = Array::make(buckets, absent)
  fn add(bucket : Int32, value : @control.ControlValue) {
    guard value.get() is Some(v) else { return }
    if lows[bucket].get() is Some(low) && low <= v {
      ()
    } else {
      lows[bucket] = value
    }
    if highs[bucket].get() is Some(high) && high >= v {
      ()
    } else {
      highs[bucket] = value
    }
  }
  // The bucket holding `time`, or with `before`, the one holding the instant
  // just before it.
  fn bucket_of(time : @pattern.Rational, before : Bool) -> Int32 {
    let position = time * @pattern.Rational(buckets.to_int64(), 1L) / window
    let index = position.floor() -
      (if before && position.den == 1L { 1L } else { 0L })
    index.to_int().clamp(min=0, max=buckets - 1)
  }
  let samples = buckets * SIGNAL_GRAPH_SUBSAMPLES
  for i in 0..<samples {
    let time = window * @pattern.Rational(i.to_int64(), samples.to_int64())
    let mut value = absent
    for segment in segments {
      if segment.0.begin <= time && time < segment.0.end_ {
        value = segment.1.value_at(time)
      }
    }
    add(i / SIGNAL_GRAPH_SUBSAMPLES, value)
  }
  // The grid can miss a segment's exact ends; they are its extremes for a saw.
  for segment in segments {
    let (span, trace) = segment
    add(bucket_of(span.begin, false), trace.value_at(span.begin))
    add(bucket_of(span.end_, true), trace.value_before(span.end_))
  }
  let (first_span, first_trace) = segments[0]
  let (last_span, last_trace) = segments[segments.length() - 1]
  {
    lows,
    highs,
    spans: segments.map(segment => segment.0),
    first: first_trace.value_at(first_span.begin),
    last: last_trace.value_before(last_span.end_),
  }
}
