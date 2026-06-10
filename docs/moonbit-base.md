# MoonBit Base Conventions

## Quick Reference

| When...                    | Use...                              | Not...                        |
|----------------------------|-------------------------------------|-------------------------------|
| Top-level fixed value      | `const`                             | `let`                         |
| Local immutable binding    | `let`                               | `const` (illegal in functions)|
| Mutable variable           | `let mut`                           |                               |
| Bail out early             | `guard`                             | `if ... { return }`           |
| Branch on variants         | `match`                             | chained `if/else`             |
| Option/Result inspection   | `match` or `x is Some(v)`           | `is_some()`/`is_none()` + unwrap |
| Filter/map a collection (cold path) | `Iter` chain or `[ for x in xs if cond => f(x) ]` | `let mut out = []` + push loop |
| First/last/shape of array  | view patterns `[head, ..tail]`      | `.length()` checks + indexing |
| String prefix/suffix/shape | `s.view()` + pattern match          | converting to `Array[Char]`   |
| Simple boolean             | `if/else`                           |                               |
| Struct construction        | custom `fn Type::Type(...)` constructor | bare `{ field: value }`       |
| Empty callback body        | `() => ()`                          | `() => {}` (map literal!)     |
| Tuple field access         | `.0`                                | `._` (deprecated)             |
| Fallible return type       | `T!Error` with `!` propagation      | `try?` (deprecated v0.10.0)    |
| Iteration                  | `for .. in`                         | `loop` (deprecated)           |
| Visibility default         | `pub`                               | `pub(all)` unless needed      |
| Re-export from dependency    | `pub using @pkg { type T }`       | manual wrapper functions      |
| Foreign trait + foreign type | newtype wrapper                   | direct impl (orphan rule)     |
| Unimplemented placeholder  | `...`                               | leaving in committed code     |
| Debugging derive           | `derive(Debug)` + manual `impl Show` for `inspect` | `derive(Show)` warns [0027] |
| Regex matching             | `s =~ re"pattern"`                  | `lexmatch`/`lexmatch?` (deprecated) |
| Reduce nesting in DSLs     | `<\|` reverse pipeline              | deeply nested parentheses     |

## MoonBit Code Search

Prefer `moon ide` over grep/glob for MoonBit-specific code search. These commands use compiler semantics instead of text matching.

```bash
moon ide peek-def SyncEditor              # Go-to-definition with context
moon ide peek-def -loc editor/foo.mbt:5   # Definition at cursor position
moon ide find-references SyncEditor       # All usages across codebase
moon ide outline editor/                  # Package structure overview
moon ide doc "String::*rev*"              # API discovery with wildcards
```

Common symbol forms:

```text
Symbol
@pkg.Symbol
Type::method
@pkg.Type::method
```

When to use: finding definitions, tracing usages, understanding package APIs, discovering methods. Falls back to grep only for non-MoonBit files or cross-language patterns.

### Convention Audit Commands

`moon ide` audits **semantic** properties (symbols, types, visibility). Grep audits **stylistic** choices (which keyword was used). Both are needed.

```bash
# Semantic audits (moon ide)
moon ide analyze <pkg> | grep "can be removed"       # Over-exposed pub(all)
moon ide analyze <pkg> | grep "usage: 0"             # Unused public APIs
moon ide outline <pkg> | grep ' | let '              # Top-level let → review if should be const
moon ide outline <pkg> | grep 'const'                # Verify const usage exists
moon ide find-references abort --loc <file:line>      # abort sites → potential guard candidates
moon ide doc --dump /tmp/symbols.jsonl                # Full symbol dump (NEVER pass a source file path — it overwrites!)

# Stylistic audits (grep — moon ide can't see keywords like return/if/guard)
grep -rn 'if .* { return' <pkg>/*.mbt                # guard candidates (early return)
grep -rn '() => {}' <pkg>/*.mbt                      # Empty callback anti-pattern
```

## Bindings & Visibility

