# Documentation Status

Generated: 2026-05-14 (drift update — ChatAI provider types + VERSION bump)

## Topic Scores

| Topic | Fresh | Human | Complete | Claims | File |
|---|---|---|---|---|---|
| [Kiali Operator Chart](kiali-operator-chart.md) | 100 | 1 | 78 | 15 | kiali-operator/ |
| [Kiali Server Chart](kiali-server-chart.md) | 100 | 1 | 80 | 15 | kiali-server/ |
| [Testing and Build Pipeline](testing-and-build-pipeline.md) | 100 | 1 | 75 | 12 | tests/, kiali-server/ci/, Makefile, hack/ |

## Stale Flags

None.

## Review Notes

### Kiali Operator Chart
- (minor) Startup probe parameters documented inline; flagged for awareness on slow-cluster deployments
- (minor) `debug.enabled` defaults to `true` — full Ansible logs dumped after each reconciliation by default, with log-volume implications
- (minor) `ALLOW_AD_HOC_OSSMCONSOLE_IMAGE` env var is OpenShift-only (conditionally rendered) — not called out explicitly in the env var list
- (minor) Secrets RBAC model collapses three distinct rules — the exact verb scoping per secret name is in the template but not in the doc

### Kiali Server Chart
- (minor) `login_token.signing_key` regenerated on every `helm upgrade` unless pinned — invalidates existing user sessions
- (minor) NetworkPolicy is Ingress-only (no Egress policy)
- (unverifiable) `<fullname>-oauth-cabundle` ConfigMap is projected into the cabundle volume but its purpose is not documented upstream

### Testing and Build Pipeline
- (minor) Test counts (~127, ~26) will drift as tests are added
