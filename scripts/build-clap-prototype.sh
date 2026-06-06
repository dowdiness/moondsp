#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
moon_home=${MOON_HOME:-$HOME/.moon}
cc=${CC:-cc}
out_dir="$repo_root/_build/native/release/clap"
payload_c="$repo_root/_build/native/release/build/clap_plugin/clap_plugin.c"
runtime_pic="$out_dir/moonbit_runtime_pic.o"
output="$out_dir/moondsp-synth.clap"

if [[ ! -f "$moon_home/lib/runtime.c" ]]; then
  echo "MoonBit runtime.c not found under MOON_HOME=$moon_home" >&2
  exit 1
fi

moon -C "$repo_root" build --target native --release clap_plugin
if ! grep -q '_M0FP39dowdiness7moondsp10clap__host14engine__create' "$payload_c"; then
  echo "Expected MoonBit CLAP host bridge symbol not found in $payload_c" >&2
  echo "moondsp_clap_moonbit.h may be stale for this MoonBit toolchain/package name." >&2
  exit 1
fi
mkdir -p "$out_dir"

"$cc" -std=gnu11 -fPIC \
  -I"$moon_home/include" \
  -c "$moon_home/lib/runtime.c" \
  -o "$runtime_pic"

"$cc" -std=gnu11 -shared -fPIC \
  -I"$repo_root/clap_plugin" \
  -I"$moon_home/include" \
  -o "$output" \
  "$repo_root/clap_plugin/moondsp_clap.c" \
  "$payload_c" \
  "$runtime_pic" \
  "$moon_home/lib/libmoonbitrun.o" \
  "$moon_home/lib/moonbit_simdutf.o" \
  "$moon_home/lib/simdutf.o" \
  "$moon_home/lib/libbacktrace.a" \
  -lm

printf 'Built %s\n' "$output"