- **`const`** for top-level compile-time constants. It is valid only at top level; functions use `let` for immutable local bindings. For a fixed value at module scope (magic numbers, sizes, thresholds, string keys), always use `const`.
  ```moonbit
  const MAX_SIZE = 1024      // correct — top-level fixed value → const
  const PREFIX = "incr"      // correct — top-level fixed string → const
  //! let MAX_SIZE = 1024    // wrong — use const for top-level fixed values

  fn main {
    let x = 10               // correct — immutable local binding
    let mut i = 10            // correct — mutable local binding
    //! const LOCAL = 10      // ILLEGAL — const cannot appear inside functions
  }
  ```
- **Visibility:** `pub` exposes a symbol to direct dependents only. `pub(all)` exposes it transitively to all downstream packages. `pub(open)` on enums allows downstream packages to add variants. Use `pub` by default; only use `pub(all)` for types/functions that downstream-of-downstream consumers need, and `pub(open)` only for intentionally extensible enums.
- **Constructor aliases:** `using @pkg { type T }` imports a constructor alias so `T(args)` works instead of `@pkg.T(args)`. `#alias(Name)` on a type definition creates a local alias. Both work with tuple structs, structs with custom constructors, and single-constructor errors.
  ```moonbit
  using @ref { type Ref }
  let r = Ref(42)             // instead of @ref.Ref(42)
  ```
- **Re-exports with `pub using`:** `pub using @pkg { type T, trait Trait, fn_name }` both re-exports symbols to consumers AND makes them available locally without prefix. Use this for facade packages that provide backward compatibility during package splits.
  ```moonbit
  // In facade package — re-exports all DSP types from @dsp
  pub using @dsp {
    type AudioBuffer,
    type DspContext,
    type Waveform,
    trait ArithSym,
    is_finite,
  }
  // Consumers of this package see AudioBuffer as if defined here.
  // Code within this package can use AudioBuffer without @dsp. prefix.
  ```
  **What works through `pub using`:** function calls, type annotations, method calls on re-exported types, trait bounds, enum pattern matching via `Type::Constructor`.

  **Enum constructor caveat:** bare enum constructors via `@pkg.Constructor` need a normal `using` import and type-qualified constructor form:

  ```moonbit
  using @pkg { type T }
  T::Constructor(args)
  ```

  This is standard MoonBit, not a `pub using` limitation. The `.mbti` interface shows re-exported types with their canonical origin (e.g., `@dsp.AudioBuffer`), but consumer code using the facade path still compiles.
- **Naming:** `snake_case` for functions, methods, variables, and modules. `PascalCase` for types, enums, and constructors. `SCREAMING_SNAKE_CASE` for `const` constants.

## Control Flow

- **Decision tree:**
  ```
  Need to bail out early (precondition, unwrap, validation)?
    ├── yes → guard (bool or pattern — keeps happy path unindented)
    └── no → Destructuring enum/Option/Result variants?
          ├── yes → match (exhaustive, compiler-checked)
          └── no → if/else (simple boolean)
  ```
  **`guard`** filters out the bad case so the rest of the function stays flat. Prefer `guard` over `if ... { return }` or nested `match` when only one branch exits early.
  ```moonbit
  guard opt is Some(x) else { return Err("missing") }
  guard n > 0 else { fail("n must be positive") }
  // happy path continues here — no nesting
  ```
  Note: `guard let Pattern = expr else { ... }` does NOT compile in current MoonBit — it parses as a Unit statement and the binder doesn't escape. Use the `<expr> is <Pattern>` form above.
- **Iteration:** `for .. in` with accumulator state. `loop` keyword is deprecated.
  ```moonbit
  // Preferred: for-in with accumulator
  for x in xs; sum = 0 {
    continue sum + x
  } nobreak { sum }

  // Also fine: for-in with mut for simple cases
  let mut acc = 0
  for i in 0..<n { acc += xs[i] }
  ```
