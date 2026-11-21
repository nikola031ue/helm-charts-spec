#!/usr/bin/env bats
# Tests for .github/scripts/publish.sh (FR-008).

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/publish.sh"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  : > "$STUB_LOG"
  ROOT="$BATS_TEST_TMPDIR/repo"
  for c in shop shophub; do
    mkdir -p "$ROOT/charts/$c/templates"
    printf 'apiVersion: v2\nname: %s\nversion: 0.1.0\n' "$c" > "$ROOT/charts/$c/Chart.yaml"
  done
  cd "$ROOT"
}

@test "version already in registry -> skip, no package, no push" {
  HELM_SHOW_DEFAULT=published run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
  ! grep -q "^helm push" "$STUB_LOG"
  ! grep -q "^helm package" "$STUB_LOG"
}

@test "version not found -> package and push to the project registry" {
  HELM_SHOW_DEFAULT=notfound run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "^helm package charts/shop" "$STUB_LOG"
  grep -q "^helm push .* oci://ghcr.io/nikola031ue/charts$" "$STUB_LOG"
  [ "$(grep -c '^helm push' "$STUB_LOG")" -eq 2 ]
}

@test "package does not exist yet (denied) -> package and push" {
  HELM_SHOW_DEFAULT=published HELM_SHOW_SHOPHUB=denied run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^helm push' "$STUB_LOG")" -eq 1 ]
  grep -q "^helm package charts/shophub" "$STUB_LOG"
}

@test "registry error -> fail and never push (no blind overwrite)" {
  HELM_SHOW_DEFAULT=error run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  ! grep -q "^helm push" "$STUB_LOG"
}
