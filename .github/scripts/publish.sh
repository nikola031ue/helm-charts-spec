#!/usr/bin/env bash
# Publish every chart version that is not yet in the registry; never overwrite (FR-008).
# Must run logged in to ghcr.io (helm registry login). Usage: publish.sh [REPO_ROOT]
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "${1:-.}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pushed=0 skipped=0 failed=0
for d in charts/*/; do
  [[ -f "$d/Chart.yaml" ]] || continue
  c="$(basename "$d")"
  v="$(chart_field "$d/Chart.yaml" version)"
  semver_valid "$v" || { log "ERROR: charts/$c: invalid version '$v'"; failed=$((failed + 1)); continue; }

  case "$(registry_status "$c" "$v")" in
    published)
      echo "skip   $c $v (already published)"; skipped=$((skipped + 1)) ;;
    notfound|missing)
      out="$work/$c"; mkdir -p "$out"
      helm package "charts/$c" --destination "$out" >/dev/null
      pkg="$(ls "$out"/*.tgz)"
      helm push "$pkg" "$OCI_BASE"
      echo "pushed $c $v -> $OCI_BASE/$c"; pushed=$((pushed + 1)) ;;
    *)
      log "ERROR: charts/$c: registry error — not pushing (no blind overwrite)"; failed=$((failed + 1)) ;;
  esac
done

echo "publish: $pushed pushed, $skipped skipped, $failed failed"
((failed == 0))