- **Destructuring tuple-element arrays:** `for (a, b) in xs` is a parse error `[3002]` — `for .. in` binds identifiers, not patterns. For an `Array[(A, B)]`, both `for a, b in xs` and `xs.iter2()` yield **(index, element)** (`a : Int`, `b : (A, B)` — `Array::iter2() -> Iter2[Int, A]`), NOT the tuple components. To destructure the components, wrap the iterator in `Iter2` (a newtype over `Iter[(X, Y)]`, in prelude) — its two-binder `for` / `.each` yield `(X, Y)`. Otherwise destructure in the body. Tuple-pattern lambda params (`.each(((a, b)) => ...)`) are also a parse error.
  ```moonbit
  for a, b in Iter2(xs.iter()) { ... }       // a : A, b : B
  for p in xs { let (a, b) = p; ... }         // body destructure
  ```
- **List comprehensions (v0.9.2):** `[ for x in xs => f(x) ]` builds an array; add `if cond` before `=>` to filter. The same `[ for ... => ... ]` shape constructs `Array`, `String`, `Bytes`, or lazy `Iter` based on the target type. Control-flow constructs (`break`, `continue`, etc.) are not currently allowed inside the body.
  ```moonbit
  let doubled : Array[Int] = [ for x in xs => x * 2 ]
  let evens   : Array[Int] = [ for x in xs if x % 2 == 0 => x ]
  let iter    : Iter[Int]  = [ for x in xs => x ]      // typed context selects Iter
  ```
- **Iterator construction from literals (v0.9.2):** An array literal in a context expecting `Iter` becomes an `Iter`, but element expressions are still evaluated eagerly. The spread form `[ a, ..it, b ]` is what triggers lazy evaluation of `it`'s side effects.
- **Regex matching:** Use `s =~ re"pattern"` for regex. Patterns compose with `+` (concat), `|` (alternation), `as name` (captures), and `before=`/`after~` (surrounding text bindings).
  ```moonbit
  let s = "==abc=="
  let _ = s =~ re"abc"                                      // simple match
  let _ = s =~ (re"a" + re"bc", )                           // pattern composition
  let _ = s =~ (((re"x" as x) | re"b") + re"bc", before=y, after~) // captures + context
  ```
- **Reverse pipeline `<|`:** Reduces nesting in DSL/view code. `f <| args` is equivalent to `f(args)`. As of v0.9.2, `<|` also supports method-call receivers, threading the right-hand side as the last argument: `obj.method(a, b) <| last_arg` desugars to `obj.method(a, b, last_arg)`.
  ```moonbit
  fn view() -> Html {
    div <| [
      text("hello"),
      ul <| [ li("item 1"), li("item 2") ],
    ]
  }

  // v0.9.2 — method receiver on the LHS of <|
  buf.write_section("body") <| render(children)
  ```
- **StringView/ArrayView patterns:** Use `.view()` for prefix/suffix matching with `match`:
  ```moonbit
  match s.view() {
    [.."let", ..rest] => ...  // prefix match
    [a, ..rest, b] => ...     // first and last
    [] => ...                 // empty
  }
  ```

## Functions & Types

- **Arrow functions:** `() => expr` (zero params, single expression), `() => { stmts }` (multi-statement), `x => expr` (one param), `(x, y) => expr` (multiple params). Empty body: `() => ()` — not `() => {}` which MoonBit parses as a map literal. Named functions (`pub fn`, `fn name(...)`) are unaffected.
- **Custom constructors for structs:** Define a constructor method whose name matches the struct type: `fn Type::Type(...) -> Type`. This enables `Type(args)` construction syntax with labelled/optional parameters, validation, defaults, and `raise` when construction is fallible. Applies regardless of visibility — `pub`, `pub(all)`, and `priv` structs all benefit from consistent call syntax and future-proof validation hooks. Prefer this over bare struct literals `{ field: value }`.
  ```moonbit
  struct MyStruct {
    x : Int
    y : Int
  } derive(Debug)

  fn MyStruct::MyStruct(x~ : Int, y? : Int = x) -> MyStruct {
    { x, y }
  }

  let s = MyStruct(x=1)  // usage — like enum constructors
  ```
  **Generic structs** put type params on the constructor method.
  ```moonbit
  pub(all) struct Ref[T] {
    mut val : T
  }

  fn[T] Ref::Ref(value : T) -> Ref[T] { { val: value } }

  let r : Ref[Int] = Ref(42)
  ```
  **Cross-package / blackbox caveat:** the bare `Type(args)` sugar resolves only within the defining package. From another package (notably blackbox `*_test.mbt`, which is a separate package), it is unbound `[4021]` — qualify as `Type::Type(args)` (or `@pkg.Type::Type(args)`). Same constraint the enum-constructor bullet notes.
