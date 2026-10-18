#!/usr/bin/env bash
# deploys the app to the local kind cluster.
#   scripts/deploy.sh          build from the working copy, tagged with the current commit
#   scripts/deploy.sh <sha>    deploy an image that CI already built and pushed to ghcr
set -euo pipefail

cd "$(dirname "$0")/.."

NAMESPACE=temp-converter
REGISTRY=ghcr.io/manish-gitx/temp-converter

if [ -n "${1:-}" ]; then
  VERSION=$1
  echo "deploying released image $REGISTRY:$VERSION"
  docker pull "$REGISTRY:$VERSION"
  docker tag "$REGISTRY:$VERSION" "temp-converter:$VERSION"
else
  if git rev-parse HEAD >/dev/null 2>&1; then
    VERSION=$(git rev-parse HEAD)
    # mark the version if there are uncommitted changes so it is not mixed up with a real commit
    if ! git diff --quiet HEAD -- app Dockerfile 2>/dev/null; then
      VERSION="${VERSION}-dirty"
    fi
  else
    VERSION="local-$(date +%s)"
  fi
  echo "building version $VERSION"
  docker build --build-arg APP_VERSION="$VERSION" -t "temp-converter:$VERSION" .
fi

kind load docker-image "temp-converter:$VERSION" --name temp-converter

helm upgrade --install temp-converter helm/temp-converter \
  -n "$NAMESPACE" \
  -f helm/temp-converter/values-local.yaml \
  --set image.tag="$VERSION" \
  --description "image $VERSION" \
  --wait --timeout 3m

kubectl -n "$NAMESPACE" rollout status deploy/temp-converter
helm -n "$NAMESPACE" history temp-converter --max 5
