#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
plugin_id=${CLAP_PLUGIN_ID:-com.dowdiness.moondsp.synth}
validator_version=${CLAP_VALIDATOR_VERSION:-0.3.2}
platform=$(uname -s)
plugin=${1:-$repo_root/_build/native/release/clap/moondsp-synth.clap}
validator=${CLAP_VALIDATOR:-}

usage() {
  cat >&2 <<EOF
usage: scripts/validate-clap-prototype.sh [plugin.clap]

Builds the moondsp CLAP prototype, downloads a pinned clap-validator if needed,
and validates the plugin with clap-validator.

Environment:
  CLAP_VALIDATOR          Path to an existing clap-validator binary
  CLAP_VALIDATOR_VERSION  Checksummed release version to download when CLAP_VALIDATOR
                          is unset (default/currently supported: $validator_version)
  CLAP_PLUGIN_ID          Plugin id to validate
                          (default: $plugin_id)
EOF
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ -z "$validator" ]]; then
  cache_dir="$repo_root/_build/tools/clap-validator/$validator_version/$platform"
  validator="$cache_dir/clap-validator"
  if [[ ! -x "$validator" ]]; then
    case "$validator_version:$platform" in
      0.3.2:Linux)
        asset="clap-validator-0.3.2-ubuntu-18.04.tar.gz"
        asset_sha256="1476ed68f5657e76050e0c4f19790c02d819ecc62c35fd465059d21f05169cb1"
        ;;
      0.3.2:Darwin)
        asset="clap-validator-0.3.2-macos-universal.tar.gz"
        asset_sha256="3750f3729adfd8489f2b29019f7f2ed65ba71bf9d5049735f6a2ca0fccb18ffd"
        ;;
      *)
        echo "Unsupported clap-validator download for $validator_version on $platform" >&2
        echo "Install clap-validator and set CLAP_VALIDATOR=/path/to/clap-validator." >&2
        exit 1
        ;;
    esac
    url="https://github.com/free-audio/clap-validator/releases/download/$validator_version/$asset"
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    mkdir -p "$cache_dir"
    curl -L --fail --retry 3 -o "$tmp_dir/$asset" "$url"
    if command -v sha256sum >/dev/null 2>&1; then
      actual_sha256=$(sha256sum "$tmp_dir/$asset" | awk '{ print $1 }')
    elif command -v shasum >/dev/null 2>&1; then
      actual_sha256=$(shasum -a 256 "$tmp_dir/$asset" | awk '{ print $1 }')
    else
      echo "Need sha256sum or shasum to verify downloaded clap-validator" >&2
      exit 1
    fi
    if [[ "$actual_sha256" != "$asset_sha256" ]]; then
      echo "Checksum mismatch for downloaded clap-validator asset: $asset" >&2
      echo "expected $asset_sha256" >&2
      echo "actual   $actual_sha256" >&2
      exit 1
    fi
    tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"
    found=$(find "$tmp_dir" -type f -name clap-validator -print -quit)
    if [[ -z "$found" ]]; then
      echo "Downloaded clap-validator archive did not contain a clap-validator binary" >&2
      exit 1
    fi
    cp "$found" "$validator"
    chmod +x "$validator"
  fi
elif [[ ! -x "$validator" ]]; then
  echo "CLAP_VALIDATOR is not executable: $validator" >&2
  exit 1
fi

"$repo_root/scripts/build-clap-prototype.sh"

if [[ ! -f "$plugin" ]]; then
  echo "CLAP plugin not found: $plugin" >&2
  exit 1
fi

"$validator" validate \
  --plugin-id "$plugin_id" \
  --only-failed \
  --no-parallel \
  "$plugin"

printf 'CLAP validator passed for %s with %s\n' "$plugin" "$validator"