- **Trait impl:** `pub impl Trait for Type with method(self) { ... }` — one method per impl block
- **Orphan rule** (error 4061): can't impl foreign trait for foreign type — use a private newtype wrapper
- **Error handling:** use `Unit!Error` or `T!Error` for fallible return types. Normal calls auto-propagate errors (zero syntax cost). `try?` converts to `Result[T, E]` but is **deprecated as of v0.10.0** (warning [0020]) — see the migration bullet below. `abort` is NOT catchable — prefer `fail("msg")` for defect detection (catchable + source location). See `moonbit-error-handling` skill for full conventions (abort vs fail vs raise, boundary rules, error type design).
- **`try?` → `try/catch` migration (v0.10.0):** `try?` is deprecated; do NOT mechanically swap to `try expr |> Ok catch { e => Err(e) }` (the compiler discourages it). Handle the raising expression directly:
  - **Success-test guard** — a raise *is* the failure, so just call it: `guard (try? f(x)) is Ok(v)` → `let v = f(x)` (errors auto-propagate, or wrap the whole function body in one `try/catch`).
  - **Error-test guard** — capture as an `Option` to keep the **concrete** error type: `let captured = try { let _ = f(x); None } catch { e => Some(e) }` then `guard captured is Some(MyError(..))`. Putting `fail()`/another raising call *inside* the same `try` widens the catch binder to the supertype `Error`, costing you variant matching and `.message()` (error [4015] "Type Error has no method message").
  - moonfmt canonicalizes a single-expression `try { x } catch { ... }` to the postfix form `x catch { ... }`.
- **TODO syntax:** `...` is a placeholder for unimplemented code. It type-checks as any type but aborts at runtime. Do not leave `...` in committed code.
- **Newtype wrappers (v0.9.2):** Use `struct T(Underlying)` for single-field wrappers. The old `type T Underlying` newtype declaration was removed in v0.9.2.
- **Local mutual recursion (v0.9.2):** Local `fn name(...)` bindings no longer form a mutually recursive group implicitly (top-level `fn` declarations are unaffected). Use `letrec name = fn(...) { ... } and name2 = fn(...) { ... }`:
  ```moonbit
  fn outer() -> Bool {
    letrec even = fn(n : Int) -> Bool {
      if n == 0 { true } else { odd(n - 1) }
    }
    and odd = fn(n : Int) -> Bool {
      if n == 0 { false } else { even(n - 1) }
    }
    even(4)
  }
  ```

## Testing

- **Files:** `*_test.mbt` (blackbox), `*_wbtest.mbt` (whitebox), `*_benchmark.mbt`
- **Assertions:** Use `inspect` for snapshots, `@qc` for properties
- **Panic tests:** name starts with `"panic "` — test runner expects `abort()`
- **Blackbox tests** cannot construct internal structs — use whitebox tests or expose constructors
- **Block-style:** Code organized in `///|` separated blocks
- **Format:** Always `moon info && moon fmt` before committing

## Pitfalls

