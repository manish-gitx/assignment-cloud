#!/usr/bin/env bash
# collects proof that the deployed version works, into docs/evidence/<version>.txt
# run after make deploy (or make deploy-release) on the local cluster
set -uo pipefail

cd "$(dirname "$0")/.."

NS=temp-converter
URL=http://temp-converter.localhost:8080

VERSION=$(curl -s $URL/version | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
mkdir -p docs/evidence
OUT=docs/evidence/$VERSION.txt

section() {
  echo
  echo "=================================================================="
  echo "== $1"
  echo "=================================================================="
}

promq() {
  curl -s http://localhost:9090/api/v1/query --data-urlencode "query=$1" |
    python3 -c "import json,sys; [print(' ', r['metric'], r['value'][1]) for r in json.load(sys.stdin)['data']['result']]"
}

kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090 >/dev/null 2>&1 &
PF_PROM=$!
kubectl -n observability port-forward svc/jaeger 16686 >/dev/null 2>&1 &
PF_JAEGER=$!
trap 'kill $PF_PROM $PF_JAEGER 2>/dev/null' EXIT

{
  echo "evidence collected $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git commit:       $(git rev-parse HEAD 2>/dev/null || echo 'no git')"
  echo "running version:  $VERSION"

  section "source -> image: helm release history (description has the image tag)"
  helm -n $NS history temp-converter --max 5

  section "runtime: pods, the image they run and the version label"
  kubectl -n $NS get pods -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,IMAGE:.spec.containers[0].image,VERSION:.metadata.labels.app\.kubernetes\.io/version'
  echo
  kubectl -n $NS get deploy,svc,ingress,hpa,pdb,networkpolicy

  section "user journey through the ingress"
  scripts/smoke-test.sh $URL "$VERSION"
  echo
  echo "response headers:"
  curl -s -D - -o /dev/null "$URL/convert?value=21&from=C&to=F" | grep -iE '^(HTTP|x-app-version|x-request-id)'

  section "not exposed: /metrics through the ingress should be 404"
  curl -s -o /dev/null -w '  status %{http_code}\n' $URL/metrics

  section "security: pod security admission rejects a pod without the restricted settings"
  kubectl -n $NS run psa-test --image=busybox:1.36 --restart=Never --dry-run=server -- true 2>&1 | cut -c1-200

  section "security: network policy"
  echo "  from default namespace (should be blocked):"
  kubectl run np-test --rm -i --quiet --restart=Never --image=busybox:1.36 -n default -- \
    sh -c "wget -qO- -T 4 http://temp-converter.$NS.svc/version && echo || echo '  blocked'"
  echo "  from monitoring namespace (should work):"
  kubectl run np-test --rm -i --quiet --restart=Never --image=busybox:1.36 -n monitoring -- \
    sh -c "wget -qO- -T 4 http://temp-converter.$NS.svc/version && echo || echo '  blocked'"

  section "security: container runs as"
  kubectl -n $NS exec deploy/temp-converter -- id
  kubectl -n $NS exec deploy/temp-converter -- sh -c 'touch /srv/x 2>&1 || true'

  sleep 20

  section "metrics: prometheus targets"
  promq 'up{service="temp-converter"}'

  section "metrics: requests by status"
  promq 'sum by (status) (tempconv_requests_total)'

  section "metrics: SLO, success ratio and p95 latency over 5m"
  promq '1 - tempconv:error_ratio:rate5m'
  promq 'tempconv:latency_p95:rate5m'

  section "metrics: running version"
  promq 'tempconv_build_info'

  section "alerts: current state of temp-converter alerts"
  curl -s http://localhost:9090/api/v1/rules | python3 -c "
import json, sys
for g in json.load(sys.stdin)['data']['groups']:
    if g['name'] != 'temp-converter':
        continue
    for r in g['rules']:
        if r['type'] == 'alerting':
            print(' ', r['name'], r['state'], r['health'])
"

  section "logs: last 3 request lines"
  kubectl -n $NS logs deploy/temp-converter --tail=3

  section "traces: latest temp-converter traces in jaeger"
  START=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)
  END=$(date -u -v+1M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 minute' +%Y-%m-%dT%H:%M:%SZ)
  curl -s "http://localhost:16686/api/v3/traces?query.service_name=temp-converter&query.start_time_min=$START&query.start_time_max=$END&query.num_traces=3" |
    python3 -c "
import json, sys
for rs in json.load(sys.stdin)['result']['resourceSpans']:
    for ss in rs['scopeSpans']:
        for s in ss['spans']:
            print(' ', s['traceId'], s['name'])
"
} 2>&1 | tee "$OUT"

echo
echo "saved to $OUT"
