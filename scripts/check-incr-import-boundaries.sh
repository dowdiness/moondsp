#!/usr/bin/env bash
#
# Audits production MoonBit package manifests for over-broad dowdiness/incr
# imports. Vocabulary-only consumers may use dowdiness/incr/types for trait and
# Revision vocabulary, but must not import the full dowdiness/incr facade unless
# they own real reactive runtime cells.
#
# Full-facade carve-outs are intentionally explicit and ADR-referenced below.
# Additions must update this script together with the design rationale.
#
# See docs/decisions/0001-layered-package-architecture.md and
# docs/decisions/0011-incr-backed-mini-authoring-pipeline.md.

set -euo pipefail

violations=()

# Packages whose incr usage is vocabulary-only. If they import any incr package,
# dowdiness/incr/types is the only allowed incr import.
declare -A VOCABULARY_ONLY_PACKAGES=(
  ["pattern/moon.pkg"]="PatternDoc only implements incr/types BackdateEq + HasChangedAt vocabulary; it must not depend on the reactive runtime."
)

# Packages allowed to import the full dowdiness/incr facade. Each entry must name
# the ADR/design note that justifies owning Scope/Signal/Memo/Observer runtime
# cells instead of only importing dowdiness/incr/types.
declare -A FULL_FACADE_CARVEOUTS=(
  ["mini/moon.pkg"]="ADR-0011: MiniAuthoringPipeline owns incr Scope, Signal, Memo, and Observer cells."
)

manifest_imports() {
  local manifest=$1
  awk '
    {
      line = $0
      while (match(line, /"[^"]+"/)) {
        value = substr(line, RSTART + 1, RLENGTH - 2)
        print value
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$manifest"
}

production_manifests() {
  find . \
    \( -path './.git' -o -path './.mooncakes' -o -path './_build' -o -path './.worktrees' -o -path './specs' -o -path './node_modules' \) -prune \
    -o -name moon.pkg -type f -print \
    | sed 's#^./##' \
    | sort
}

while IFS= read -r manifest; do
  [[ -n "$manifest" ]] || continue
  mapfile -t imports < <(manifest_imports "$manifest")

  for import_path in "${imports[@]}"; do
    case "$import_path" in
      dowdiness/incr)
        if [[ -z "${FULL_FACADE_CARVEOUTS[$manifest]:-}" ]]; then
          violations+=("$manifest imports full dowdiness/incr facade without a documented full-runtime carve-out")
        fi
        ;;
      dowdiness/incr/*)
        # Sub-package imports are checked below for vocabulary-only packages.
        ;;
    esac
  done

  if [[ -n "${VOCABULARY_ONLY_PACKAGES[$manifest]:-}" ]]; then
    for import_path in "${imports[@]}"; do
      case "$import_path" in
        dowdiness/incr/types)
          ;;
        dowdiness/incr|dowdiness/incr/*)
          violations+=("$manifest is vocabulary-only but imports $import_path; use dowdiness/incr/types instead. ${VOCABULARY_ONLY_PACKAGES[$manifest]}")
          ;;
      esac
    done
  fi
done < <(production_manifests)

for manifest in "${!VOCABULARY_ONLY_PACKAGES[@]}"; do
  if [[ ! -f "$manifest" ]]; then
    violations+=("guarded vocabulary-only package manifest is missing: $manifest")
  fi
done

for manifest in "${!FULL_FACADE_CARVEOUTS[@]}"; do
  if [[ ! -f "$manifest" ]]; then
    violations+=("full incr facade carve-out points at missing manifest: $manifest")
  fi
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: incr import boundary violations:"
  printf '  %s\n' "${violations[@]}"
  echo ""
  echo "Vocabulary-only packages must import dowdiness/incr/types, not the full dowdiness/incr runtime facade."
  echo "If a package genuinely owns incr runtime cells, add it to FULL_FACADE_CARVEOUTS with an ADR/design-note reference."
  exit 1
fi

echo "OK: incr imports use narrow sub-packages or documented full-runtime carve-outs."
