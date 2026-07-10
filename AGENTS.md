# Kiali Helm Charts

Kiali is an open source service mesh observability tool for Istio. This repository contains the Helm charts for deploying Kiali — either via the **Kiali Operator** (which watches `Kiali` custom resources and manages the server lifecycle) or as a **standalone Kiali Server** — along with the tooling to build, test, and publish those charts.

Charts are published at [kiali.org/helm-charts](https://kiali.org/helm-charts).

## Quick Reference

| Task | Command |
|---|---|
| Install operator | `helm install kiali-operator kiali/kiali-operator -n kiali-operator --create-namespace` |
| Install server directly | `helm install kiali-server kiali/kiali-server -n istio-system` |
| Build charts locally | `make build-helm-charts` |
| Run template tests | `./tests/run-helm-chart-tests.sh` or `make run-helm-tests` |
| Run integration tests | `make run-server-itests` (requires live cluster) |
| Sync CRDs from upstream | `make sync-crds` |
| Validate CRD sync | `make validate-crd-sync` |

## Architecture at a Glance

```
kiali-helm-charts/
├── kiali-operator/       # Operator chart — installs the Ansible-based operator
│   ├── crds/             # Kiali CRD (installed via Helm crds/ mechanism)
│   └── templates/        # Deployment, RBAC, OSSMConsole CRD (OpenShift only)
├── kiali-server/         # Server chart — standalone Kiali installation
│   ├── templates/        # Deployment, ConfigMap, RBAC, Service, Ingress/Route, HPA, PDB, NetworkPolicy, OAuth
│   └── ci/               # CI value fixtures for integration tests
├── tests/
│   ├── kiali-server-tests/    # ~127 helm-template unit tests for server chart
│   └── kiali-operator-tests/  # ~26 helm-template unit tests for operator chart
├── hack/                 # Integration test setup/cleanup scripts
├── Makefile              # Build, test, CRD-sync targets
└── docs/                 # Published Helm chart index (kiali.org/helm-charts)
```

> For the full architecture index, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Documentation

- [Kiali Operator Chart](docs/agents/kiali-operator-chart.md) — CRDs, RBAC model, Ansible operator deployment, OpenShift support, and all `values.yaml` knobs for the operator chart.
- [Kiali Server Chart](docs/agents/kiali-server-chart.md) — All server chart templates (auth, ConfigMap generation, RBAC role split, Ingress/Route, HPA, PDB, NetworkPolicy, OAuth, security guardrails, credential secret pattern).
- [Testing and Build Pipeline](docs/agents/testing-and-build-pipeline.md) — Test file format, test runner mechanics, Makefile targets (`build-helm-charts`, `run-helm-tests`, `run-server-itests`), CRD synchronization workflow.

## Conventions

- **Two installation paths:** operator (`kiali-operator` chart) vs. standalone (`kiali-server` chart). The operator manages the full Kiali lifecycle via `Kiali` CRs; the server chart is a direct Helm-managed install with no operator.
- **CRD lifecycle:** The `kialis.kiali.io` CRD lives in `kiali-operator/crds/` (Helm `crds/` mechanism — created but not upgraded). The `ossmconsoles.kiali.io` CRD is in `templates/` so it can be OpenShift-conditional; this means `helm uninstall` also deletes it.
- **CRD sync:** CRDs are mastered in the `kiali-operator` upstream repo. Run `make sync-crds` to pull the latest, and `make validate-crd-sync` in CI to catch drift.
- **Value substitution:** `${HELM_IMAGE_REPO}` and `${HELM_IMAGE_TAG}` tokens in `values.yaml` are replaced at build time via `envsubst`. Source files always contain the token placeholders.
- **Tests are yaml-diff based:** Each test file specifies `helm_args`, a `yq` query, and an `expected_result`. The runner builds the chart, renders with `helm template --skip-tests`, runs the two-stage yq pipeline, and diffs the result.
- **Role split:** The `kiali-server` chart produces either a standard role (write-capable, only when auth=anonymous and view_only_mode=false) or a viewer role (read-only). Default installations on both k8s and OpenShift get the viewer role.
- **Ingress vs. Route:** On Kubernetes, Ingress is disabled by default and must be explicitly enabled. On OpenShift, `deployment.ingress.enabled` defaults to true and produces a Route (not a k8s Ingress).
