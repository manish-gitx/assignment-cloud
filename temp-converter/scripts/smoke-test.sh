#!/usr/bin/env bash
# checks the app the same way a user would. usage: smoke-test.sh <base url> [expected version]
set -euo pipefail

BASE_URL=${1:-http://temp-converter.localhost:8080}
EXPECTED_VERSION=${2:-}
FAILED=0
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

check() {
  local name=$1 url=$2 want_status=$3 want_body=$4
  local status body
  status=$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$url") || true
  body=$(cat "$BODY_FILE")

  if [ "$status" = "$want_status" ] && echo "$body" | grep -q "$want_body"; then
    echo "PASS  $name -> $status $body"
  else
    echo "FAIL  $name -> got $status $body, wanted $want_status containing $want_body"
    FAILED=1
  fi
}

check "C to F"            "$BASE_URL/convert?value=100&from=C&to=F"   200 '"result":212.0'
check "F to C"            "$BASE_URL/convert?value=32&from=F&to=C"    200 '"result":0.0'
check "C to K"            "$BASE_URL/convert?value=0&from=C&to=K"     200 '"result":273.15'
check "not a number"      "$BASE_URL/convert?value=abc&from=C&to=F"   400 'error'
check "bad unit"          "$BASE_URL/convert?value=10&from=C&to=X"    400 'error'
check "below abs zero"    "$BASE_URL/convert?value=-5&from=K&to=C"    400 'error'
check "missing"           "$BASE_URL/convert"                         400 'error'

if [ -n "$EXPECTED_VERSION" ]; then
  check "version" "$BASE_URL/version" 200 "\"version\":\"$EXPECTED_VERSION\""
else
  check "version" "$BASE_URL/version" 200 'version'
fi

if [ "$FAILED" = "1" ]; then
  echo "smoke test failed"
  exit 1
fi
echo "smoke test passed"
