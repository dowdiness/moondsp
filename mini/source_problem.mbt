///|
/// Why a source cannot be played, decided where the parser finds it.
#derive(Eq, Debug)
pub(all) suberror SourceProblem {
  /// The code is wrong at this UTF-16 offset into the whole source.
  Mistake(Int32, String)
  /// The code is valid but exceeds what playback can afford.
  OverLimit(SourceLimit)
  /// The compiler broke one of its own invariants; the author cannot fix it.
  Internal(String)
}

///|
pub extend SourceProblem with Eq::{equal, not_equal}

///|
pub extend SourceProblem with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum SourceLimit {
  /// More than 8192 UTF-16 code units.
  Length
  /// Brackets, calls, or transform chains nested deeper than this.
  Nesting(Int32)
  /// More than 512 syntax nodes, or syntax deeper than 32, under admission.
  SyntaxNodes
  /// A pattern could make one player query expand too far.
  PatternExpansion
  /// Overlapping song parts could make one player query expand too far.
  ArrangementExpansion
  /// More than 128 song occurrences and gaps.
  Occurrences
  /// A Euclidean rhythm over 128 steps.
  EuclideanSteps
  /// Relative durations in one sequence summing over 256.
  DurationSum
  /// A notation projection over 256 source nodes.
  NotationNodes
}

///|
pub extend SourceLimit with Eq::{equal, not_equal}

///|
pub extend SourceLimit with Debug::{to_repr}

///|
/// What the author reads; a mistake's position is reported separately.
pub fn SourceProblem::message(self : SourceProblem) -> String {
  match self {
    Mistake(_, message) | Internal(message) => message
    OverLimit(limit) =>
      match limit {
        Length => "playback source exceeds 8192 characters"
        Nesting(depth) => "source exceeds nesting depth \{depth}"
        SyntaxNodes => "playback source exceeds 512 syntax nodes or depth 32"
        PatternExpansion => "playback source exceeds the query expansion limit"
        ArrangementExpansion =>
          "playback arrangement exceeds the query expansion limit"
        Occurrences => "playback arrangement exceeds 128 occurrences"
        EuclideanSteps => "playback Euclidean rhythm exceeds 128 steps"
        DurationSum => "relative duration sum must not exceed 256"
        NotationNodes => "notation projection exceeds 256 source nodes"
      }
  }
}

///|
/// One line of text for callers that only display the problem.
pub impl Show for SourceProblem with fn output(self, logger) {
  match self {
    Mistake(at, message) => logger.write_string("position \{at}: \{message}")
    _ => logger.write_string(self.message())
  }
}

///|
pub extend SourceProblem with Show::{to_string}
