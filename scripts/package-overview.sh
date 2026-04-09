#!/usr/bin/env bash
# package-overview.sh — compact package map via moon ide outline
# Run by SessionStart hook to give Claude a live view of the project.

set -euo pipefail

echo "=== mdsp package overview ==="
echo ""

for pkg in lib pattern scheduler browser browser_test cmd/main; do
  if [ -d "$pkg" ]; then
    echo "--- $pkg ---"
    moon ide outline "$pkg" 2>/dev/null | head -30
    echo ""
  fi
done

echo "--- / (root) ---"
moon ide outline . 2>/dev/null | head -20
echo ""
echo "=== end ==="
