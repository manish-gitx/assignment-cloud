#!/usr/bin/env bash
# creates the local kind cluster and installs ingress, metrics-server, prometheus/grafana and jaeger
set -euo pipefail

cd "$(dirname "$0")/.."

INGRESS_VERSION=controller-v1.15.1
PROM_STACK_VERSION=92.10.1
METRICS_SERVER_VERSION=3.14.0

if kind get clusters | grep -q '^temp-converter$'; then
  echo "cluster temp-converter already exists"
else
  kind create cluster --config k8s/kind-config.yaml
fi

kubectl config use-context kind-temp-converter

echo "--- ingress-nginx"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/kind/deploy.yaml"
# rate limited requests get 429 instead of the default 503, so they dont look like an outage
kubectl -n ingress-nginx patch configmap ingress-nginx-controller --type merge \
  -p '{"data":{"limit-req-status-code":"429","limit-conn-status-code":"429"}}'

echo "--- metrics-server (needed for hpa)"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version "$METRICS_SERVER_VERSION" -n kube-system \
  --set 'args={--kubelet-insecure-tls}'

echo "--- monitoring"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 18)"
fi
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$PROM_STACK_VERSION" -n monitoring \
  -f monitoring/kube-prometheus-values.yaml --wait --timeout 10m

echo "--- jaeger"
kubectl apply -f monitoring/jaeger.yaml

echo "--- app namespace"
kubectl apply -f k8s/namespace.yaml

kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s
kubectl -n observability rollout status deploy/jaeger --timeout=180s

echo
echo "cluster ready. next: make deploy"
