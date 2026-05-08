# Documentation Status

Generated: 2026-05-08 (post human review)

## Topic Scores

| Topic | Fresh | Human | Complete | File |
|---|---|---|---|---|
| [Kiali Operator Chart](kiali-operator-chart.md) | 100 | 1 | 82 | kiali-operator/ |
| [Kiali Server Chart](kiali-server-chart.md) | 100 | 1 | 85 | kiali-server/ |
| [Testing and Build Pipeline](testing-and-build-pipeline.md) | 100 | 1 | 80 | tests/, kiali-server/ci/, Makefile, hack/ |

## Stale Flags

None.

## Review Notes

### Kiali Operator Chart
- (minor) Startup probe parameters documented inline; flagged for awareness on slow-cluster deployments

### Kiali Server Chart
- (minor) `login_token.signing_key` regenerated on every `helm upgrade` unless pinned — invalidates existing user sessions
- (minor) NetworkPolicy is Ingress-only (no Egress policy)
- (unverifiable) `<fullname>-oauth-cabundle` ConfigMap is projected into the cabundle volume but its purpose is not documented upstream

### Testing and Build Pipeline
- (minor) Test counts (~127, ~26) will drift as tests are added
