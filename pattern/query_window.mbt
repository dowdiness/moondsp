///|
/// The longest stretch of musical time a consumer asks a pattern for at once.
/// It is always positive, because `from_span` is the only way to build one.
pub struct QueryWindow {
  priv span : Rational
}

///|
/// A window spanning `span` cycles, or `None` when `span` is not positive.
pub fn QueryWindow::from_span(span : Rational) -> QueryWindow? {
  if span.num > 0L {
    Some({ span, })
  } else {
    None
  }
}

///|
pub fn QueryWindow::span(self : QueryWindow) -> Rational {
  self.span
}
