#!/usr/bin/env bats
# Tests for .github/scripts/check-layout.sh (FR-001–FR-004).

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-layout.sh"
  ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$ROOT"
  touch "$ROOT/README.md"
  for c in shop shop-operator shophub-discord shophub; do
    mkdir -p "$ROOT/charts/$c/templates"
    printf 'apiVersion: v2\nname: %s\nversion: 0.1.0\n' "$c" > "$ROOT/charts/$c/Chart.yaml"
    echo '{}' > "$ROOT/charts/$c/values.yaml"
    touch "$ROOT/charts/$c/templates/NOTES.txt"
  done
  mkdir -p "$ROOT/charts/shophub/charts"
  for f in _helpers.tpl deployment.yaml hpa.yaml ingress.yaml service.yaml serviceaccount.yaml; do
    touch "$ROOT/charts/shophub/templates/$f"
  done
}

@test "passes on the correct tree" {
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "fails when README.md is missing" {
  rm "$ROOT/README.md"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "fails when a chart lacks Chart.yaml" {
  rm "$ROOT/charts/shop/Chart.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shop/Chart.yaml"* ]]
}

@test "fails when a chart lacks values.yaml" {
  rm "$ROOT/charts/shop-operator/values.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shop-operator/values.yaml"* ]]
}

@test "fails when a chart lacks templates/" {
  rm -r "$ROOT/charts/shophub-discord/templates"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shophub-discord/templates"* ]]
}

@test "fails when an allow-listed chart is missing" {
  rm -r "$ROOT/charts/shop"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shop"* ]]
}

@test "fails when charts/shophub/charts/ is missing" {
  rm -r "$ROOT/charts/shophub/charts"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shophub/charts"* ]]
}

@test "fails when a shophub template is missing" {
  rm "$ROOT/charts/shophub/templates/hpa.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hpa.yaml"* ]]
}

@test "fails when shophub templates has an extra file" {
  touch "$ROOT/charts/shophub/templates/configmap.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"configmap.yaml"* ]]
}

@test "fails when shophub templates has an extra directory" {
  mkdir -p "$ROOT/charts/shophub/templates/tests"
  touch "$ROOT/charts/shophub/templates/tests/test-connection.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tests"* ]]
}

@test "fails when a Chart.yaml exists outside charts/" {
  mkdir -p "$ROOT/other/foo"
  touch "$ROOT/other/foo/Chart.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"other/foo/Chart.yaml"* ]]
}

@test "fails when charts/ contains a chart not on the allow-list" {
  mkdir -p "$ROOT/charts/bitcoin/templates"
  touch "$ROOT/charts/bitcoin/Chart.yaml" "$ROOT/charts/bitcoin/values.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bitcoin"* ]]
}

@test "fails on a parallel top-level folder" {
  mkdir -p "$ROOT/helm"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"helm"* ]]
}

@test "allows hidden top-level folders such as .github" {
  mkdir -p "$ROOT/.github/workflows"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "allows a subchart inside charts/shophub/charts/" {
  mkdir -p "$ROOT/charts/shophub/charts/dep"
  touch "$ROOT/charts/shophub/charts/dep/Chart.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "reports every problem, not only the first" {
  rm "$ROOT/README.md" "$ROOT/charts/shophub/templates/hpa.yaml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
  [[ "$output" == *"hpa.yaml"* ]]
}
