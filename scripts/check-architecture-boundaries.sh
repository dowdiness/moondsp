#!/usr/bin/env bash
#
# Audits moondsp package imports against the architectural dependency rules.
#
# This is intentionally manifest-based and explicit: MoonBit package manifests
# are the enforceable boundary. Additions to the package graph should update this
# script together with the ADR or design note that justifies the new edge.
#
# See docs/decisions/0015-graph-internal-boundaries-and-maintainability.md.

set -euo pipefail

violations=()

repo_import_re='^dowdiness/moondsp($|/)'

# Prints "mode import_path" rows for moondsp imports in a moon.pkg file.
# Mode is prod/test/wbtest. The parser is deliberately small and matches the
# import-block shape used in this repo; if package syntax changes, update the
# script rather than falling back to auto-discovery.
manifest_imports() {
  local manifest=$1
  if [[ ! -f "$manifest" ]]; then
    return 0
  fi
  awk '
    function reset_block() {
      delete imports
      import_count = 0
      in_import = 0
      block_mode = "prod"
    }
    BEGIN { reset_block() }
    /^[[:space:]]*import[[:space:]]*\{/ {
      in_import = 1
      block_mode = "prod"
      next
    }
    in_import {
      line = $0
      while (match(line, /"[^"]+"/)) {
        value = substr(line, RSTART + 1, RLENGTH - 2)
        imports[++import_count] = value
        line = substr(line, RSTART + RLENGTH)
      }
      if ($0 ~ /\}/) {
        if ($0 ~ /for[[:space:]]+"test"/) {
          block_mode = "test"
        } else if ($0 ~ /for[[:space:]]+"wbtest"/) {
          block_mode = "wbtest"
        }
        for (i = 1; i <= import_count; i++) {
          print block_mode " " imports[i]
        }
        reset_block()
      }
    }
  ' "$manifest" | while read -r mode import_path; do
    if [[ "$import_path" =~ $repo_import_re ]]; then
      printf '%s %s\n' "$mode" "$import_path"
    fi
  done
}

check_manifest() {
  local manifest=$1
  local prod_allowed_re=$2
  local test_allowed_re=${3:-$prod_allowed_re}
  local wbtest_allowed_re=${4:-$test_allowed_re}
  local json_manifest="${manifest}.json"
  if [[ ! -f "$manifest" ]]; then
    if [[ -f "$json_manifest" ]]; then
      violations+=("$json_manifest exists, but this architecture check only parses moon.pkg; add a moon.pkg manifest or extend scripts/check-architecture-boundaries.sh")
    fi
    return 0
  fi
  if [[ -f "$json_manifest" ]]; then
    violations+=("$manifest and $json_manifest both exist; architecture boundary checks require one manifest format per package")
  fi
  while read -r mode import_path; do
    if [[ -z "${import_path:-}" ]]; then
      continue
    fi
    local allowed_re=$prod_allowed_re
    case "$mode" in
      test) allowed_re=$test_allowed_re ;;
      wbtest) allowed_re=$wbtest_allowed_re ;;
    esac
    if ! [[ "$import_path" =~ $allowed_re ]]; then
      violations+=("$manifest ($mode) imports $import_path")
    fi
  done < <(manifest_imports "$manifest")
}

# Public package dependency rules. These reflect the current layered package
# architecture plus the facade exceptions documented in ADR-0001 and ADR-0015.
check_manifest \
  "moon.pkg" \
  '^(dowdiness/moondsp/(dsp|graph|identity|voice))$' \
  '^(dowdiness/moondsp/(mini|pattern))$'
check_manifest "dsp/moon.pkg" '^$'
check_manifest "identity/moon.pkg" '^$'
check_manifest "pattern/moon.pkg" '^(dowdiness/moondsp/identity)$'
check_manifest "song/moon.pkg" '^(dowdiness/moondsp/(identity|pattern))$'
check_manifest "mini/moon.pkg" '^(dowdiness/moondsp/(identity|pattern|song))$'
check_manifest "graph/moon.pkg" '^(dowdiness/moondsp/(dsp|identity|graph/internal/(model|template|binding|runtime|staging|authoring)))$'
check_manifest "voice/moon.pkg" '^(dowdiness/moondsp/(dsp|graph))$'
check_manifest "scheduler/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(identity|pattern|song))$'
check_manifest "browser/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(mini|scheduler|pattern|song))$'
check_manifest "browser_test/moon.pkg" '^(dowdiness/moondsp)$'
check_manifest "cmd/main/moon.pkg" '^$'

# Future graph internals. Absent manifests are skipped. These rules are the
# migration guardrails: runtime internals must not import graph authoring,
# scheduler, browser, mini, song, pattern, identity, or the root facade.
check_manifest "graph/internal/model/moon.pkg" '^(dowdiness/moondsp/dsp)$'
check_manifest "graph/internal/template/moon.pkg" '^(dowdiness/moondsp/(dsp|graph/internal/model))$'
check_manifest "graph/internal/binding/moon.pkg" '^(dowdiness/moondsp/graph/internal/(model|template))$'
check_manifest "graph/internal/runtime/moon.pkg" '^(dowdiness/moondsp/(dsp|graph/internal/(model|template)))$'
check_manifest "graph/internal/staging/moon.pkg" '^(dowdiness/moondsp/(dsp|graph/internal/(model|template|runtime)))$'
check_manifest "graph/internal/authoring/moon.pkg" '^(dowdiness/moondsp/(identity|graph/internal/(model|template|binding|runtime|staging)))$'

# Future scheduler/browser internals are intentionally looser for now than the
# graph rules. They document the next facade-plus-internals direction without
# blocking current production code paths.
check_manifest "scheduler/internal/transport/moon.pkg" '^(dowdiness/moondsp/(dsp|pattern))$'
check_manifest "scheduler/internal/playback/moon.pkg" '^(dowdiness/moondsp/(identity|pattern|song))$'
check_manifest "scheduler/internal/voice_runtime/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(identity|pattern|song))$'
check_manifest "scheduler/internal/edit_policy/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(identity|pattern|song))$'
check_manifest "browser/internal/slot/moon.pkg" '^(dowdiness/moondsp)$'
check_manifest "browser/internal/demo_templates/moon.pkg" '^(dowdiness/moondsp)$'
check_manifest "browser/internal/playback_host/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(mini|scheduler|pattern|song))$'

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: package imports violate architecture boundary rules:"
  printf '  %s\n' "${violations[@]}"
  echo ""
  echo "Either remove the dependency edge or update this script together with"
  echo "the ADR/design rationale that makes the new edge intentional."
  exit 1
fi

echo "OK: package imports match architecture boundary rules."