- `._` syntax is deprecated — use `.0` for tuple access
- `ref` and `protected` are reserved keywords — do not use as variable/field/parameter names. `protected` rejection surfaces as Warning [0035].
- `Ref::new(x)` does NOT exist — core/ref exposes `Ref::Ref(x)` and standalone `@ref.new(x)`; idiomatic form is `Ref(x)` (calls the `Ref::Ref` constructor)
- `@hashmap.HashMap::new()` is `#deprecated` — use `@hashmap.HashMap([])` (the `HashMap::HashMap(ArrayView)` constructor with an empty array)
- `() => {}` is a map literal rather than an empty function body; use `() => ()`
- `loop` keyword is deprecated — use `for .. in`
- `try?` does not catch `abort` (and `try?` itself is deprecated as of v0.10.0 — [0020]; migrate to `try/catch`, see Error handling)
- For cross-target builds, use per-file conditional compilation rather than `supported-targets` in moon.pkg.json
- `derive(Show)` on containers (tuple/array/map/set/Option/Result) is deprecated in v0.9.2 — use `derive(Debug)` for diagnostics and `@debug.assert_eq(...)` for test assertions. `Show::output` is now consistent with `Show::to_string` (both unquoted) for `String`/`Char`
- Old `type T Underlying` newtype no longer compiles — use `struct T(Underlying)`
- Local mutually recursive `fn` no longer works — use `letrec`

## Code Changes & Review

- Before suggesting code removal, check if symbols are re-exported as public API for downstream consumers. Do not delete structs/types that appear unused internally but may be part of the library's public interface.
- Never dismiss a review request — always do a thorough line-by-line review even if changes seem minor
- Check for: integer overflow, zero/negative inputs, boundary validation, generation wrap-around
- Do not suggest deleting public API types (Id structs, etc.) as 'unused' — they may be needed by downstream consumers
- Verify method names match actual API before writing tests (e.g., check if it's `insert` vs `add_local_op`)

## Development Workflow

### Performance Optimization Rule

Before designing any performance optimization, write a microbenchmark that **reproduces the claimed bottleneck** in isolation. If the benchmark can't demonstrate the problem, stop and re-evaluate. Stale profiling data and O(bad) complexity are not proof of a real problem.

### Incremental Edit Rule

**CRITICAL:** After every file edit, run `moon check` before proceeding to the next file. If there are errors, fix them immediately before continuing with the plan.

### Standard Workflow

1. Make edits
2. `moon check` — Lint
3. `moon test` — Run tests
4. `moon test --update` — Update snapshots (if behavior changed)
5. `moon prove` — Verify `proof_ensure` properties (if `proof-enabled: true` in moon.pkg)
6. `moon info` — Update `.mbti` interfaces
7. Check `git diff *.mbti` — Verify API changes
8. `moon fmt` — Format

### Workspace Commands

For multi-project workspaces (monorepos with multiple `moon.mod.json`):
- `moon work init` — Initialize a workspace
- `moon work use <path>` — Add a project to the workspace
- `moon work sync` — Sync dependencies across workspace members

### v0.9.2 Toolchain Updates

- **Per-member preferred-target:** Workspace builds (`moon build`, `moon test`) now respect each member's declared `preferred-target`, so mixed frontend/backend projects can build in a single command.
- **`moon run -c '<script>'`:** Execute a snippet without creating a file. Useful for one-off probes inside a project.
- **Path-based `moon run`:** `moon run path/to/project` resolves the project from the given path; no longer requires running from the project root or passing `--manifest-path`.
- **Native LSP:** `moon lsp` ships an OCaml-based LSP binary. Enable in VS Code with `"moonbit.nativeLsp": true`.
- **`MOON_WORK` env var:** Override the `moon.work` location, or set `MOON_WORK=off` to disable workspace behavior for a single invocation.
- **Experimental `moon.mod`:** A new configuration file format replacing `moon.mod.json`. Set `NEW_MOON_MOD=1` to migrate automatically. Build rules move from `options("pre-build": ...)` in `moon.pkg` to structured `rule()` / `dev_build()` declarations in `moon.mod`, reusable across packages.

## Git & PR Workflow

- Always check if git is initialized before running git commands
- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- When merging PRs, always verify CI status is passing rather than skipped before proceeding. Never represent CI as green if any checks were skipped or failed.
- After rebasing or refactoring, verify file paths haven't shifted unexpectedly. Run `git diff --stat` to confirm only intended files changed.
