#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git -C "${BASH_SOURCE[0]%/*}/.." rev-parse --show-toplevel)
BASE_COMMIT=${BASE_COMMIT:-c62774961895f2b2fd7b96adf448672df93527ad}
TARGET=${TARGET:-wasm-gc}
OUTPUT=${OUTPUT:-/tmp/moondsp-delayline-reset-ab-$(date +%Y%m%d-%H%M%S).txt}

if ! git -C "$ROOT" cat-file -e "${BASE_COMMIT}^{commit}"; then
  printf 'unknown BASE_COMMIT: %s\n' "$BASE_COMMIT" >&2
  exit 2
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/moondsp-delayline-reset-baseline.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT

mkdir "$TEMP_ROOT/baseline"
git -C "$ROOT" archive HEAD | tar -x -C "$TEMP_ROOT/baseline"
git -C "$ROOT" show "${BASE_COMMIT}:dsp/delay.mbt" > "$TEMP_ROOT/baseline/dsp/delay.mbt"
if [ -d "$ROOT/.mooncakes" ]; then
  cp -a "$ROOT/.mooncakes" "$TEMP_ROOT/baseline/.mooncakes"
fi

run_bench() {
  local label=$1
  local directory=$2
  printf '\n===== %s =====\n' "$label"
  printf 'directory: %s\n' "$directory"
  printf 'source delay.mbt: %s\n' "$label"
  (cd "$directory" && NEW_MOON_MOD=0 moon bench --release --target "$TARGET" dsp/delay_benchmark.mbt)
}

{
  printf 'DelayLine focused candidate/baseline comparison\n'
  printf 'target: %s\n' "$TARGET"
  printf 'command: NEW_MOON_MOD=0 moon bench --release --target %s dsp/delay_benchmark.mbt\n' "$TARGET"
  printf 'candidate: HEAD %s\n' "$(git -C "$ROOT" rev-parse HEAD)"
  printf 'baseline: %s (physical buffer reset)\n' "$BASE_COMMIT"
  printf 'benchmark: current HEAD dsp/delay_benchmark.mbt, including capacity-scaled warmup\n'
  run_bench candidate "$ROOT"
  run_bench baseline "$TEMP_ROOT/baseline"
} | tee "$OUTPUT"

printf '\nSaved comparison to %s\n' "$OUTPUT" >&2
