#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
moon_home=${MOON_HOME:-$HOME/.moon}
cc=${WINDOWS_CC:-x86_64-w64-mingw32-gcc}
out_dir="$repo_root/_build/windows/release/clap"
payload_c="$repo_root/_build/native/release/build/clap_plugin/clap_plugin.c"
clap_include="$repo_root/third_party/clap/include"
runtime_obj="$out_dir/moonbit_runtime_windows.o"
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
if [[ ! -f "$moon_home/lib/runtime.c" ]]; then
  echo "MoonBit runtime.c not found under MOON_HOME=$moon_home" >&2
  exit 1
fi
if [[ ! -f "$clap_include/clap/entry.h" ]]; then
  echo "Vendored CLAP headers not found under $clap_include" >&2
  exit 1
fi

moon -C "$repo_root" build --target native --release clap_plugin
"$repo_root/scripts/generate-clap-moonbit-header.sh" \
  --check \
  "$payload_c" \
  "$repo_root/clap_plugin/moondsp_clap_moonbit.h"
mkdir -p "$out_dir"

"$cc" -std=gnu11 -O2 \
  -I"$moon_home/include" \
  -c "$moon_home/lib/runtime.c" \
  -o "$runtime_obj"

"$cc" -std=gnu11 -O2 -shared \
  -I"$clap_include" \
  -I"$moon_home/include" \
  -o "$output" \
  "$repo_root/clap_plugin/moondsp_clap.c" \
  "$payload_c" \
  "$runtime_obj" \
  -static-libgcc \
  -Wl,--no-undefined \
  -lm

printf 'Built Windows CLAP %s\n' "$output"
