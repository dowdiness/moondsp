#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
moon_home=${MOON_HOME:-$HOME/.moon}
cc=${WINDOWS_CC:-x86_64-w64-mingw32-gcc}
out_dir="$repo_root/_build/windows/release/clap"
payload_c="$repo_root/_build/native/release/build/clap_plugin/clap_plugin.c"
clap_include="$repo_root/third_party/clap/include"
output="$out_dir/moondsp-synth.clap"

if ! command -v "$cc" >/dev/null 2>&1; then
  cat >&2 <<EOF
Windows CLAP cross compiler not found: $cc

Install a MinGW-w64 x86_64 compiler and retry, or set WINDOWS_CC.
Examples:
  Ubuntu/Debian: sudo apt-get install gcc-mingw-w64-x86-64
  Homebrew:      brew install mingw-w64
  Custom:        WINDOWS_CC=/path/to/x86_64-w64-mingw32-gcc $0
EOF
  exit 1
fi
# Current toolchains split the runtime; older releases shipped one source.
if [[ -f "$moon_home/lib/runtime/runtime.c" ]]; then
  runtime_sources=(
    "$moon_home/lib/runtime/runtime.c"
    "$moon_home/lib/runtime/backtrace.c"
    "$moon_home/lib/runtime/env.c"
    "$moon_home/lib/runtime/sync_io.c"
    "$moon_home/lib/runtime/utf.c"
  )
else
  runtime_sources=("$moon_home/lib/runtime.c")
fi
for source in "${runtime_sources[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "MoonBit runtime source not found: $source" >&2
    exit 1
  fi
done
if [[ ! -f "$clap_include/clap/entry.h" ]]; then
  echo "Vendored CLAP headers not found under $clap_include" >&2
  exit 1
fi

NEW_MOON_MOD=0 MOONBIT_NEW_NATIVE=0 moon -C "$repo_root" build --target native --release clap_plugin
mkdir -p "$out_dir"

runtime_objects=()
for source in "${runtime_sources[@]}"; do
  object="$out_dir/moonbit_$(basename "${source%.c}").o"
  "$cc" -std=gnu11 -O2 -D_CRT_RAND_S -fwrapv -fno-strict-aliasing \
    -I"$moon_home/include" -c "$source" -o "$object"
  runtime_objects+=("$object")
done

"$cc" -std=gnu11 -O2 -shared \
  -I"$clap_include" \
  -I"$moon_home/include" \
  -o "$output" \
  "$repo_root/clap_plugin/moondsp_clap.c" \
  -include "$repo_root/clap_plugin/moondsp_clap_moonbit.h" \
  "$payload_c" \
  "${runtime_objects[@]}" \
  -static-libgcc \
  -Wl,--no-undefined \
  -lm

printf 'Built Windows CLAP %s\n' "$output"
