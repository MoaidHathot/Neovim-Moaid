# Classification recipes

`mcplense scan` is fact-only: it extracts data, downstream consumers classify.
These jq recipes turn the raw JSON report into actionable policy / risk
classifications. Mirror of [`docs/security-classification-recipes.md`](../../../docs/security-classification-recipes.md)
in the repo; bundled here so the skill is self-contained.

All recipes assume `mcplense scan <url> --format json` output piped to `jq`.

## Tool surface

### Tools accepting open-shape input

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks.tools.items[]
  | select(.schemaFingerprint.hasAdditionalProperties == true)
  | "\($t) tool=\(.name) accepts additionalProperties"
'
```

### Tools missing destructive-hint annotation

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks.tools.items[]
  | select(.missingAnnotations | index("destructiveHint"))
  | "\($t) tool=\(.name) missing destructiveHint"
'
```

### URLs in tool descriptions (image-fetch exfiltration surface)

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks.metrics.fields[]
  | select(.path | startswith("tool:"))
  | select(.urlCount > 0)
  | "\($t) \(.path): \(.urls | join(", "))"
'
```

## Auth / TLS posture

### TLS cert expiring within 30 days

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | select(.checks.transport.tls.daysUntilExpiry < 30)
  | "\(.target): cert expires in \(.checks.transport.tls.daysUntilExpiry) days"
'
```

### Wildcard CORS with credentials

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks.corsPreflight as $c |
  if ($c.accessControlAllowOrigin // "") == "*"
     and ($c.accessControlAllowCredentials // "") == "true"
  then "\($t) wildcard origin with credentials: high risk"
  else empty end
'
```

### Servers without HSTS

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | select((.checks.transport.responseHeaders.strictTransportSecurity // "") == "")
  | "\(.target): no HSTS"
'
```

## Information leakage

### Stack traces / internal markers in error responses

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks."behavior.callNonExistentTool" as $b |
  if ($b.toolResultJson // "") | test("(at [A-Z]:\\\\|build=|internal-)") then
    "\($t) leaked internals in error: \($b.toolResultJson | .[0:120])..."
  else empty end
'
```

### Server / X-Powered-By banners

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks.transport.responseHeaders.server // empty as $srv |
  .checks.transport.responseHeaders.xPoweredBy // empty as $pb |
  "\($t) Server=\($srv) X-Powered-By=\($pb)"
'
```

### Hidden / RTL / control chars in server instructions

```bash
mcplense scan https://server/mcp --format json | jq -r '
  .servers[] | .target as $t |
  .checks.metrics.fields[]
  | select(.path == "serverInstructions")
  | select(.controlCharCount > 0 or .nonAsciiCharCount > 50)
  | "\($t) instructions: ctrl=\(.controlCharCount) nonAscii=\(.nonAsciiCharCount)"
'
```

## Behavioural

### Servers reaching back via sampling / elicitation / roots

```bash
mcplense observe https://server/mcp --timeout 30 --format json | jq -r '
  .servers[] | .target as $t |
  .checks."behavior.serverInitiated".inboundCountsByMethod
  | to_entries[]
  | "\($t) \(.key): \(.value) call(s)"
'
```

## Diff / drift

### Anything changed since the baseline

```bash
mcplense scan https://server/mcp --diff ./baselines/server/yesterday.json --format json |
  jq '.servers[].checks.tools.changed[] | { id, before: .before.contentHash, after: .after.contentHash }'
```

### Fleet-wide drift (nightly)

```bash
# nightly
mkdir -p baselines
for url in $(cat targets.txt); do
  mcplense scan "$url" --baseline ./baselines/ --quiet --format json > /dev/null
done

# next day
for url in $(cat targets.txt); do
  host=$(echo "$url" | awk -F/ '{print $3}')
  latest=$(ls -1t ./baselines/"$host"/*.json | head -1)
  mcplense scan "$url" --diff "$latest" --format json |
    jq -r --arg url "$url" '.servers[] | select(.status != "unchanged") | "\($url): \(.status)"'
done
```

## Classification thresholds: a starter scoring rubric

| Signal | Action |
| --- | --- |
| `tools[*].schemaFingerprint.hasAdditionalProperties == true` | Warn. |
| `tools[*].missingAnnotations` contains `destructiveHint` | Warn. |
| `corsPreflight.accessControlAllowOrigin == "*"` AND `accessControlAllowCredentials == "true"` | High risk. |
| `transport.tls.daysUntilExpiry < 14` | High risk. |
| `transport.tls.daysUntilExpiry < 30` | Warn. |
| `behavior.callNonExistentTool.toolResultJson` matches stack-trace regex | Warn. |
| `metrics.fields[?(@.path=="serverInstructions")].controlCharCount > 0` | High risk (hidden prompt injection). |
| `behavior.serverInitiated.inboundCountsByMethod["sampling/createMessage"] > 0` | Audit context. |
| diff shows new tool with `destructiveHint != true` | High risk (rug-pull). |

Use these as starting points; the actual thresholds depend on your fleet's
trust model.
