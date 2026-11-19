#!/usr/bin/env bash
#
# Builds the engine and its test probe for the demo pages served from web/.
# (web/live builds its own copy in scripts/sync-assets.mjs.)

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
build_dir="$repo_dir/_build/wasm-gc/release/build"
web_dir="$repo_dir/web"

(cd "$repo_dir" && NEW_MOON_MOD=0 moon build browser browser_test --target wasm-gc --release)

cp "$build_dir/browser/browser.wasm" "$web_dir/moonbit_dsp.wasm"
cp "$build_dir/browser_test/browser_test.wasm" "$web_dir/moonbit_dsp_test.wasm"
