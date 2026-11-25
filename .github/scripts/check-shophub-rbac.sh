#!/usr/bin/env bash
# Role drift check (spec 004 T023): the shophub chart's RBAC must equal the manifest the shophub
# k3s tests assert (shophub-spec: tests/ShopHub.Api.Tests/Integration/K3s/Manifests/shophub-rbac.yaml).
#
# Usage: check-shophub-rbac.sh CHART_DIR MANIFEST
#
# Renders CHART_DIR with default values as release "shophub" in namespace "shophub" (as deployed),
# keeps every Role, RoleBinding, ClusterRole and ClusterRoleBinding from both sides, and compares
# them after normalising: YAML to JSON, labels and annotations dropped, rule lists and their
# apiGroups/resources/verbs sorted, subjects sorted. Any difference (an extra verb, resource,
# subject, object or ClusterRole) fails with a diff. Requires helm, yq v4 and jq.
set -euo pipefail

(($# == 2)) || { echo "usage: check-shophub-rbac.sh CHART_DIR MANIFEST" >&2; exit 2; }
CHART="$1"
MANIFEST="$2"
[[ -f "$MANIFEST" ]] || { echo "ERROR: manifest not found: $MANIFEST" >&2; exit 2; }

normalise() { # stdin: YAML stream -> canonical JSON of the RBAC objects in it
  yq eval-all -o=json -I=0 \
    'select(.kind == "Role" or .kind == "RoleBinding" or .kind == "ClusterRole" or .kind == "ClusterRoleBinding")' - \
    | jq -S -s '
        map({
          kind,
          name: .metadata.name,
          namespace: (.metadata.namespace // null),
          rules: ((.rules // []) | map({
            apiGroups: ((.apiGroups // []) | sort),
            resources: ((.resources // []) | sort),
            resourceNames: ((.resourceNames // []) | sort),
            nonResourceURLs: ((.nonResourceURLs // []) | sort),
            verbs: ((.verbs // []) | sort)
          }) | sort),
          roleRef: (.roleRef // null),
          subjects: ((.subjects // []) | sort_by(.kind, (.namespace // ""), .name))
        })
        | sort_by(.kind, (.namespace // ""), .name)'
}

rendered="$(helm template shophub "$CHART" --namespace shophub | normalise)"
expected="$(normalise < "$MANIFEST")"

if [[ "$(jq length <<<"$expected")" -eq 0 ]]; then
  echo "ERROR: $MANIFEST contains no RBAC objects" >&2
  exit 1
fi

if [[ "$rendered" != "$expected" ]]; then
  echo "ERROR: the shophub chart's RBAC differs from the tested manifest $MANIFEST" >&2
  diff <(jq . <<<"$expected") <(jq . <<<"$rendered") --label "tested (shophub k3s manifest)" --label "chart (rendered)" -u >&2 || true
  exit 1
fi
echo "shophub RBAC OK: the chart renders exactly the tested Role and RoleBinding"
