#!/usr/bin/env bash
#
# Common one-line queries against `mcplense scan ... --format json` output.
# Usage:
#   ./scripts/scan-queries.sh tools-open-shape <url>
#   ./scripts/scan-queries.sh tls-expiring   <url> [days]
#   ./scripts/scan-queries.sh cors-risk      <url>
#   ./scripts/scan-queries.sh leaky-errors   <url>
#   ./scripts/scan-queries.sh urls-in-tools  <url>
#   ./scripts/scan-queries.sh missing-hints  <url> [hint]
#
# Requires: jq, mcplense.
set -euo pipefail

cmd=${1:-help}
url=${2:-}

if [[ "$cmd" == "help" || -z "$url" ]]; then
  cat <<'EOF'
Usage:
  scan-queries.sh <query> <url> [extra]

Queries:
  tools-open-shape    Tools whose schemas allow additionalProperties.
  tls-expiring        TLS cert expiring within N days (default 30).
  cors-risk           Wildcard CORS origin combined with credentials.
  leaky-errors        Stack-trace-like markers in error responses.
  urls-in-tools       URLs embedded in tool descriptions.
  missing-hints       Tools missing a specific annotation hint (default: destructiveHint).
  no-hsts             Servers that don't advertise Strict-Transport-Security.
  no-csp              Servers that don't advertise Content-Security-Policy.

All queries emit one-per-line plain text suitable for further grep / sort / uniq.
EOF
  exit 0
fi

run_scan() {
  mcplense scan "$url" --format json --quiet
}

case "$cmd" in
  tools-open-shape)
    run_scan | jq -r '
      .servers[] | .target as $t |
      .checks.tools.items[]
      | select(.schemaFingerprint.hasAdditionalProperties == true)
      | "\($t) tool=\(.name) accepts additionalProperties"
    '
    ;;
  tls-expiring)
    days=${3:-30}
    run_scan | jq -r --argjson days "$days" '
      .servers[] | select(.checks.transport.tls.daysUntilExpiry < $days)
      | "\(.target): cert expires in \(.checks.transport.tls.daysUntilExpiry) days"
    '
    ;;
  cors-risk)
    run_scan | jq -r '
      .servers[] | .target as $t |
      .checks.corsPreflight as $c |
      if ($c.accessControlAllowOrigin // "") == "*"
         and ($c.accessControlAllowCredentials // "") == "true"
      then "\($t) wildcard origin with credentials: high risk"
      else empty end
    '
    ;;
  leaky-errors)
    run_scan | jq -r '
      .servers[] | .target as $t |
      .checks."behavior.callNonExistentTool" as $b |
      if ($b.toolResultJson // "") | test("(at [A-Z]:\\\\|build=|internal-)") then
        "\($t) leaked internals: \($b.toolResultJson | .[0:120])..."
      else empty end
    '
    ;;
  urls-in-tools)
    run_scan | jq -r '
      .servers[] | .target as $t |
      .checks.metrics.fields[]
      | select(.path | startswith("tool:"))
      | select(.urlCount > 0)
      | "\($t) \(.path): \(.urls | join(", "))"
    '
    ;;
  missing-hints)
    hint=${3:-destructiveHint}
    run_scan | jq -r --arg hint "$hint" '
      .servers[] | .target as $t |
      .checks.tools.items[]
      | select(.missingAnnotations | index($hint))
      | "\($t) tool=\(.name) missing \($hint)"
    '
    ;;
  no-hsts)
    run_scan | jq -r '
      .servers[] |
      select((.checks.transport.responseHeaders.strictTransportSecurity // "") == "")
      | "\(.target): no HSTS"
    '
    ;;
  no-csp)
    run_scan | jq -r '
      .servers[] |
      select((.checks.transport.responseHeaders.contentSecurityPolicy // "") == "")
      | "\(.target): no Content-Security-Policy"
    '
    ;;
  *)
    echo "unknown query: $cmd" >&2
    exit 2
    ;;
esac
