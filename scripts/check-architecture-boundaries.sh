#!/usr/bin/env bash
#
# Audits moondsp package imports and public facade boundaries against the
# architectural dependency rules.
#
# This is intentionally explicit: MoonBit package manifests and generated public
# interfaces are the enforceable boundary. Additions to the package graph or
# public facade should update this script together with the ADR or design note
# that justifies the new edge.
#
# See docs/decisions/0015-graph-internal-boundaries-and-maintainability.md.

set -euo pipefail

violations=()

# Regenerate public interfaces before checking facade-level re-export rules.
moon info --quiet

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
check_manifest "scheduler/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(identity|pattern|song|scheduler/internal/(model|transport|playback|voice_runtime|edit_policy)))$'
check_manifest "browser/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(scheduler|browser/internal/(slot|demo_templates|playback_host)))$'
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

# Scheduler and browser internals are intentionally looser for now than the
# graph rules. They document the facade-plus-internals direction without
# blocking current production code paths.
check_manifest "scheduler/internal/model/moon.pkg" '^(dowdiness/moondsp/(identity|pattern))$'
check_manifest "scheduler/internal/transport/moon.pkg" '^(dowdiness/moondsp/(dsp|pattern))$'
check_manifest "scheduler/internal/playback/moon.pkg" '^(dowdiness/moondsp/(identity|pattern|song))$'
check_manifest "scheduler/internal/voice_runtime/moon.pkg" '^(dowdiness/moondsp/(identity|pattern|voice))$'
check_manifest "scheduler/internal/edit_policy/moon.pkg" '^(dowdiness/moondsp/identity)$'
check_manifest "browser/internal/slot/moon.pkg" '^(dowdiness/moondsp)$'
check_manifest "browser/internal/demo_templates/moon.pkg" '^(dowdiness/moondsp)$'
check_manifest "browser/internal/playback_host/moon.pkg" '^(dowdiness/moondsp|dowdiness/moondsp/(mini|scheduler|pattern|song))$'

# Graph is not a secondary DSP facade. It may expose graph APIs whose signatures
# mention @dsp types, but it must not publicly re-export DSP package types,
# traits, or helper functions. The root dowdiness/moondsp facade remains the
# intended combined public surface.
declare -A dsp_public_values=()
if [[ -f "dsp/pkg.generated.mbti" ]]; then
  while IFS= read -r name; do
    if [[ -n "$name" ]]; then
      dsp_public_values["$name"]=1
    fi
  done < <(
    awk '
      /^\/\/ Values/ { in_values = 1; next }
      /^\/\/ / && in_values { exit }
      in_values && /^pub fn/ {
        line = $0
        sub(/^pub fn(\[[^]]+\])?[[:space:]]+/, "", line)
        sub(/\(.*/, "", line)
        print line
      }
    ' "dsp/pkg.generated.mbti"
  )
fi

if [[ -f "graph/pkg.generated.mbti" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^pub[[:space:]]using[[:space:]]@dsp ]]; then
      violations+=("graph/pkg.generated.mbti re-exports DSP through graph: $line")
    fi
    if [[ "$line" =~ ^pub[[:space:]]fn ]]; then
      graph_fn=$(echo "$line" | sed -E 's/^pub fn(\[[^]]+\])?[[:space:]]+//; s/\(.*$//')
      if [[ "$graph_fn" != *::* && -n "${dsp_public_values[$graph_fn]:-}" ]]; then
        violations+=("graph/pkg.generated.mbti re-exports DSP helper through graph: $line")
      fi
    fi
  done < "graph/pkg.generated.mbti"
fi

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: architecture boundary violations:"
  printf '  %s\n' "${violations[@]}"
  echo ""
  echo "Either remove the dependency/public-surface leak or update this script"
  echo "together with the ADR/design rationale that makes the edge intentional."
  exit 1
fi

scripts/check-graph-model-facade-parity.sh

echo "OK: architecture boundaries match rules."
