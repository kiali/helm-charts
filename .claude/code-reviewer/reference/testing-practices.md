---
format_version: 1
---

# Testing Practices — Kiali Helm Charts

## Framework

Template-based tests use `helm template` + `yq` queries. No cluster required. Test runner: `tests/run-helm-chart-tests.sh`. Run via `make run-helm-tests TEST_SUITE=server`.

## Test File Structure

```yaml
name: "unique_test_identifier"
description: "Human-readable description of what is being tested"
helm_args:
  - "--set"
  - "key=value"
yq_query: "select(.kind == \"Deployment\") | .spec.template.spec.volumes"
expected_result: |
  - name: my-volume
    secret:
      secretName: my-secret
should_fail: false
expected_error_pattern: ""   # only needed when should_fail: true
```

## Coverage Requirements

### Credential secret mounting tests
For any new credential field that supports `secret:<name>:<key>` notation, add a test verifying:
- Volume is created with correct `secretName` and `items[].key`
- VolumeMount is created at `/kiali-override-secrets/<volume-name>` with `readOnly: true`
- A literal value (no `secret:` prefix) does NOT create a volume

### Validation failure tests
For any `{{- fail }}` validation added to `_helpers.tpl`, add a corresponding `should_fail: true` test with `expected_error_pattern` matching the fail message.

### Backward compatibility
When adding new auth types or credential fields, add tests confirming existing auth types (bearer, basic) are unaffected.

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-05-28 | Initial generation | /code-reviewer:setup |
