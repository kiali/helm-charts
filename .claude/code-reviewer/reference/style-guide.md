---
format_version: 1
---

# Style Guide — Kiali Helm Charts

## Helm Template Conventions

### Helper naming
All helpers in `_helpers.tpl` use the prefix `kiali-server.` (e.g., `kiali-server.fullname`, `kiali-server.process-auth-secrets`). New helpers must follow this prefix convention.

### Nil-safe nested access
Use nested `{{- if }}` blocks rather than `and` for multi-level value access to avoid nil dereference. Helm's `and` evaluates all arguments before checking truthiness.

```
{{- if .auth.oauth2 }}
{{- if .auth.oauth2.client_secret }}
{{- end }}
{{- end }}
```

Not:
```
{{- if and .auth.oauth2 .auth.oauth2.client_secret }}
```

### `fail` for validation
Template-time validation uses `{{- fail "message" }}` inside helpers. Validation should be placed inside the helper that processes the relevant config (e.g., inside `process-auth-secrets` for auth validation).

### Secret extraction pattern
Credential fields using `secret:<name>:<key>` notation are extracted via the `kiali-server.extract-secret` helper. Always pass `volumeName` and `fileName` as dict keys. The volume name convention is `<service>-<field>` (e.g., `prometheus-token`, `grafana-oauth2-client-secret`).

## Test File Conventions

### File naming
Test files use kebab-case: `credential-secret-prometheus-oauth2.yaml`, `auth-oauth2-missing-client-secret.yaml`.

### Required fields
Every test file must have: `name`, `description`, `helm_args`, `yq_query`, `expected_result`.

### Failure tests
Tests that expect `helm template` to fail must set `should_fail: true` and `expected_error_pattern` with the expected error substring.

### `helm_args` format
Each `--set` and its value must be separate list entries:
```yaml
helm_args:
  - "--set"
  - "key=value"
```

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-05-28 | Initial generation | /code-reviewer:setup |
