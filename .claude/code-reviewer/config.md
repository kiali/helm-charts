---
base_branch: master
languages:
  - helm
  - yaml
  - shell
key_paths:
  - kiali-server/templates/
  - kiali-server/templates/_helpers.tpl
  - tests/kiali-server-tests/
  - tests/kiali-operator-tests/
  - tests/run-helm-chart-tests.sh
---

# Kiali Helm Charts

Helm charts for deploying Kiali and the Kiali operator. The primary chart is `kiali-server`. Key review areas: `_helpers.tpl` template helpers (credential scanning, validation, auth helpers), `deployment.yaml` volume/volumeMount rendering, and the template-based test suite in `tests/kiali-server-tests/`. Tests use `helm template` + `yq` queries — no cluster required. The test format is declarative YAML files in `tests/kiali-server-tests/` and `tests/kiali-operator-tests/`.
