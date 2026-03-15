#!/usr/bin/env bash

set -eu

root_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
web_dir="$root_dir/web"
port="${1:-8090}"

"$root_dir/playwright-sync-wasm.sh"

cd "$web_dir"
python3 -m http.server "$port" --bind 127.0.0.1
