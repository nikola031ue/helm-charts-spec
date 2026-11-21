#!/usr/bin/env bash
# Enforce the Requirement 5.3 layout of the helm-charts repository (FR-001–FR-004, Principle I).
# Usage: check-layout.sh [REPO_ROOT]   (default: current directory)
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="${1:-.}"
cd "$ROOT"

errors=()
err() { errors+=("$1"); }

SHOPHUB_TEMPLATES=(NOTES.txt _helpers.tpl deployment.yaml hpa.yaml ingress.yaml service.yaml serviceaccount.yaml)

[[ -f README.md ]] || err "missing README.md at repository root"
[[ -d charts ]] || err "missing charts/ directory"

# Only charts/ may be a visible top-level directory (no parallel layouts).
for entry in */; do
  [[ -d "$entry" ]] || continue
  name="${entry%/}"
  [[ "$name" == charts ]] || err "unexpected top-level directory: $name/ (only charts/ is allowed)"
done

is_allowed() {
  local c
  for c in "${ALLOWED_CHARTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
  return 1
}

if [[ -d charts ]]; then
  for entry in charts/* charts/.[!.]*; do
    [[ -e "$entry" ]] || continue
    name="${entry#charts/}"
    if [[ ! -d "$entry" ]]; then
      err "unexpected file in charts/: $entry"
    elif ! is_allowed "$name"; then
      err "chart not on allow-list: $entry (allowed: ${ALLOWED_CHARTS[*]})"
    fi
  done

  for c in "${ALLOWED_CHARTS[@]}"; do
    d="charts/$c"
    if [[ ! -d "$d" ]]; then err "missing chart folder: $d"; continue; fi
    [[ -f "$d/Chart.yaml" ]] || err "missing $d/Chart.yaml"
    [[ -f "$d/values.yaml" ]] || err "missing $d/values.yaml"
    [[ -d "$d/templates" ]] || err "missing $d/templates/"
  done

  d=charts/shophub
  if [[ -d "$d" ]]; then
    [[ -d "$d/charts" ]] || err "missing $d/charts/"
    if [[ -d "$d/templates" ]]; then
      for f in "${SHOPHUB_TEMPLATES[@]}"; do
        [[ -f "$d/templates/$f" ]] || err "missing $d/templates/$f"
      done
      for entry in "$d"/templates/* "$d"/templates/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="${entry##*/}"
        found=false
        for f in "${SHOPHUB_TEMPLATES[@]}"; do [[ "$f" == "$base" && -f "$entry" ]] && found=true; done
        $found || err "unexpected entry in $d/templates/: $base"
      done
    fi
  fi
fi

# A Chart.yaml may only live at charts/<name>/Chart.yaml or charts/<name>/charts/<sub>/Chart.yaml.
while IFS= read -r f; do
  f="${f#./}"
  if [[ ! "$f" =~ ^charts/[^/]+/Chart\.yaml$ && ! "$f" =~ ^charts/[^/]+/charts/[^/]+/Chart\.yaml$ ]]; then
    err "Chart.yaml outside the allowed layout: $f"
  fi
done < <(find . -path ./.git -prune -o -name Chart.yaml -type f -print)

if ((${#errors[@]})); then
  for e in "${errors[@]}"; do printf 'ERROR: %s\n' "$e" >&2; done
  printf 'layout check failed: %d problem(s)\n' "${#errors[@]}" >&2
  exit 1
fi
echo "layout OK: README.md, charts/{${ALLOWED_CHARTS[*]}}"
