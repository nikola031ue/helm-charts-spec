#!/usr/bin/env bats
# Tests for .github/scripts/check-version.sh (FR-006, FR-007; research.md R9).
# Uses a real temporary git repo for base/head and a stub helm for the registry.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-version.sh"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  export HELM_SHOW_DEFAULT=notfound
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" && cd "$REPO"
  git init -q -b main .
  git config user.email t@example.com && git config user.name test
  for c in shop shophub; do write_chart "$c" 0.1.0; done
  git add -A && git commit -qm base
  git switch -qc feature
  export BASE_REF=main
}

write_chart() {
  mkdir -p "charts/$1/templates"
  printf 'apiVersion: v2\nname: %s\nversion: %s\n' "$1" "$2" > "charts/$1/Chart.yaml"
  echo '{}' > "charts/$1/values.yaml"
}

commit() { git add -A && git commit -qm change; }

@test "no chart changed -> pass, nothing checked against the registry" {
  echo docs >> README.md; commit
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q "show chart" "$STUB_LOG" 2>/dev/null
}

@test "changed chart with bumped version and not yet published -> pass" {
  echo 'a: 1' > charts/shop/values.yaml
  sed -i 's/0.1.0/0.1.1/' charts/shop/Chart.yaml; commit
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "show chart oci://ghcr.io/nikola031ue/charts/shop --version 0.1.1" "$STUB_LOG"
}

@test "changed chart without version bump -> fail" {
  echo 'a: 1' > charts/shop/values.yaml; commit
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shop"* && "$output" == *"0.1.0"* ]]
}

@test "changed chart with lower version -> fail" {
  sed -i 's/version: 0.1.0/version: 0.0.9/' charts/shophub/Chart.yaml; commit
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shophub"* ]]
}

@test "prerelease of the same core version is lower than the release -> fail" {
  sed -i 's/version: 0.1.0/version: 0.1.0-rc.1/' charts/shop/Chart.yaml; commit
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "invalid SemVer -> fail" {
  sed -i 's/version: 0.1.0/version: v0.2/' charts/shop/Chart.yaml; commit
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SemVer"* ]]
}

@test "version already in registry -> fail" {
  sed -i 's/0.1.0/0.2.0/' charts/shop/Chart.yaml; commit
  HELM_SHOW_SHOP=published run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already published"* ]]
}

@test "existing chart, registry answers denied (private package) -> fail, never 'not published'" {
  sed -i 's/0.1.0/0.2.0/' charts/shop/Chart.yaml; commit
  HELM_SHOW_SHOP=denied run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Make packages public"* ]]
}

@test "registry network error -> fail" {
  sed -i 's/0.1.0/0.2.0/' charts/shop/Chart.yaml; commit
  HELM_SHOW_SHOP=error run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "brand-new chart, registry answers not found -> pass" {
  write_chart shophub-discord 0.1.0; commit
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "brand-new chart, registry answers denied (package does not exist yet) -> pass" {
  write_chart shophub-discord 0.1.0; commit
  HELM_SHOW_SHOPHUB_DISCORD=denied run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "brand-new chart already published (re-added name) -> fail" {
  write_chart shophub-discord 0.1.0; commit
  HELM_SHOW_SHOPHUB_DISCORD=published run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "reports every failing chart" {
  echo 'a: 1' > charts/shop/values.yaml
  echo 'b: 1' > charts/shophub/values.yaml; commit
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"charts/shop:"* && "$output" == *"charts/shophub:"* ]]
}
