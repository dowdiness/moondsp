#!/usr/bin/env bash
#
# Cloudflare Pages build script for the live REPL (web/live).
#
# Cloudflare's default Pages build environment ships Node + npm but not
# MoonBit, and only installs root-level npm deps — so the build needs
# to bootstrap the MoonBit toolchain and install web/live's own deps
# before running the Vite build, which compiles the engine itself.
#
# Configure in Cloudflare Pages dashboard:
#   Build command:        bash scripts/cloudflare-build.sh
#   Build output dir:     web/live/dist
#   Root directory:       (repo root)

set -euo pipefail

# Keep deployment on the toolchain tested by GitHub Actions.
export NEW_MOON_MOD=0

echo "── Installing MoonBit toolchain ───────────────────────"
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- 0.10.21+06da1ed44
export PATH="$HOME/.moon/bin:$PATH"
moon version || true

echo "── Fetching MoonBit dependencies ──────────────────────"
moon update

echo "── Installing web/live npm dependencies ───────────────"
cd web/live
npm clean-install --no-audit --no-fund

echo "── Building web/live (Vite) ───────────────────────────"
npm run build

echo "── Done ───────────────────────────────────────────────"
ls -lh dist/ | head
