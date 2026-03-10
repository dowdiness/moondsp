#!/usr/bin/env bash

set -eu

root_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
build_dir="$root_dir/_build/wasm-gc/release/build"
web_dir="$root_dir/web"

mkdir -p "$web_dir"

wasm_path="$build_dir/mdsp.wasm"

if [ ! -f "$wasm_path" ]; then
  echo "No wasm-gc build artifact found at $wasm_path" >&2
  echo "Run: moon build --target wasm-gc --release" >&2
  exit 1
fi

cp "$wasm_path" "$web_dir/moonbit_dsp.wasm"
echo "Copied $(basename "$wasm_path") to $web_dir/moonbit_dsp.wasm"

cd "$web_dir"
python3 -m http.server 8080
