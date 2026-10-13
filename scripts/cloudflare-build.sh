#!/usr/bin/env bash
#
# Cloudflare Pages build script for the live REPL (web/live).
#
# Cloudflare's default Pages build environment ships Node + npm but not
# MoonBit, and only installs root-level npm deps — so the build needs
# to (1) bootstrap the MoonBit toolchain and compile the browser wasm,
# (2) sync the wasm into web/, and (3) install web/live's own deps
# before running the Vite build.
#
# Configure in Cloudflare Pages dashboard:
#   Build command:        bash scripts/cloudflare-build.sh
#   Build output dir:     web/live/dist
#   Root directory:       (repo root)

set -euo pipefail

# Keep deployment on the toolchain tested by GitHub Actions.
export NEW_MOON_MOD=0

echo "── Installing MoonBit toolchain ───────────────────────"
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- 0.10.14+7d59c7ec9
export PATH="$HOME/.moon/bin:$PATH"
moon version || true

echo "── Fetching MoonBit dependencies ──────────────────────"
moon update

echo "── Building browser wasm (release) ────────────────────"
moon build browser --target wasm-gc --release

echo "── Syncing wasm into web/ ─────────────────────────────"
./playwright-sync-wasm.sh

echo "── Installing web/live npm dependencies ───────────────"
cd web/live
npm clean-install --no-audit --no-fund

echo "── Building web/live (Vite) ───────────────────────────"
npm run build

echo "── Done ───────────────────────────────────────────────"
ls -lh dist/ | head
