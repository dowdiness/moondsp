#!/usr/bin/env bash

set -eu

root_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
build_dir="$root_dir/_build/wasm-gc/release/build"
web_dir="$root_dir/web"

mkdir -p "$web_dir"

wasm_path="$build_dir/browser/browser.wasm"
test_wasm_path="$build_dir/browser_test/browser_test.wasm"

if [ ! -f "$wasm_path" ]; then
  echo "No wasm-gc build artifact found at $wasm_path" >&2
  echo "Run: moon build browser --target wasm-gc --release" >&2
  exit 1
fi

cp "$wasm_path" "$web_dir/moonbit_dsp.wasm"

if [ -f "$test_wasm_path" ]; then
  cp "$test_wasm_path" "$web_dir/moonbit_dsp_test.wasm"
fi
