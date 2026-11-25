#!/usr/bin/env bats
# Tests for .github/scripts/check-shophub-rbac.sh (spec 004 T023 Role drift check).

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-shophub-rbac.sh"
  CHART="$BATS_TEST_DIRNAME/../../charts/shophub"
  M="$BATS_TEST_TMPDIR/shophub-rbac.yaml"
  # The tested manifest as the shophub repo holds it (no labels, comments allowed).
  cat > "$M" <<'YAML'
# comment-only lines are fine
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: shophub
  namespace: shops
rules:
  - apiGroups: ["shophub.io"]
    resources: ["shops", "wallets", "discordchannels"]
    verbs: ["get", "list", "watch", "create", "patch", "delete"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: shophub
  namespace: shops
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: shophub
subjects:
  - kind: ServiceAccount
    name: shophub
    namespace: shophub
YAML
}

@test "passes when the chart renders the tested rules" {
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shophub RBAC OK"* ]]
}

@test "order of rules, verbs and resources and extra labels don't matter" {
  yq -i 'select(.kind == "Role").rules |= reverse' "$M"
  yq -i 'select(.kind == "Role").rules[0].verbs |= reverse' "$M"
  yq -i 'select(.kind == "Role").metadata.labels = {"x": "y"}' "$M"
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -eq 0 ]
}

@test "fails when the tested Role has a verb the chart lacks (or the other way round)" {
  yq -i 'select(.kind == "Role").rules[1].verbs += ["list"]' "$M"
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs"* ]]
  [[ "$output" == *'"list"'* ]]
}

@test "fails on a different resource" {
  yq -i 'select(.kind == "Role").rules[0].resources = ["shops", "wallets"]' "$M"
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -ne 0 ]
}

@test "fails on a different namespace or subject" {
  yq -i 'select(.kind == "RoleBinding").subjects[0].namespace = "elsewhere"' "$M"
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -ne 0 ]
}

@test "fails when the chart renders an RBAC object the manifest doesn't have" {
  # Remove the RoleBinding from the manifest: the chart still renders one.
  yq -i 'del(select(.kind == "RoleBinding"))' "$M"
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -ne 0 ]
}

@test "fails on a manifest without RBAC objects" {
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n' > "$M"
  run bash "$SCRIPT" "$CHART" "$M"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no RBAC objects"* ]]
}

@test "usage error without arguments" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
