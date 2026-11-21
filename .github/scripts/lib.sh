#!/usr/bin/env bash
# Shared helpers for helm-charts CI scripts. Source, do not execute.
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

# Strict SemVer 2.0 (https://semver.org) — no leading "v".
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'

semver_valid() { [[ "$1" =~ $SEMVER_RE ]]; }

# semver_gt A B -> 0 if A > B (core version + prerelease precedence; build metadata ignored).
semver_gt() {
  local a="${1%%+*}" b="${2%%+*}"
  local a_core="${a%%-*}" b_core="${b%%-*}"
  local a_pre="" b_pre=""
  [[ "$a" == *-* ]] && a_pre="${a#*-}"
  [[ "$b" == *-* ]] && b_pre="${b#*-}"
  local IFS=.
  local -a ac=($a_core) bc=($b_core)
  local i
  for i in 0 1 2; do
    if (( 10#${ac[i]} > 10#${bc[i]} )); then return 0; fi
    if (( 10#${ac[i]} < 10#${bc[i]} )); then return 1; fi
  done
  # Equal core: a release is greater than any prerelease.
  if [[ -z "$a_pre" && -n "$b_pre" ]]; then return 0; fi
  if [[ -n "$a_pre" && -z "$b_pre" ]]; then return 1; fi
  if [[ -z "$a_pre" && -z "$b_pre" ]]; then return 1; fi
  local -a ap=($a_pre) bp=($b_pre)
  local n=${#ap[@]}; (( ${#bp[@]} > n )) && n=${#bp[@]}
  for (( i = 0; i < n; i++ )); do
    local x="${ap[i]-}" y="${bp[i]-}"
    if [[ -z "$x" ]]; then return 1; fi
    if [[ -z "$y" ]]; then return 0; fi
    if [[ "$x" == "$y" ]]; then continue; fi
    if [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]]; then
      (( 10#$x > 10#$y )) && return 0 || return 1
    fi
    if [[ "$x" =~ ^[0-9]+$ ]]; then return 1; fi
    if [[ "$y" =~ ^[0-9]+$ ]]; then return 0; fi
    [[ "$x" > "$y" ]] && return 0 || return 1
  done
  return 1
}

# Read a top-level scalar from a Chart.yaml without yq (keeps scripts usable with only bash).
chart_field() {
  local file="$1" key="$2"
  sed -n -E "s/^${key}:[[:space:]]*[\"']?([^\"'#]*[^\"'#[:space:]])[\"']?[[:space:]]*(#.*)?$/\1/p" "$file" | head -n1
}

# registry_status CHART VERSION -> prints one of:
#   published  the version exists
#   notfound   the package exists but not this version
#   missing    GHCR answered denied/unauthorized/NAME_UNKNOWN: the package is private OR does
#              not exist yet (GHCR does not distinguish the two)
#   error      anything else (network, TLS, …) — message on stderr
registry_status() {
  local chart="$1" version="$2" out
  if out="$(helm show chart "$OCI_BASE/$chart" --version "$version" 2>&1 >/dev/null)"; then
    echo published; return
  fi
  shopt -s nocasematch
  if [[ "$out" =~ (denied|unauthorized|forbidden|401|403|name_unknown) ]]; then
    echo missing
  elif [[ "$out" =~ (not\ found|manifest\ unknown|manifest_unknown) ]]; then
    echo notfound
  else
    log "registry error for $chart:$version: $out"
    echo error
  fi
  shopt -u nocasematch
}

# OCI registry base for every chart (research.md R8).
OCI_BASE="${OCI_BASE:-oci://ghcr.io/nikola031ue/charts}"

# Chart folders allowed under charts/ (FR-002, FR-004). Extend in the same PR that adds a chart.
ALLOWED_CHARTS=(shop shophub shop-operator shophub-discord)
