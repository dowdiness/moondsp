///|
pub struct Event[A] {
  whole : TimeSpan?
  part : TimeSpan
  value : A
} derive(Show)
