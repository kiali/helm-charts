# Documentation Status

Generated: 2026-05-26 (focus-enrich — kiali-server-chart: documented oauth-cabundle purpose and full /kiali-cabundle projected volume structure)

## Topic Scores

| Topic | Fresh | Human | Complete | Claims | File |
|---|---|---|---|---|---|
| [Kiali Operator Chart](kiali-operator-chart.md) | 100 | 1 | 78 | 15 | kiali-operator/ |
| [Kiali Server Chart](kiali-server-chart.md) | 100 | 1 | 82 | 19 | kiali-server/ |
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
- (minor) `<fullname>-oauth-cabundle` purpose clarified 2026-05-26: provides `oauth-server-ca.crt` for validating OpenShift OAuth server TLS cert
- (minor) `deployment.strategy` was undocumented in Key Values Reference — added 2026-05-19
- (minor) `templates/tests/` Helm-native tests noted in Resources Produced; cross-reference to testing topic added

### Testing and Build Pipeline
- (minor) Test counts (~127, ~26) will drift as tests are added
