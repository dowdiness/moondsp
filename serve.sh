#!/usr/bin/env bash

set -eu

root_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
build_dir="$root_dir/_build/wasm-gc/release/build"
web_dir="$root_dir/web"
port="${1:-8080}"

mkdir -p "$web_dir"

wasm_path="$build_dir/mdsp.wasm"

if [ ! -f "$wasm_path" ]; then
  echo "No wasm-gc build artifact found at $wasm_path" >&2
  echo "Run: moon build --target wasm-gc --release" >&2
  exit 1
fi

cp "$wasm_path" "$web_dir/moonbit_dsp.wasm"
echo "Copied $(basename "$wasm_path") to $web_dir/moonbit_dsp.wasm"

find_free_port() {
  python3 - "$1" <<'PY'
import socket
import sys

port = int(sys.argv[1])

while True:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        port += 1
    else:
        sock.close()
        print(port)
        break
PY
}

port="$(find_free_port "$port")"
echo "Serving web demo at http://127.0.0.1:$port"

cd "$web_dir"
python3 -m http.server "$port" --bind 127.0.0.1
