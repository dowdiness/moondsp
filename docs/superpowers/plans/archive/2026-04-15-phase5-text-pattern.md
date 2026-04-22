# Phase 5: Text Pattern to Audible Output — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Type `s("bd sd hh sd").fast(2)` in a browser text field and hear a synthesized drum beat.

**Architecture:** A loom-based parser (`mini/` package) converts text to `Pat[ControlMap]`. The browser layer splits the pattern by sound type via `filter_map` and routes events to per-template voice pools. All parsing happens inside the AudioWorklet wasm instance. If loom's dependency chain doesn't compile to wasm-gc, a hand-written recursive descent parser provides the same API.

**Tech Stack:** MoonBit, loom (parser framework from canopy), seam (CST library), WebAudio AudioWorklet, wasm-gc

**Spec:** `docs/superpowers/specs/2026-04-15-phase5-text-pattern-design.md`

---

## File Map

**New files:**
| File | Responsibility |
|------|---------------|
| `mini/moon.pkg` | Package config — imports loom/core, seam, pattern |
| `mini/drums.mbt` | Sound name → GM MIDI number mapping |
| `mini/mini.mbt` | Public API: `parse(String) -> Result[Pat[ControlMap], String]` |
| `mini/lexer.mbt` | Step-based tokenizer (Token enum + lex function) |
| `mini/syntax.mbt` | SyntaxKind enum + seam trait impls |
| `mini/parser.mbt` | Recursive descent parser using loom/core ParserContext |
| `mini/fold.mbt` | CST → Pat[ControlMap] fold function |
| `mini/mini_test.mbt` | Parser tests (blackbox) |

**Modified files:**
| File | Change |
|------|--------|
| `moon.mod.json` | Add loom, seam path dependencies |
| `pattern/combinators.mbt` | Add `Pat::filter_map` |
| `pattern/combinators_test.mbt` | filter_map tests |
| `browser/browser_scheduler.mbt` | Multi-pool routing, parse_and_set_pattern |
| `browser/moon.pkg` | Add mini import, new wasm exports |
| `web/index.html` | Text input UI replacing pattern buttons |
| `web/processor.js` | Handle set-pattern-text message |

---

## Task 0: Verify loom compiles to wasm-gc (risk gate)

**Files:**
- Modify: `moon.mod.json`

This is the critical risk gate. loom depends on seam, text_change, incr, and graphviz. We only need `loom/core` (depends on seam + text_change), but the module declaration pulls in all deps. If this fails, fall back to hand-written parser (Task 3-alt).

- [ ] **Step 1: Add loom and seam as path dependencies**

In `moon.mod.json`, add to `"deps"`:

```json
"dowdiness/loom": { "path": "../canopy/loom/loom" },
"dowdiness/seam": { "path": "../canopy/loom/seam" }
```

- [ ] **Step 2: Create minimal mini/ package to test import**

Create `mini/moon.pkg`:

```
import {
  "dowdiness/loom/core" @core,
  "dowdiness/seam" @seam,
}
```

Create `mini/mini.mbt`:

```moonbit
///|
pub fn smoke_test() -> Bool {
  true
}
```

- [ ] **Step 3: Build and verify**

Run: `moon check`

Expected: compiles without errors. If dependency resolution fails (missing transitive deps), try adding them explicitly to `moon.mod.json`:

```json
"dowdiness/text_change": { "path": "../canopy/lib/text-change" },
"dowdiness/incr": { "path": "../canopy/loom/incr" }
```

If it still fails after adding transitive deps, proceed to Task 3-alt (hand-written parser) and skip Tasks 3-6.

- [ ] **Step 4: Verify wasm-gc build**

Run: `moon build --target wasm-gc`

Expected: builds successfully. This confirms loom code compiles to wasm-gc target.

- [ ] **Step 5: Commit**

```bash
git add moon.mod.json mini/
git commit -m "chore: add loom/seam deps and mini/ package scaffold"
```

---

## Task 1: Add Pat::filter_map to pattern/

**Files:**
- Modify: `pattern/combinators.mbt`
- Test: `pattern/combinators_test.mbt`

- [ ] **Step 1: Write failing tests**

In `pattern/combinators_test.mbt`, add:

```moonbit
///|
test "filter_map keeps matching events" {
  let pat = sequence([note(60.0), note(72.0), note(60.0)])
  let filtered = pat.filter_map(fn(cm) {
    let m = cm.to_map()
    match m.get("note") {
      Some(n) => if n == 60.0 { Some(cm) } else { None }
      None => None
    }
  })
  let events = filtered.query(TimeSpan::new(Rational::new(0L, 1L), Rational::new(1L, 1L)))
  inspect!(events.length(), content="2")
}

///|
test "filter_map removes non-matching events" {
  let pat = sequence([note(60.0), note(72.0)])
  let filtered = pat.filter_map(fn(cm) {
    let m = cm.to_map()
    match m.get("note") {
      Some(n) => if n == 99.0 { Some(cm) } else { None }
      None => None
    }
  })
  let events = filtered.query(TimeSpan::new(Rational::new(0L, 1L), Rational::new(1L, 1L)))
  inspect!(events.length(), content="0")
}

///|
test "filter_map on silence returns silence" {
  let pat : Pat[ControlMap] = Pat::silence()
  let filtered = pat.filter_map(fn(cm) { Some(cm) })
  let events = filtered.query(TimeSpan::new(Rational::new(0L, 1L), Rational::new(1L, 1L)))
  inspect!(events.length(), content="0")
}

///|
test "filter_map preserves event timing" {
  // In sequence([a, b, c]), a occupies [0, 1/3), b [1/3, 2/3), c [2/3, 1)
  // Filtering to keep only 'a' should preserve its [0, 1/3) timing
  let pat = sequence([note(60.0), note(72.0), note(84.0)])
  let filtered = pat.filter_map(fn(cm) {
    let m = cm.to_map()
    match m.get("note") {
      Some(n) => if n == 60.0 { Some(cm) } else { None }
      None => None
    }
  })
  let events = filtered.query(TimeSpan::new(Rational::new(0L, 1L), Rational::new(1L, 1L)))
  inspect!(events.length(), content="1")
  let e = events[0]
  // whole span should be [0, 1/3)
  match e.whole {
    Some(w) => {
      inspect!(w.begin == Rational::new(0L, 1L), content="true")
      inspect!(w.end_ == Rational::new(1L, 3L), content="true")
    }
    None => fail!("expected whole span")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/moondsp/pattern`

