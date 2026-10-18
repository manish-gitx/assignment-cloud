# Decisions

## App
- Flask, one endpoint `/convert?value=N&from=C&to=F` for Celsius, Fahrenheit and Kelvin.
- Bad input is a 400: missing value, unknown unit, not a number, nan/inf, outside ±1e9, below absolute zero.
- Converts through Celsius, so 3 units need 4 small functions instead of 6 pairwise formulas.
- `/healthz` and `/readyz` for probes, `/version` for the running commit, `/metrics` for prometheus.

## Kubernetes
- Deployment, not StatefulSet: the app keeps no state, so no PVC.
- 2 replicas + PDB minAvailable 1, so one pod can go down and the app still answers.
- HPA 2-5 pods on CPU 70%, since every request costs about the same CPU.
- gunicorn 1 worker 4 threads: keeps prometheus counters in one process, scale with pods instead.
- Resources: requests 50m/64Mi, limits 250m/128Mi (measured ~55Mi per pod under load).
- Readiness every 5s, liveness slower (10s x 3) so a short hiccup does not restart the pod.
- preStop sleep 5 so the service stops sending traffic before the pod shuts down.
- Ingress only exposes `/convert` and `/version`, rate limited to 20 rps (429 when over).

## Config
- One Helm chart, `values.yaml` + `values-local.yaml` + `values-ci.yaml`, no copied manifests.
- ConfigMap checksum annotation rolls pods when config changes.
- `image.tag` is required, so `latest` can never be deployed by accident.

## CI/CD
- GitHub Actions: lint, tests, bandit, pip-audit, gitleaks, helm lint, docker build, trivy.
- Image built once, tagged with the commit sha, tested in a throwaway kind cluster.
- Publish to ghcr needs manual approval (`production` environment).
- CD stops at publish because GitHub cannot reach my laptop cluster; I deploy with `make deploy-release TAG=<sha>`.

## Release control
- Rolling update, maxSurge 1, maxUnavailable 0: a broken version never replaces working pods.
- Rollback with `helm rollback`, every revision description has the image sha.
- Traceability: commit sha -> image tag -> `/version`, `X-App-Version` header, logs, metrics, pod label.
- Feature flag `config.showFormula` (adds the formula to the response), changed by values without a new image.

## Observability
- Metrics: requests by status, latency histogram, conversions by unit pair, build info.
- Healthy = 99% of requests not 5xx and p95 under 200ms. 4xx are user errors and not counted.
- Alerts: app down, error rate > 1%, p95 > 200ms, pod restarting.
- JSON logs with request id, trace id and version. Traces go to Jaeger over OTLP.

## Security
- Non root (uid 10001), read only filesystem, all capabilities dropped, seccomp RuntimeDefault.
- Namespace enforces Pod Security `restricted`.
- No service account token, the app never calls the Kubernetes API.
- NetworkPolicy: only ingress-nginx and monitoring can reach the app.
- No secrets in the repo; Grafana password is generated at setup and stored as a k8s Secret.
- CI uses read only permissions, only publish gets `packages: write` via `GITHUB_TOKEN`.
