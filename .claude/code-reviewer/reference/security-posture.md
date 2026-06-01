---
format_version: 1
---

# Security Posture — Kiali Helm Charts

## Secret Volume Mounting

Credential fields supporting `secret:<secretName>:<secretKey>` notation must result in:
- A `volume` entry in the Deployment with `secret.secretName` and `items[].key`
- A `volumeMount` at `/kiali-override-secrets/<volume-name>` with `readOnly: true`

The `readOnly: true` requirement is enforced by the deployment template. Never omit it.

## Credential Field Classification

- `client_secret`, `password`, `token`, `key_file` — sensitive, support `secret:` pattern
- `client_id`, `username` — public identifiers, do NOT support or require `secret:` pattern (RFC 6749 §2.2 for `client_id`)

## Template-Time Validation

Misconfigurations must be caught at `helm template` time via `{{- fail }}`, not at pod startup. This includes: missing required fields when a feature is enabled, incompatible combinations (e.g., `use_kiali_token` + `oauth2`, `use_grpc` + `oauth2`).

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-05-28 | Initial generation | /code-reviewer:setup |
