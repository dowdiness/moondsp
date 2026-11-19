#!/usr/bin/env bash

set -eu

root_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
web_dir="$root_dir/web"
port="${1:-8080}"

"$root_dir/scripts/build-web-wasm.sh"

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
