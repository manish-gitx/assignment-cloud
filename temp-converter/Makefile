.PHONY: install test lint scan image cluster deploy deploy-release smoke evidence urls down

install:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements-dev.txt

test:
	.venv/bin/python -m pytest -v --cov=app

lint:
	.venv/bin/flake8 app tests
	helm lint helm/temp-converter --set image.tag=lint

scan:
	.venv/bin/bandit -r app
	.venv/bin/pip-audit -r app/requirements.txt
	docker build -t temp-converter:scan .
	trivy image --severity HIGH,CRITICAL --ignore-unfixed temp-converter:scan

image:
	docker build -t temp-converter:dev .

cluster:
	scripts/cluster-up.sh

deploy:
	scripts/deploy.sh

deploy-release:
	scripts/deploy.sh $(TAG)

smoke:
	scripts/smoke-test.sh http://temp-converter.localhost:8080

urls:
	@echo "app:        http://temp-converter.localhost:8080/convert?value=100&from=C&to=F"
	@echo "grafana:    kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80  -> http://localhost:3000"
	@echo "            password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d"
	@echo "prometheus: kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090  -> http://localhost:9090"
	@echo "jaeger:     kubectl -n observability port-forward svc/jaeger 16686  -> http://localhost:16686"

down:
	scripts/cluster-down.sh

evidence:
	scripts/collect-evidence.sh
