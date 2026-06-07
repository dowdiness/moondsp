# CLAP native bridge symbol probe

Issue: #174

## Toolchain tested

```text
moon 0.1.20260522 (4a0c52f 2026-05-22) ~/.moon/bin/moon
moonc v0.9.3+b53c2807d (2026-05-26) ~/.moon/bin/moonc
moonrun 0.1.20260522 (4a0c52f 2026-05-22) ~/.moon/bin/moonrun
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

## Probe

The probe checked whether the current native target can emit an explicit stable
C alias for a primitive public function. It used a temporary main package with a
native export alias:

```moonbit
options(
  "is-main": true,
  link: {
    "native": {
      "exports": ["add_one:mb_add_one"],
    },
  },
)
```

```mbt
///|
pub fn add_one(x : Int) -> Int { x + 1 }

///|
fn main { ignore(add_one(1)) }
```

The dry run confirmed that `moon` forwards the requested alias to the native
link step:

```text
moonc link-core ... -target native '-exported_functions=add_one:mb_add_one'
```

The generated native C and linked executable did not contain either the original
source name or requested alias as a C symbol:

```text
$ rg -n "add_one|mb_add_one|add__one" _build/native/release/build/cmd/main/main.c
547:int32_t _M0FP49dowdiness21native__export__probe3cmd4main8add__one(int32_t);
549:int32_t _M0FP49dowdiness21native__export__probe3cmd4main8add__one(

$ nm -g _build/native/release/build/cmd/main/main.exe | grep -E 'add_one|mb_add_one|add__one'
000000000001a030 T _M0FP49dowdiness21native__export__probe3cmd4main8add__one
```

## Result

Unsupported for the current CLAP bridge. `link.native.exports` reaches
`moonc link-core`, but the native C payload still exposes only package-mangled
MoonBit symbols. Because even a main-package primitive export does not produce a
stable alias, `clap_host` bridge primitives cannot currently replace
`clap_plugin/moondsp_clap_moonbit.h` with direct stable declarations.

Keep `scripts/generate-clap-moonbit-header.sh` as the durable bridge-symbol
guard. `scripts/build-clap-prototype.sh` and
`scripts/build-clap-prototype-windows.sh` should continue to fail closed when
the checked-in generated header is stale for the MoonBit payload.

## Recheck trigger

Repeat this probe after MoonBit native toolchain upgrades. If native C aliases
appear, the smallest migration is:

1. add stable `mb_engine_*` native exports in the CLAP payload package, using
   forwarding wrappers if imported `clap_host` functions cannot be exported
   directly;
2. replace `clap_plugin/moondsp_clap_moonbit.h` with direct stable
   declarations;
3. remove or repurpose `scripts/generate-clap-moonbit-header.sh` so the build
   verifies those stable aliases instead of discovering package-mangled names;
4. rerun the CLAP build, smoke, validator, and allocation-audit gates.