Expected: FAIL — `filter_map` not defined.

- [ ] **Step 3: Check if ControlMap has a to_map() accessor**

Run: `moon ide outline pattern/ | grep -i map` and read `pattern/control.mbt` to find how to access ControlMap's inner Map. If there's no `to_map()`, check what accessor exists (might be pattern-matched directly, or have a `get` method). Adjust the test code accordingly.

- [ ] **Step 4: Implement filter_map**

In `pattern/combinators.mbt`, add:

```moonbit
///|
pub fn Pat::filter_map[A](self : Pat[A], f : (A) -> A?) -> Pat[A] {
  Pat::new(fn(arc) {
    let events = self.query(arc)
    let result : Array[Event[A]] = []
    for e in events {
      match f(e.value) {
        Some(new_value) => result.push(Event::new(whole=e.whole, part=e.part, value=new_value))
        None => ()
      }
    }
    result
  })
}
```

Note: Check that `Pat::new` exists and takes `(TimeSpan) -> Array[Event[A]]`. If the constructor is different (e.g., `{ query: fn }` struct literal), adjust. Also verify `Event::new` or equivalent constructor exists — may need `{ whole: e.whole, part: e.part, value: new_value }`.

- [ ] **Step 5: Run tests**

Run: `moon check && moon test -p dowdiness/moondsp/pattern`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add pattern/
git commit -m "feat(pattern): add filter_map combinator"
```

---

## Task 2: Implement drums.mbt — sound name mapping

**Files:**
- Create: `mini/drums.mbt`
- Test: `mini/mini_test.mbt`

- [ ] **Step 1: Write failing tests**

Create `mini/mini_test.mbt`:

```moonbit
///|
test "drum_midi returns correct GM numbers" {
  inspect!(drum_midi("bd"), content="Some(36)")
  inspect!(drum_midi("sd"), content="Some(38)")
  inspect!(drum_midi("hh"), content="Some(42)")
}

