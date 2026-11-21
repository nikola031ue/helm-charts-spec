#!/usr/bin/env bash
# PR check: every changed chart has a valid, increased SemVer version that is not yet published
# (FR-006, FR-007; research.md R9).
# Env: BASE_REF (default origin/$GITHUB_BASE_REF, else origin/main).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_REF="${BASE_REF:-origin/${GITHUB_BASE_REF:-main}}"
git rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null || die "base ref '$BASE_REF' not found (fetch-depth: 0?)"
MERGE_BASE="$(git merge-base "$BASE_REF" HEAD)"

errors=()
checked=0
for d in charts/*/; do
  [[ -f "$d/Chart.yaml" ]] || continue
  c="$(basename "$d")"
  path="charts/$c"

  # Changed in this PR (vs the merge base, including uncommitted work)?
  if git diff --quiet "$MERGE_BASE" -- "$path" \
     && [[ -z "$(git ls-files --others --exclude-standard -- "$path")" ]]; then
    continue
  fi
  checked=$((checked + 1))

  v="$(chart_field "$d/Chart.yaml" version)"
  if ! semver_valid "$v"; then
    errors+=("$path: version '$v' is not valid SemVer 2.0")
    continue
  fi

  new_chart=true
  if base_yaml="$(git show "$BASE_REF:$path/Chart.yaml" 2>/dev/null)"; then
    new_chart=false
    base_v="$(chart_field /dev/stdin version <<<"$base_yaml")"
    if semver_valid "$base_v" && ! semver_gt "$v" "$base_v"; then
      errors+=("$path: version $v must be greater than $base_v on $BASE_REF — bump Chart.yaml version")
      continue
    fi
  fi

  status="$(registry_status "$c" "$v")"
  case "$status" in
    published) errors+=("$path: version $v is already published to $OCI_BASE/$c — bump Chart.yaml version") ;;
    notfound)  log "$path: $v not yet published — OK" ;;
    missing)
      if $new_chart; then
        log "$path: new chart, package does not exist yet — OK"
      else
        errors+=("$path: registry denied access to $OCI_BASE/$c (package private?). See quickstart.md \"Make packages public\"")
      fi ;;
    *) errors+=("$path: could not query $OCI_BASE/$c --version $v (registry error)") ;;
  esac
done

if ((${#errors[@]})); then
  for e in "${errors[@]}"; do printf 'ERROR: %s\n' "$e" >&2; done
  exit 1
fi
echo "version check OK: $checked changed chart(s)"
