#!/usr/bin/env bash
#
# Run a nightly fleet scan + drift report.
#
# Usage:
#   ./scripts/fleet-drift.sh baseline ./targets.txt ./baselines/
#   ./scripts/fleet-drift.sh diff     ./targets.txt ./baselines/
#
# targets.txt is one URL per line. Empty lines and '#' comments are ignored.
#
# 'baseline' writes one report per target under <baselines>/<host>/<UTC-ts>.json.
# 'diff' compares each target's CURRENT scan to its most recent baseline and
# prints any servers whose status is not "unchanged".
#
# Requires: jq, mcplense.
set -euo pipefail

mode=${1:-help}
targets_file=${2:-}
baselines_dir=${3:-./baselines/}

if [[ "$mode" == "help" || -z "$targets_file" ]]; then
  cat <<'EOF'
Usage:
  fleet-drift.sh baseline <targets-file> [baselines-dir]
  fleet-drift.sh diff     <targets-file> [baselines-dir]

Modes:
  baseline   Write a fresh scan per target under <baselines-dir>/<host>/<UTC-ts>.json.
  diff       Re-scan each target and emit a one-line drift report.
EOF
  exit 0
fi

if [[ ! -f "$targets_file" ]]; then
  echo "targets file not found: $targets_file" >&2
  exit 2
fi

mkdir -p "$baselines_dir"

read_targets() {
  grep -vE '^\s*($|#)' "$targets_file"
}

case "$mode" in
  baseline)
    while IFS= read -r url; do
      echo "scan baseline: $url" >&2
      mcplense scan "$url" --baseline "$baselines_dir" --quiet --format json > /dev/null
    done < <(read_targets)
    ;;
  diff)
    while IFS= read -r url; do
      host=$(echo "$url" | awk -F/ '{print $3}')
      latest=$(ls -1t "$baselines_dir/$host"/*.json 2>/dev/null | head -1 || true)
      if [[ -z "$latest" ]]; then
        echo "$url: no prior baseline; skipped" >&2
        continue
      fi
      mcplense scan "$url" --diff "$latest" --format json --quiet |
        jq -r --arg url "$url" '
          .servers[]
          | select(.status != null)
          | select(.status != "unchanged")
          | "\($url): \(.status)"
        '
    done < <(read_targets)
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