///|
test "drum_midi returns None for unknown names" {
  inspect!(drum_midi("snare"), content="None")
  inspect!(drum_midi(""), content="None")
  inspect!(drum_midi("123"), content="None")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/moondsp/mini`

Expected: FAIL — `drum_midi` not defined.

- [ ] **Step 3: Implement drum_midi**

In `mini/drums.mbt`:

```moonbit
///|
pub fn drum_midi(name : String) -> Int? {
  match name {
    "bd" => Some(36)
    "sd" => Some(38)
    "hh" => Some(42)
    _ => None
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/moondsp/mini`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mini/
git commit -m "feat(mini): add drum name to GM MIDI number mapping"
```

---

## Task 3: Implement mini-notation parser

**Files:**
- Create: `mini/lexer.mbt`, `mini/syntax.mbt`, `mini/parser.mbt`, `mini/fold.mbt`
- Modify: `mini/mini.mbt`, `mini/moon.pkg`, `mini/mini_test.mbt`

This is the largest task. It implements the loom-based parser. Each sub-step builds incrementally.

### Step group A: Token and SyntaxKind enums

- [ ] **Step A1: Define Token enum**

In `mini/lexer.mbt`:

```moonbit
///|
pub(all) enum Token {
  LParen          // (
  RParen          // )
  LBracket        // [
  RBracket        // ]
  Dot             // .
  Comma           // ,
  Quote           // "
  Ident(String)   // bd, sd, hh, s, note, fast, slow, rev
  Number(String)  // 60, 2, 0.5
  Whitespace      // spaces inside notation
  Error(String)   // lexer errors
  EOF
} derive(Eq, Debug)
```

Implement the required seam traits (`IsTrivia`, `IsEof`, `ToRawKind`) following the JSON example pattern. Check what traits loom/core's ParserContext requires on Token.

- [ ] **Step A2: Define SyntaxKind enum**

In `mini/syntax.mbt`:

```moonbit
///|
pub(all) enum SyntaxKind {
  // Token kinds (must match Token ordering)
  LParenToken
  RParenToken
  LBracketToken
  RBracketToken
  DotToken
  CommaToken
  QuoteToken
  IdentToken
  NumberToken
  WhitespaceToken
  ErrorToken
  EofToken
  // Node kinds
  RootNode        // top-level expr
  PrimaryNode     // s("...") or note("...")
  MethodNode      // .fast(2)
  NotationNode    // inner mini-notation
  LayerNode       // space-separated sequence
  GroupNode       // [...] sub-group
  AtomNode        // single identifier or number
} derive(Debug, Eq)
```

Implement `ToRawKind` and `from_raw` for SyntaxKind.

- [ ] **Step A3: Run moon check**

Run: `moon check`

Expected: compiles. Fix any missing trait impls.

### Step group B: Tokenizer

- [ ] **Step B1: Implement step-based lexer**

In `mini/lexer.mbt`, implement the tokenizer. The input format has two layers:

1. **Outer**: `s(`, `note(`, `)`, `.`, `fast(`, `slow(`, `rev(`, numbers
2. **Inner** (inside quotes): identifiers (`bd`, `sd`), numbers, spaces, `[`, `]`, `,`

The tokenizer handles both layers (the parser distinguishes context).

```moonbit
///|
pub fn mini_step_lexer(source : String, pos : Int) -> @core.LexStep[Token] {
  if pos >= source.length() {
    return @core.LexStep::Done
  }
  let ch = source[pos]
  match ch {
    '(' => @core.LexStep::Produced(@core.TokenInfo::new(LParen, 1), next_offset=pos + 1)
    ')' => @core.LexStep::Produced(@core.TokenInfo::new(RParen, 1), next_offset=pos + 1)
    '[' => @core.LexStep::Produced(@core.TokenInfo::new(LBracket, 1), next_offset=pos + 1)
    ']' => @core.LexStep::Produced(@core.TokenInfo::new(RBracket, 1), next_offset=pos + 1)
    '.' => @core.LexStep::Produced(@core.TokenInfo::new(Dot, 1), next_offset=pos + 1)
    ',' => @core.LexStep::Produced(@core.TokenInfo::new(Comma, 1), next_offset=pos + 1)
    '"' => @core.LexStep::Produced(@core.TokenInfo::new(Quote, 1), next_offset=pos + 1)
    ' ' | '\t' | '\n' => {
      let mut end = pos + 1
      while end < source.length() && (source[end] == ' ' || source[end] == '\t' || source[end] == '\n') {
        end = end + 1
      }
      @core.LexStep::Produced(@core.TokenInfo::new(Whitespace, end - pos), next_offset=end)
    }
    _ => {
      if is_digit(ch) || ch == '-' {
        lex_number(source, pos)
      } else if is_alpha(ch) {
        lex_ident(source, pos)
      } else {
        @core.LexStep::Produced(
          @core.TokenInfo::new(Error("unexpected character: " + ch.to_string()), 1),
          next_offset=pos + 1,
        )
      }
    }
  }
}
```

Implement `lex_number` (reads digits and optional `.` decimal) and `lex_ident` (reads alpha + digits, returns Ident with the text).

Note: Check how to access individual characters in MoonBit String — may need `source.charCodeAt(pos)` or similar. Use `String::view` or index access as appropriate.

- [ ] **Step B2: Implement batch tokenizer**

```moonbit
///|
pub fn tokenize(input : String) -> Array[@core.TokenInfo[Token]]!@core.LexError {
  @core.tokenize_via_steps(mini_step_lexer, input, EOF)
}
```

Check that `@core.tokenize_via_steps` exists with this signature. If not, implement a simple loop over `mini_step_lexer`.

- [ ] **Step B3: Run moon check**

Run: `moon check`

Expected: compiles.

### Step group C: Parser (recursive descent)

- [ ] **Step C1: Define LanguageSpec**

In `mini/parser.mbt`:

```moonbit
///|
let mini_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  parse_root=parse_root,
  reuse_size_threshold=0,
)
```

- [ ] **Step C2: Implement parse_root**

```moonbit
///|
fn parse_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_expr(ctx)
  if ctx.peek() != EOF {
    ctx.error("unexpected tokens after expression")
    ctx.skip_until(fn(t) { t == EOF })
  }
}
```

- [ ] **Step C3: Implement parse_expr (primary + method chain)**

```moonbit
///|
fn parse_expr(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(RootNode, fn() {
    parse_primary(ctx)
    // Method chain: .fast(n), .slow(n), .rev()
    while ctx.peek() == Dot {
      parse_method(ctx)
    }
  })
}

///|
fn parse_primary(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(PrimaryNode, fn() {
    match ctx.peek() {
      Ident(name) => {
        guard name == "s" || name == "note" else {
          ctx.error("expected 's' or 'note', got '" + name + "'")
          ctx.emit_error_placeholder()
          return
        }
        ctx.emit_token(IdentToken)          // s or note
        if ctx.peek() == LParen {
          ctx.emit_token(LParenToken)       // (
        } else {
          ctx.error("expected '(' after '" + name + "'")
          return
        }
        if ctx.peek() == Quote {
          ctx.emit_token(QuoteToken)        // opening "
          parse_notation(ctx)               // inner mini-notation
          if ctx.peek() == Quote {
            ctx.emit_token(QuoteToken)      // closing "
          } else {
            ctx.error("expected closing '\"'")
          }
        } else {
          ctx.error("expected '\"' after '('")
        }
        if ctx.peek() == RParen {
          ctx.emit_token(RParenToken)       // )
        } else {
          ctx.error("expected ')'")
        }
      }
      _ => {
        ctx.error("expected 's(\"...\")' or 'note(\"...\")'")
        ctx.emit_error_placeholder()
      }
    }
  })
}
```

- [ ] **Step C4: Implement parse_notation (inner mini-notation)**

```moonbit
///|
fn parse_notation(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(NotationNode, fn() {
    parse_layer(ctx)
    // Comma-separated = stack
    while ctx.peek() == Comma {
      ctx.emit_token(CommaToken)
      parse_layer(ctx)
    }
  })
}

///|
fn parse_layer(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(LayerNode, fn() {
    parse_element(ctx)
    // Space-separated elements = sequence (whitespace is trivia, so next token is just the next element)
    while is_element_start(ctx.peek()) {
      parse_element(ctx)
    }
  })
}

///|
fn is_element_start(t : Token) -> Bool {
  match t {
    Ident(_) | Number(_) | LBracket => true
    _ => false
  }
}

///|
fn parse_element(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  match ctx.peek() {
    LBracket => {
      ctx.node(GroupNode, fn() {
        ctx.emit_token(LBracketToken)   // [
        parse_notation(ctx)             // recursive
        if ctx.peek() == RBracket {
          ctx.emit_token(RBracketToken) // ]
        } else {
          ctx.error("expected ']'")
        }
      })
    }
    Ident(_) => {
      ctx.node(AtomNode, fn() {
        ctx.emit_token(IdentToken)
      })
    }
    Number(_) => {
      ctx.node(AtomNode, fn() {
        ctx.emit_token(NumberToken)
      })
    }
    _ => {
      ctx.error("expected sound name, number, or '['")
      ctx.emit_error_placeholder()
    }
  }
}
```

- [ ] **Step C5: Implement parse_method**

```moonbit
///|
fn parse_method(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(MethodNode, fn() {
    ctx.emit_token(DotToken)            // .
    match ctx.peek() {
      Ident(name) => {
        match name {
          "fast" | "slow" => {
            ctx.emit_token(IdentToken)  // fast or slow
            if ctx.peek() == LParen {
              ctx.emit_token(LParenToken)
            } else {
              ctx.error("expected '(' after '" + name + "'")
              return
            }
            match ctx.peek() {
              Number(_) => ctx.emit_token(NumberToken)
              _ => {
                ctx.error("expected positive number")
                ctx.emit_error_placeholder()
              }
            }
            if ctx.peek() == RParen {
              ctx.emit_token(RParenToken)
            } else {
              ctx.error("expected ')'")
            }
          }
          "rev" => {
            ctx.emit_token(IdentToken)  // rev
            if ctx.peek() == LParen {
              ctx.emit_token(LParenToken)
            } else {
              ctx.error("expected '(' after 'rev'")
              return
            }
            if ctx.peek() == RParen {
              ctx.emit_token(RParenToken)
            } else {
              ctx.error("expected ')'")
            }
          }
          _ => {
            ctx.error("unknown method '" + name + "', expected fast, slow, or rev")
            ctx.emit_error_placeholder()
          }
        }
      }
      _ => {
        ctx.error("expected method name after '.'")
        ctx.emit_error_placeholder()
      }
    }
  })
}
```

- [ ] **Step C6: Run moon check**

Run: `moon check`

Expected: compiles. Fix any type mismatches with loom/core API.

### Step group D: CST fold → Pat[ControlMap]

- [ ] **Step D1: Implement fold function**

In `mini/fold.mbt`:

```moonbit
///|
pub fn fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] {
  match SyntaxKind::from_raw(node.kind()) {
    RootNode => fold_root(node, recurse)
    PrimaryNode => fold_primary(node, recurse)
    MethodNode => @pattern.Pat::silence() // handled by fold_root
    NotationNode => fold_notation(node, recurse)
    LayerNode => fold_layer(node, recurse)
    GroupNode => fold_group(node, recurse)
    AtomNode => @pattern.Pat::silence() // handled by fold_layer context
    _ => @pattern.Pat::silence()
  }
}
```

The fold_root function handles the method chain by first folding the primary, then applying each method:

```moonbit
///|
fn fold_root(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @pattern.Pat[@pattern.ControlMap],
) -> @pattern.Pat[@pattern.ControlMap] {
  let mut pat = @pattern.Pat::silence()
  let mut primary_name = ""

  for child in node.children() {
    match SyntaxKind::from_raw(child.kind()) {
      PrimaryNode => {
        // Extract the function name (s or note)
        primary_name = child.token_text(IdentToken.to_raw())
        pat = fold_primary_with_name(child, recurse, primary_name)
      }
      MethodNode => {
        let method_name = child.token_text(IdentToken.to_raw())
        match method_name {
          "fast" => {
            let num_text = child.token_text(NumberToken.to_raw())
            let n = parse_positive_double(num_text)
            match n {
              Some(v) => pat = pat.fast(@pattern.Rational::from_double(v))
              None => () // validation error, keep pat unchanged
            }
          }
          "slow" => {
            let num_text = child.token_text(NumberToken.to_raw())
            let n = parse_positive_double(num_text)
            match n {
              Some(v) => pat = pat.slow(@pattern.Rational::from_double(v))
              None => ()
            }
          }
          "rev" => pat = pat.rev()
          _ => ()
        }
      }
      _ => ()
    }
  }
  pat
}
```

Note: Check if `Rational::from_double` exists. If not, for integer arguments use `Rational::from_int(v.to_int())`. For fractional, may need `Rational::new(num, den)` with manual conversion.

The fold_primary_with_name extracts the notation content and distinguishes `s()` vs `note()`:

```moonbit
///|
fn fold_primary_with_name(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @pattern.Pat[@pattern.ControlMap],
  name : String,
) -> @pattern.Pat[@pattern.ControlMap] {
  // Find the NotationNode child
  for child in node.children() {
    match SyntaxKind::from_raw(child.kind()) {
      NotationNode => return fold_notation_with_mode(child, recurse, name)
      _ => ()
    }
  }
  @pattern.Pat::silence()
}
```

The fold_notation_with_mode distinguishes between sound names (s) and MIDI numbers (note).

- [ ] **Step D2: Implement fold_notation_with_mode and fold_layer_with_mode**

These create the pattern structure — stacks for comma-separated layers, sequences for space-separated elements. The `mode` parameter determines how atoms are interpreted:

- `mode="s"`: atom text → drum_midi → `ControlMap` with "sound" key
- `mode="note"`: atom text → parse as double → `ControlMap` with "note" key

```moonbit
///|
fn fold_notation_with_mode(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @pattern.Pat[@pattern.ControlMap],
  mode : String,
) -> @pattern.Pat[@pattern.ControlMap] {
  let layers : Array[@pattern.Pat[@pattern.ControlMap]] = []
  for child in node.children() {
    match SyntaxKind::from_raw(child.kind()) {
      LayerNode => layers.push(fold_layer_with_mode(child, recurse, mode))
      _ => ()
    }
  }
  match layers.length() {
    0 => @pattern.Pat::silence()
    1 => layers[0]
    _ => @pattern.stack(layers)
  }
}

///|
fn fold_layer_with_mode(
  node : @seam.SyntaxNode,
  _recurse : (@seam.SyntaxNode) -> @pattern.Pat[@pattern.ControlMap],
  mode : String,
) -> @pattern.Pat[@pattern.ControlMap] {
  let elements : Array[@pattern.Pat[@pattern.ControlMap]] = []
  for child in node.children() {
    match SyntaxKind::from_raw(child.kind()) {
      AtomNode => {
        let text = get_atom_text(child)
        let pat = match mode {
          "s" => {
            match drum_midi(text) {
              Some(midi) => @pattern.Pat::pure(
                @pattern.ControlMap::from_map({"sound": midi.to_double()})
              )
              None => @pattern.Pat::silence() // unknown drum — error already reported
            }
          }
          _ => { // "note"
            match @strconv.parse_double?(text) {
              Ok(n) => @pattern.note(n)
              Err(_) => @pattern.Pat::silence()
            }
          }
        }
        elements.push(pat)
      }
      GroupNode => {
        // Recurse into [...] sub-group: find its NotationNode child
        for sub in child.children() {
          match SyntaxKind::from_raw(sub.kind()) {
            NotationNode => elements.push(fold_notation_with_mode(sub, _recurse, mode))
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  match elements.length() {
    0 => @pattern.Pat::silence()
    1 => elements[0]
    _ => @pattern.sequence(elements)
  }
}
```

Note: Check how to construct a `ControlMap` from a map. If there's no `from_map` constructor, check what's available — may need `single_control("sound", midi.to_double())` which returns `Pat[ControlMap]`, but that creates a `Pat`, not a raw `ControlMap`. If so, the atom expansion needs to use `Pat::pure` + raw ControlMap construction, or use the existing `note()` helper pattern. Adjust based on actual API.

- [ ] **Step D3: Run moon check**

Run: `moon check`

Expected: compiles. Fix any API mismatches.

### Step group E: Wire Grammar and public API

- [ ] **Step E1: Create Grammar and parse function**

In `mini/mini.mbt`:

```moonbit
///|
let mini_grammar : @loom.Grammar[Token, SyntaxKind, @pattern.Pat[@pattern.ControlMap]] =
  @loom.Grammar::new(
    spec=mini_spec,
    tokenize~,
    fold_node~,
    on_lex_error=fn(_msg) { @pattern.Pat::silence() },
    error_token=Some(Error("")),
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=mini_step_lexer)),
    block_reparse_spec=None,
  )

///|
pub fn parse(input : String) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  let (cst, diags) = mini_grammar.parse_cst(input)
  if diags.length() > 0 {
    return Err(format_diagnostic(diags[0]))
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let pat = mini_grammar.fold(syntax)
  Ok(pat)
}
```

Note: Verify `Grammar::parse_cst` and `Grammar::fold` signatures. The JSON example uses a separate `syntax_node_to_json` function rather than `grammar.fold`. Check actual API.

- [ ] **Step E2: Add validation in parse()**

Add pre-parse validation: reject empty input, validate that fast/slow arguments are positive.

```moonbit
///|
fn format_diagnostic(diag : @core.Diagnostic[Token]) -> String {
  // Extract position and message from diagnostic
  "parse error at position " + diag.offset.to_string() + ": " + diag.message
}
```

Check actual `Diagnostic` field names (`offset`, `message`, etc.).

- [ ] **Step E3: Run moon check**

Run: `moon check`

Expected: compiles.

### Step group F: Parser tests

- [ ] **Step F1: Write parser tests**

Add to `mini/mini_test.mbt`:

```moonbit
///|
test "parse s() with single sound" {
  let result = parse("s(\"bd\")")
  inspect!(result.is_ok(), content="true")
  let pat = result.unwrap()
  let events = pat.query(@pattern.TimeSpan::new(
    @pattern.Rational::new(0L, 1L),
    @pattern.Rational::new(1L, 1L),
  ))
  inspect!(events.length(), content="1")
  // Check the "sound" key has value 36.0 (bd)
  let cm = events[0].value
  inspect!(cm.to_map().get("sound"), content="Some(36)")
}

///|
test "parse s() with sequence" {
  let result = parse("s(\"bd sd hh sd\")")
  inspect!(result.is_ok(), content="true")
  let pat = result.unwrap()
  let events = pat.query(@pattern.TimeSpan::new(
    @pattern.Rational::new(0L, 1L),
    @pattern.Rational::new(1L, 1L),
  ))
  inspect!(events.length(), content="4")
}

///|
test "parse note() with numbers" {
  let result = parse("note(\"60 64 67\")")
  inspect!(result.is_ok(), content="true")
  let pat = result.unwrap()
  let events = pat.query(@pattern.TimeSpan::new(
    @pattern.Rational::new(0L, 1L),
    @pattern.Rational::new(1L, 1L),
  ))
  inspect!(events.length(), content="3")
}

///|
test "parse method chain fast" {
  let result = parse("s(\"bd sd\").fast(2)")
  inspect!(result.is_ok(), content="true")
  let pat = result.unwrap()
  // fast(2) doubles the speed: 2 events per half-cycle, so 4 in full cycle
  let events = pat.query(@pattern.TimeSpan::new(
    @pattern.Rational::new(0L, 1L),
    @pattern.Rational::new(1L, 1L),
  ))
  inspect!(events.length(), content="4")
}

///|
test "parse sub-group" {
  let result = parse("s(\"bd [sd hh]\")")
  inspect!(result.is_ok(), content="true")
  let pat = result.unwrap()
  let events = pat.query(@pattern.TimeSpan::new(
    @pattern.Rational::new(0L, 1L),
    @pattern.Rational::new(1L, 1L),
  ))
  // bd takes first half, [sd hh] splits second half: 3 events
  inspect!(events.length(), content="3")
}

///|
test "parse stack with comma" {
  let result = parse("s(\"bd sd, hh hh hh\")")
  inspect!(result.is_ok(), content="true")
  let pat = result.unwrap()
  let events = pat.query(@pattern.TimeSpan::new(
    @pattern.Rational::new(0L, 1L),
    @pattern.Rational::new(1L, 1L),
  ))
  // layer1: bd sd (2 events), layer2: hh hh hh (3 events) = 5 total
  inspect!(events.length(), content="5")
}

///|
test "parse error: unknown sound name" {
  let result = parse("s(\"snare\")")
  // This depends on whether unknown names cause a parse error or silent pattern.
  // If drum_midi returns None, the atom becomes silence.
  // For stricter validation, check during fold and report error.
  inspect!(result.is_ok(), content="true")
}

///|
test "parse error: empty input" {
  let result = parse("")
  inspect!(result.is_err(), content="true")
}

///|
test "parse error: invalid syntax" {
  let result = parse("foo(\"bar\")")
  inspect!(result.is_err(), content="true")
}

///|
test "parse error: fast with zero" {
  let result = parse("s(\"bd\").fast(0)")
  inspect!(result.is_err(), content="true")
}

///|
test "parse error: fast with negative" {
  let result = parse("s(\"bd\").fast(-1)")
  inspect!(result.is_err(), content="true")
}
```

- [ ] **Step F2: Run tests**

Run: `moon check && moon test -p dowdiness/moondsp/mini`

Expected: all pass. Debug and fix any failures — this is where API mismatches surface.

- [ ] **Step F3: Commit**

```bash
git add mini/
git commit -m "feat(mini): loom-based mini-notation parser"
```

---

## Task 3-alt: Hand-written parser (if loom fails)

**Only execute this if Task 0 fails.** Skip if loom works.

**Files:**
- Create: `mini/parser.mbt`
- Modify: `mini/mini.mbt`, `mini/moon.pkg`

- [ ] **Step 1: Simplify moon.pkg**

Remove loom/seam imports. Only import pattern:

```
import {
  "dowdiness/moondsp/pattern" @pattern,
}
```

Also remove loom/seam from `moon.mod.json`.

- [ ] **Step 2: Implement hand-written recursive descent parser**

In `mini/parser.mbt`, implement a simple parser struct:

```moonbit
///|
struct Parser {
  input : String
  mut pos : Int
}

///|
fn Parser::new(input : String) -> Parser {
  { input, pos: 0 }
}

///|
fn Parser::peek(self : Parser) -> Char? {
  if self.pos >= self.input.length() { None } else { Some(self.input[self.pos]) }
}

///|
fn Parser::advance(self : Parser) -> Unit {
  self.pos += 1
}

///|
fn Parser::skip_whitespace(self : Parser) -> Unit {
  while self.pos < self.input.length() && self.input[self.pos] == ' ' {
    self.pos += 1
  }
}

///|
fn Parser::read_ident(self : Parser) -> String {
  let start = self.pos
  while self.pos < self.input.length() && is_alpha_num(self.input[self.pos]) {
    self.pos += 1
  }
  self.input.substring(start~, end=self.pos)
}

///|
fn Parser::read_number(self : Parser) -> String {
  let start = self.pos
  while self.pos < self.input.length() && (is_digit(self.input[self.pos]) || self.input[self.pos] == '.') {
    self.pos += 1
  }
  self.input.substring(start~, end=self.pos)
}

///|
fn Parser::expect(self : Parser, ch : Char) -> Result[Unit, String] {
  match self.peek() {
    Some(c) if c == ch => { self.advance(); Ok(()) }
    Some(c) => Err("expected '" + ch.to_string() + "' at position " + self.pos.to_string() + ", got '" + c.to_string() + "'")
    None => Err("expected '" + ch.to_string() + "' at position " + self.pos.to_string() + ", got end of input")
  }
}
```

Then implement parse_expr, parse_primary, parse_notation, parse_layer, parse_element, parse_method following the same grammar as the loom version but directly returning `Pat[ControlMap]` instead of building a CST.

- [ ] **Step 3: Wire public API**

In `mini/mini.mbt`:

```moonbit
///|
pub fn parse(input : String) -> Result[@pattern.Pat[@pattern.ControlMap], String] {
  if input.length() == 0 {
    return Err("empty input")
  }
  let parser = Parser::new(input)
  let pat = parser.parse_expr()?
  if parser.pos < input.length() {
    return Err("unexpected characters at position " + parser.pos.to_string())
  }
  Ok(pat)
}
```

- [ ] **Step 4: Run existing tests**

Run: `moon check && moon test -p dowdiness/moondsp/mini`

Expected: all tests from Task 2 and Task 3 Step F1 pass (same test file, same public API).

- [ ] **Step 5: Commit**

```bash
git add mini/ moon.mod.json
git commit -m "feat(mini): hand-written mini-notation parser (loom fallback)"
```

---

## Task 4: Drum templates and multi-pool routing

**Files:**
- Modify: `browser/browser_scheduler.mbt`
- Modify: `browser/moon.pkg`

- [ ] **Step 1: Add mini import to browser/moon.pkg**

Add to imports:

```
"dowdiness/moondsp/mini" @mini,
```

Add new exports to both `"js"` and `"wasm-gc"` export lists:

```
"parse_and_set_pattern",
```

- [ ] **Step 2: Define drum templates**

In `browser/browser_scheduler.mbt`, add template functions:

```moonbit
///|
fn template_bd() -> Array[@lib.DspNode] {
  [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 60.0),
    @lib.DspNode::adsr(0.001, 0.15, 0.0, 0.1),
    @lib.DspNode::gain(1, 1.0),
    @lib.DspNode::output(2),
  ]
}

///|
fn template_sd() -> Array[@lib.DspNode] {
  [
    @lib.DspNode::noise(12345),
    @lib.DspNode::biquad(0, @lib.BiquadMode::BPF, 800.0, 2.0),
    @lib.DspNode::adsr(0.001, 0.08, 0.0, 0.05),
    @lib.DspNode::gain(2, 1.0),
    @lib.DspNode::output(3),
  ]
}

///|
fn template_hh() -> Array[@lib.DspNode] {
  [
    @lib.DspNode::noise(67890),
    @lib.DspNode::biquad(0, @lib.BiquadMode::HPF, 8000.0, 1.0),
    @lib.DspNode::adsr(0.001, 0.03, 0.0, 0.02),
    @lib.DspNode::gain(2, 1.0),
    @lib.DspNode::output(3),
  ]
}
```

Note: Verify `BiquadMode` enum variant names (`BPF` vs `Bandpass`, `HPF` vs `Highpass`). Check via `moon ide outline dsp/ | grep -i biquad`. Also verify DspNode constructor signatures — `noise` takes a seed (UInt), `biquad` takes (input_index, mode, cutoff, q). The node indices must form a valid chain (each node references its input by index).

- [ ] **Step 3: Run moon check**

Run: `moon check`

Expected: compiles. Fix any constructor mismatches.

- [ ] **Step 4: Implement multi-pool state**

Replace existing single-pool globals with multi-pool:

```moonbit
///|
struct PoolEntry {
  pool : @lib.VoicePool
  scheduler : @scheduler.PatternScheduler
  tmp_left : @lib.AudioBuffer
  tmp_right : @lib.AudioBuffer
}

///|
let pool_bd : @ref.Ref[PoolEntry?] = @ref.new(None)

///|
let pool_sd : @ref.Ref[PoolEntry?] = @ref.new(None)

///|
let pool_hh : @ref.Ref[PoolEntry?] = @ref.new(None)

///|
let pool_syn : @ref.Ref[PoolEntry?] = @ref.new(None)

///|
let sched_active_pattern : @ref.Ref[@pattern.Pat[@pattern.ControlMap]] = @ref.new(@pattern.Pat::silence())
```

- [ ] **Step 5: Rewrite init_scheduler_graph**

Create all 4 pools:

```moonbit
///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_graph()
    return false
  }
  let ctx = @lib.DspContext::new(sample_rate, block_size)

  // Helper to create a pool entry
  fn make_entry(
    template : Array[@lib.DspNode],
    bindings_result : Result[@lib.ControlBindingMap, @lib.ControlBindingError],
    ctx : @lib.DspContext,
    block_size : Int,
  ) -> PoolEntry? {
    match (bindings_result, @lib.VoicePool::new(template, ctx, max_voices=4)) {
      (Ok(bindings), Some(pool)) => {
        let scheduler = @scheduler.PatternScheduler::new(
          bpm=120.0, bindings~, ctx~,
        )
        Some(PoolEntry::{
          pool, scheduler,
          tmp_left: @lib.AudioBuffer::filled(block_size),
          tmp_right: @lib.AudioBuffer::filled(block_size),
        })
      }
      _ => None
    }
  }

  // Drum pools don't need note→freq binding (frequency is baked into template)
  let empty_bindings = @lib.ControlBindingBuilder::new().build([])
  // Actually: build against each template. Drums have no controllable params via pattern.
  let bd_tmpl = template_bd()
  let sd_tmpl = template_sd()
  let hh_tmpl = template_hh()
  let syn_tmpl = sched_template()

  // For drums: no bindings (fixed parameters)
  let bd_bindings = @lib.ControlBindingBuilder::new().build(bd_tmpl)
  let sd_bindings = @lib.ControlBindingBuilder::new().build(sd_tmpl)
  let hh_bindings = @lib.ControlBindingBuilder::new().build(hh_tmpl)

  // For synth: bind "note" to oscillator frequency
  let syn_bindings = @lib.ControlBindingBuilder::new()
    .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
    .build(syn_tmpl)

  pool_bd.val = make_entry(bd_tmpl, bd_bindings, ctx, block_size)
  pool_sd.val = make_entry(sd_tmpl, sd_bindings, ctx, block_size)
  pool_hh.val = make_entry(hh_tmpl, hh_bindings, ctx, block_size)
  pool_syn.val = make_entry(syn_tmpl, syn_bindings, ctx, block_size)

  sched_left.val = Some(@lib.AudioBuffer::filled(block_size))
  sched_right.val = Some(@lib.AudioBuffer::filled(block_size))
  sched_gain.val = 0.3

  // Set default pattern
  sched_active_pattern.val = @pattern.sequence([
    @pattern.Pat::pure(@pattern.ControlMap::from_entries([("sound", 36.0)])),
    @pattern.Pat::pure(@pattern.ControlMap::from_entries([("sound", 38.0)])),
    @pattern.Pat::pure(@pattern.ControlMap::from_entries([("sound", 42.0)])),
    @pattern.Pat::pure(@pattern.ControlMap::from_entries([("sound", 38.0)])),
  ])

  true
}
```

Note: Check how to construct ControlMap with arbitrary keys. If there's no `from_entries`, check the actual constructor. The default pattern should match `s("bd sd hh sd")` so sound plays immediately.

- [ ] **Step 6: Implement pattern splitting helpers**

```moonbit
///|
fn keep_sound(midi : Double) -> (@pattern.ControlMap) -> @pattern.ControlMap? {
  fn(cm) {
    match cm.to_map().get("sound") {
      Some(v) if v == midi => Some(cm)
      _ => None
    }
  }
}

///|
fn keep_note() -> (@pattern.ControlMap) -> @pattern.ControlMap? {
  fn(cm) {
    match cm.to_map().get("note") {
      Some(_) => Some(cm)
      _ => None
    }
  }
}
```

Check the actual accessor for ControlMap's inner map.

- [ ] **Step 7: Rewrite process_scheduler_block**

```moonbit
///|
pub fn process_scheduler_block() -> Bool {
  let left = match sched_left.val {
    Some(b) => b
    None => return false
  }
  let right = match sched_right.val {
    Some(b) => b
    None => return false
  }

  // Clear output buffers
  left.clear()
  right.clear()

  let pat = sched_active_pattern.val

  // Process each pool with its filtered sub-pattern
  fn process_pool(
    entry_ref : @ref.Ref[PoolEntry?],
    sub_pat : @pattern.Pat[@pattern.ControlMap],
    left : @lib.AudioBuffer,
    right : @lib.AudioBuffer,
  ) -> Unit {
    match entry_ref.val {
      None => ()
      Some(entry) => {
        entry.tmp_left.clear()
        entry.tmp_right.clear()
        entry.scheduler.process_block(sub_pat, entry.pool, entry.tmp_left, entry.tmp_right)
        // Accumulate into main buffers
        let len = left.length()
        for i = 0; i < len; i = i + 1 {
          left.set(i, left.get(i) + entry.tmp_left.get(i))
          right.set(i, right.get(i) + entry.tmp_right.get(i))
        }
      }
    }
  }

  process_pool(pool_bd, pat.filter_map(keep_sound(36.0)), left, right)
  process_pool(pool_sd, pat.filter_map(keep_sound(38.0)), left, right)
  process_pool(pool_hh, pat.filter_map(keep_sound(42.0)), left, right)
  process_pool(pool_syn, pat.filter_map(keep_note()), left, right)

  // Apply master gain
  let gain = sched_gain.val
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) * gain)
    right.set(i, right.get(i) * gain)
  }

  true
}
```

Check if `AudioBuffer` has a `clear()` method. If not, use a loop to zero it out.

- [ ] **Step 8: Implement parse_and_set_pattern**

```moonbit
///|
pub fn parse_and_set_pattern(text : String) -> String {
  match @mini.parse(text) {
    Ok(pat) => {
      sched_active_pattern.val = pat
      ""
    }
    Err(msg) => msg
  }
}
```

- [ ] **Step 9: Update set_scheduler_bpm to propagate to all pools**

```moonbit
///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  fn update(entry_ref : @ref.Ref[PoolEntry?], bpm : Double) {
    match entry_ref.val {
      None => ()
      Some(entry) => entry.scheduler.set_bpm(bpm)
    }
  }
  update(pool_bd, bpm)
  update(pool_sd, bpm)
  update(pool_hh, bpm)
  update(pool_syn, bpm)
}
```

- [ ] **Step 10: Remove old hardcoded pattern code**

Delete `sched_get_pattern`, `set_scheduler_pattern`, `sched_pattern_index`, and the old single-pool globals (`sched_pool`, `sched_scheduler`). Remove `set_scheduler_pattern` from browser/moon.pkg exports.

- [ ] **Step 11: Run moon check**

Run: `moon check`

Expected: compiles. Fix errors iteratively.

- [ ] **Step 12: Run all tests**

Run: `moon test`

Expected: all tests pass.

- [ ] **Step 13: Commit**

```bash
git add browser/ mini/
git commit -m "feat(browser): multi-pool drum routing with text pattern input"
```

---

## Task 5: Update browser UI and processor.js

**Files:**
- Modify: `web/index.html`
- Modify: `web/processor.js`

- [ ] **Step 1: Update index.html scheduler controls**

Replace the hardcoded pattern buttons section (lines 259-277 of `web/index.html`) with:

```html
<div id="schedulerControls" style="display: none; margin-top: 10px;">
  <div style="margin-bottom: 8px; display: flex; gap: 8px; align-items: center;">
    <input type="text" id="patternInput" value='s("bd sd hh sd").fast(2)'
           style="flex: 1; padding: 10px 14px; font-family: 'SFMono-Regular', Consolas, monospace;
                  font-size: 1rem; border: 1px solid var(--border); border-radius: 12px;
                  background: white; color: var(--ink);"
           placeholder='s("bd sd hh sd").fast(2)'>
    <button onclick="evalPattern()" style="padding: 10px 18px;">Eval</button>
  </div>
  <div id="patternStatus" style="margin-bottom: 8px; font-size: 0.88rem; color: rgba(29,27,24,0.7);"></div>
  <div style="margin-bottom: 8px;">
    <label>BPM: <span id="bpmValue">120</span></label>
    <input type="range" id="bpmSlider" min="60" max="240" value="120"
           oninput="setSchedulerBpm(this.value)">
  </div>
  <div style="margin-bottom: 8px;">
    <label>Gain: <span id="schedulerGainValue">0.30</span></label>
    <input type="range" id="schedulerGainSlider" min="0" max="100" value="30"
           oninput="setSchedulerGain(this.value / 100)">
  </div>
</div>
```

- [ ] **Step 2: Add evalPattern function**

In the `<script>` section, add:

```javascript
function evalPattern() {
  const text = document.getElementById('patternInput').value;
  if (node) {
    node.port.postMessage({ type: 'set-pattern-text', text: text });
  }
}

// Eval on Enter key
document.getElementById('patternInput')?.addEventListener('keydown', function(e) {
  if (e.key === 'Enter') {
    evalPattern();
  }
});
```

- [ ] **Step 3: Update processor.js message handling**

In the `port.onmessage` handler, add a case for `set-pattern-text`:

```javascript
} else if (data.type === "set-pattern-text") {
  if (this.usesScheduler && this.wasm && typeof this.wasm.parse_and_set_pattern === "function") {
    const error = this.wasm.parse_and_set_pattern(data.text);
    if (error === "") {
      this.port.postMessage({ type: "pattern-updated" });
    } else {
      this.port.postMessage({ type: "pattern-error", message: error });
    }
  }
}
```

Note: Check how MoonBit wasm-gc exports handle String return values. The wasm export `parse_and_set_pattern` returns a MoonBit String. In wasm-gc, this may need special handling — the JS side may receive a wasm-gc string reference, not a JS string. Check how existing string-returning exports work (if any). If strings can't cross the wasm boundary directly, change the return type to `Int` (0 = success, error code otherwise) and store the error message in a global that JS reads via a separate export.

- [ ] **Step 4: Handle pattern-updated/error messages in index.html**

In the `node.port.onmessage` handler in index.html, add:

```javascript
} else if (event.data?.type === "pattern-updated") {
  const statusEl = document.getElementById('patternStatus');
  if (statusEl) {
    statusEl.textContent = "Pattern updated";
    statusEl.style.color = "#577d21";
  }
} else if (event.data?.type === "pattern-error") {
  const statusEl = document.getElementById('patternStatus');
  if (statusEl) {
    statusEl.textContent = event.data.message;
    statusEl.style.color = "#c35a2b";
  }
}
```

- [ ] **Step 5: Auto-eval default pattern on scheduler start**

In the `startScheduler` function, after calling `start({ useScheduler: true })`, trigger initial pattern eval so the default pattern plays immediately:

```javascript
function startScheduler() {
  if (!audioContext) {
    document.getElementById('schedulerControls').style.display = 'block';
    document.querySelector('.controls').style.display = 'none';
    start({ useScheduler: true });
    // Eval default pattern after a short delay to ensure wasm is ready
    setTimeout(() => evalPattern(), 200);
  }
}
```

- [ ] **Step 6: Update page title for scheduler mode**

In the scheduler startup code:

```javascript
document.getElementById('pageTitle').innerHTML = 'MoonBit DSP<br>Pattern Sequencer';
document.getElementById('pageDesc').textContent =
  'Phase 5: type a pattern and hear it play. Try s("bd sd hh sd").fast(2), ' +
  'note("60 64 67"), or s("bd [sd hh], hh hh hh").';
```

- [ ] **Step 7: Commit**

```bash
git add web/
git commit -m "feat(web): text pattern input UI with eval"
```

---

## Task 6: Build, test, and verify in browser

**Files:** none (verification only)

- [ ] **Step 1: Run full test suite**

Run: `moon check && moon test`

Expected: all tests pass.

- [ ] **Step 2: Build wasm**

Run: `moon build --target wasm-gc`

Expected: builds without errors.

- [ ] **Step 3: Copy wasm to web/ and serve**

```bash
cp target/wasm-gc/release/build/browser/browser.wasm web/moonbit_dsp.wasm
```

Then serve `web/` (e.g., `npx serve web/` or `python3 -m http.server -d web/`).

- [ ] **Step 4: Manual browser test — success metric**

1. Open browser, navigate to served page
2. Click "Scheduler" button
3. Verify default pattern `s("bd sd hh sd").fast(2)` plays a drum beat
4. Verify distinct timbres: bd (low thump), sd (noisy snap), hh (high tick)
5. Verify BPM slider changes tempo
6. Verify gain slider changes volume

- [ ] **Step 5: Manual browser test — additional patterns**

1. Type `note("60 64 67")` and press Enter → hear 3-note arpeggio
2. Type `s("bd [sd hh]")` → hear bd on beat 1, sd+hh splitting beat 2
3. Type `s("bd sd, hh hh hh")` → hear stacked layers
4. Type `s("bd sd").slow(2)` → hear half-speed
5. Type `invalid!!!` → verify error message shown, old pattern keeps playing

- [ ] **Step 6: Fix any issues found**

If timbres are wrong, adjust ADSR values in drum templates. If timing is off, check scheduler synchronization. Run `moon check` after each fix.

- [ ] **Step 7: Run moon info and moon fmt**

```bash
moon info && moon fmt
```

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "feat: Phase 5 complete — text pattern to audible output in browser"
```

---

## Task 7: Update project documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: memory file

- [ ] **Step 1: Update CLAUDE.md project status**

Change the header line to reflect Phase 5 completion with the text-pattern pipeline.

- [ ] **Step 2: Update memory**

Update `project_phase5_brainstorm_progress.md` to record Phase 5 is fully complete with the text-pattern deliverable.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update project status for Phase 5 text pattern completion"
```
