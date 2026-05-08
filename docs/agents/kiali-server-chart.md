---
title: Kiali Server Chart
scribe:
  scan: bf3d52eb75870fdca1cedc32630a0735669bd525
  freshness: 100
  human_input: 1
  completeness: 80
  watch_paths:
    - kiali-server/
  inferred_sections:
    - id: overview
      heading: Overview
    - id: resources-produced
      heading: Resources Produced
    - id: configmap-generation
      heading: ConfigMap Generation
    - id: rbac-model
      heading: RBAC Model
    - id: auth-strategy
      heading: Auth Strategy
    - id: namespace-access
      heading: Namespace Access Model
    - id: tls-and-identity
      heading: TLS and Identity
    - id: security-guardrails
      heading: Security Guardrails for User-Defined Containers
    - id: credential-secret-pattern
      heading: Credential Secret Pattern
    - id: external-facing-resources
      heading: External-Facing Resources
    - id: openshift-specifics
      heading: OpenShift Specifics
    - id: key-values
      heading: Key Values Reference
  stale_flags: []
  review_notes:
    - finding: "login_token.signing_key uses randAlphaNum — a new random key is generated on every helm upgrade unless pinned, which invalidates existing sessions"
      severity: minor
      tag: KSC-008
      confidence: 1.0
      date: "2026-05-08"
    - finding: "NetworkPolicy is Ingress-only (no Egress policy); operators adding egress-dependent sidecars should be aware"
      severity: minor
      tag: KSC-013
      confidence: 1.0
      date: "2026-05-08"
    - finding: "<fullname>-oauth-cabundle ConfigMap purpose not documented upstream; its intended use case is unknown"
      severity: unverifiable
      tag: KSC-NEW-01
      confidence: 0.7
      date: "2026-05-08"
---

# Kiali Server Chart

> Helm chart for deploying the Kiali Server directly, without an operator. Produces all Kubernetes resources needed to run Kiali and expose it to users.

## Overview

The `kiali-server` chart is the counterpart to the operator-based installation path. It creates all resources the Kiali Server needs: a Deployment, ConfigMap, ServiceAccount, RBAC (Role or ClusterRole depending on access mode), Service, and optionally Ingress, Route, HPA, PDB, NetworkPolicy, and OAuth resources.

The chart mirrors the shape of the Kiali CR spec — most values in `values.yaml` map 1:1 into the generated `config.yaml` ConfigMap that the server reads at startup. The Helm chart applies a few transformations (auth strategy detection, TLS source selection, signing key generation) before writing the ConfigMap.

## Resources Produced

Most non-RBAC resources are skipped when `deployment.remote_cluster_resources_only: true` (for installing only RBAC on remote clusters).

| Template | Kind | Condition |
|---|---|---|
| `deployment.yaml` | `Deployment` | Unless `remote_cluster_resources_only: true` |
| `configmap.yaml` | `ConfigMap` | Always |
| `serviceaccount.yaml` | `ServiceAccount` | Unless `sa` in `skipResources` |
| `role.yaml` | `ClusterRole` or `Role` | When NOT (`view_only_mode` OR auth ≠ `anonymous`); skippable via `skipResources` |
| `role-viewer.yaml` | `ClusterRole` or `Role` (viewer) | When `view_only_mode: true` OR auth ≠ `anonymous`; skippable |
| `rolebinding.yaml` | `ClusterRoleBinding` or `RoleBinding` | Binds viewer or standard role based on same condition; skippable |
| `clusterrole-openshift.yaml` | `ClusterRole` | OpenShift only, when auth is `openshift` OR TLS source is `auto` |
| `clusterrolebinding-openshift.yaml` | `ClusterRoleBinding` | OpenShift only, paired with above |
| `service.yaml` | `Service` | Unless `remote_cluster_resources_only: true` |
| `ingress.yaml` | `Ingress` | Non-OpenShift only; when `deployment.ingress.enabled: true` (default: **false** on k8s) |
| `route.yaml` | `Route` | OpenShift only; when `deployment.ingress.enabled: true` (default: **true** on OCP) |
| `oauth.yaml` | `OAuthClient` | OpenShift only; AND (`kiali_route_url` OR `auth.openshift.redirect_uris`) is set |
| `cabundle.yaml` | `ConfigMap` (`-cabundle-openshift`) | OpenShift only; auto-populated by OpenShift service CA injector |
| `hpa.yaml` | `HorizontalPodAutoscaler` | When `deployment.hpa.spec` is non-empty; also skipped by `remote_cluster_resources_only` |
| `pdb.yaml` | `PodDisruptionBudget` | When `deployment.pod_disruption_budget.spec` is non-empty; also skipped by flag |
| `networkpolicy.yaml` | `NetworkPolicy` | When `deployment.network_policy.enabled: true` (default); also skipped by flag |

## ConfigMap Generation

`templates/configmap.yaml` writes a `config.yaml` key that is the Kiali server's configuration file. The template takes `.Values` and strips only `kiali_route_url` before serializing to YAML. Chart-only keys such as `skipResources` and `isOpenShift` are **not** stripped and will appear verbatim in `config.yaml`. The Kiali server ignores unknown keys, but any future chart-only additions to `values.yaml` will also pass through unless explicitly omitted.

The template then applies these computed overrides:

| Field | How it's set |
|---|---|
| `auth.strategy` | Computed by `kiali-server.auth.strategy` helper (see Auth Strategy) |
| `auth.openshift.client_id_prefix` | Set to the Helm release fullname |
| `deployment.namespace` | Set to `.Release.Namespace` |
| `deployment.instance_name` | Set to the Helm release fullname |
| `deployment.tls_config.source` | Computed by `kiali-server.deployment.tls_config.source` helper |
| `identity.cert_file` / `private_key_file` | Set based on OpenShift detection |
| `login_token.signing_key` | Random 32-char alphanumeric if not set explicitly |
| `external_services.istio.root_namespace` | Defaults to `.Release.Namespace` |
| `server.web_root` | `/` on OpenShift, `/kiali` on Kubernetes (unless overridden) |
| `deployment.discovery_selectors` | Converted to exact namespace list when `cluster_wide_access: false` |

The pod annotation `checksum/config: <sha256 of configmap>` ensures a rolling restart whenever the ConfigMap changes.

## RBAC Model

Access mode is controlled by `deployment.cluster_wide_access` (default `true`). Either way, the chart creates one of two role variants:

**Standard role** (`role.yaml`) — created when `view_only_mode: false` AND `auth.strategy == "anonymous"`. Grants Kiali write access to Istio resources in addition to broad read access. Depending on `cluster_wide_access`, this is a `ClusterRole` (cluster-wide) or a `Role` in each accessible namespace.

**Viewer role** (`role-viewer.yaml`) — created when `view_only_mode: true` OR `auth.strategy != "anonymous"`. **Important:** these templates check the raw `.Values.auth.strategy` value directly, not the computed helper. Since `auth.strategy` defaults to `""` in `values.yaml`, and `"" != "anonymous"`, **the viewer role is active in all default installations regardless of platform** — not because the strategy defaults to `token` or `openshift`, but because an empty string is not `"anonymous"`. The standard role is only created when `auth.strategy` is explicitly set to `"anonymous"`. Grants read-only access; no write verbs on Istio resources.

`rolebinding.yaml` creates the binding (ClusterRoleBinding or RoleBinding based on `cluster_wide_access`) targeting whichever role variant applies.

**OpenShift extra ClusterRole** — `clusterrole-openshift.yaml` is created when on OpenShift AND (auth is `openshift` OR TLS source is `auto`):
- Auth `openshift`: adds get on the `OAuthClient` for this Kiali instance
- TLS source `auto`: adds get on OpenShift `apiservers` (to read `TLSSecurityProfile`)

An `clusterrolebinding-openshift.yaml` is created under the same conditions.

**Feature flag effect on RBAC** — adding `"logs-tab"` to `kiali_feature_flags.disabled_features` does more than hide the UI tab: both `role.yaml` and `role-viewer.yaml` conditionally omit `pods/log` from their rules when this flag is set. This is the only feature flag that directly modifies the RBAC grant. Operators who disable the logs tab for security reasons (restricting log access) should be aware this is the mechanism, and operators who disable it for other reasons should note the permission is also dropped.

**Skipping resources** — `skipResources: ["clusterrole", "clusterrolebinding", "sa"]` omits those resources for environments managing RBAC externally. Skipping `clusterrole` suppresses both the standard and viewer role (and both ClusterRole and Role variants). **Always skip `clusterrole` and `clusterrolebinding` together** — skipping only `clusterrole` leaves a dangling RoleBinding/ClusterRoleBinding that references a role that no longer exists. **Note:** the OpenShift-specific `clusterrole-openshift.yaml` has no `skipResources` check and is always created when its conditions are met (OpenShift + auth=openshift or TLS=auto), regardless of `skipResources`.

## Auth Strategy

The `kiali-server.auth.strategy` helper picks the strategy:

1. If `auth.strategy` is explicitly set, it is used.
2. If not set: defaults to `openshift` on OpenShift clusters, `token` on Kubernetes.

When the strategy resolves to `openshift` (either explicitly or via auto-detect), the template requires either `kiali_route_url` OR `auth.openshift.redirect_uris` to be set. If neither is provided, the template fails at render time with a clear error message. This is a deliberate guard — the OAuthClient redirect URI cannot be inferred automatically. Providing `auth.openshift.redirect_uris` is the alternative to `kiali_route_url` when you want to specify redirect URIs directly.

## Namespace Access Model

When `cluster_wide_access: false`, the chart must determine which namespaces Kiali can reach:

1. **`deployment.discovery_selectors`** — matches Istio's selector format. **Only the `.default` key is processed** by both the namespace lookup helper and the ConfigMap helper. Keys other than `.default` (e.g., `.production`, `.staging`) are silently ignored. When `helm install`/`upgrade` runs against a live cluster, the `lookup` function discovers namespaces matching the `.default` selectors.
2. **`helm template`** — `lookup` returns empty; only the release namespace is included.
3. The discovered namespace list is converted to a `matchExpressions` discovery selector (using `kubernetes.io/metadata.name In [list]`) and written into the ConfigMap, so the server knows exactly which namespaces it has RBAC for.
4. Roles and RoleBindings are created for each discovered namespace.

The Kiali deployment namespace is always added to the list regardless of selectors.

## TLS and Identity

`deployment.tls_config.source` controls how the Kiali server picks up TLS settings:
- `auto` (default on OpenShift): reads `TLSSecurityProfile` from the OpenShift APIServer cluster operator
- `config` (default on Kubernetes): uses values in `deployment.tls_config` directly (`cipher_suites`, `min_version`, `max_version`)
- Explicitly overridable via `deployment.tls_config.source`

`identity.cert_file` / `identity.private_key_file` default to `/kiali-cert/tls.crt` and `/kiali-cert/tls.key` on OpenShift, empty on Kubernetes. When set, the deployment mounts a TLS secret at `/kiali-cert/` — the secret name differs by platform:
- **OpenShift:** `<fullname>-cert-secret` — created automatically by the OpenShift service CA controller. The `service.yaml` template adds the annotation `service.beta.openshift.io/serving-cert-secret-name: <fullname>-cert-secret`, which triggers the controller to provision a signed TLS certificate into that secret. No manual certificate management is needed on a standard OpenShift cluster.
- **Kubernetes:** `istio.<fullname>-service-account` (Istio-provisioned service account token) — must exist if TLS identity is needed on plain Kubernetes.

The Ingress backend-protocol annotation is also switched to HTTPS when identity files are set.

## Security Guardrails for User-Defined Containers

`deployment.additional_pod_containers_yaml` and `deployment.additional_pod_init_containers_yaml` let users inject sidecar and init containers. The `_helpers.tpl` functions `kiali-server.secureContainers` and `kiali-server.secureInitContainers` enforce:

1. **Mandatory security context** — `allowPrivilegeEscalation: false`, `privileged: false`, `readOnlyRootFilesystem: true`, `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]` — merged over any user-provided context. Users cannot weaken these.

2. **Read-only secret volume enforcement** — any volume mount targeting a secret-backed volume (Kiali's own secrets, custom secrets, remote cluster secrets, credential secrets) is forced to `readOnly: true`. If the user explicitly sets `readOnly: false` on a secret volume, the template fails with a clear error message.

The `kiali-server.secret-volume-names` helper centralizes the list of protected volume names, including: `<fullname>-secret`, `<fullname>-cert`, `kiali-multi-cluster-secret`, `custom_secrets` non-CSI volumes, auto-detected remote cluster secret volumes, and credential secret volumes.

## Credential Secret Pattern

External service credentials (Prometheus, Grafana, Tracing, Perses, custom dashboards, ChatAI providers) and the login token signing key support a `secret:<secretName>:<secretKey>` reference pattern in their value fields.

When the chart detects this pattern in `external_services.*.auth.{username,password,token,cert_file,key_file}` or `login_token.signing_key` or `chat_ai.providers[*].key` or `chat_ai.providers[*].models[*].key`, it:
1. Creates a volume entry pointing to the named Secret
2. Mounts it into the Kiali container at a predictable path (e.g., `/kiali-override-secrets/prometheus-password/value.txt`)
3. Updates the ConfigMap to reference the mounted file path instead of the raw value

This allows credentials to live in Kubernetes Secrets without being embedded in the Helm values. The `kiali-server.credential-secrets` helper in `_helpers.tpl` aggregates all detected secrets into a JSON map used by the deployment and service templates. Volume names follow the pattern `<service>-<field>` (e.g., `prometheus-password`) for external services, `chat-ai-provider-<name>` for provider-level keys, and `chat-ai-model-<provider>-<model>` for model-level keys.

## External-Facing Resources

**Service** — created unless `deployment.remote_cluster_resources_only: true`. Type defaults to empty (ClusterIP). Configurable via `deployment.service_type` and `deployment.additional_service_yaml`.

**Ingress** — non-OpenShift only; **disabled by default on Kubernetes** (`deployment.ingress.enabled` defaults to `false`). Enable explicitly with `--set deployment.ingress.enabled=true`. Class defaults to `nginx`. The ingress path uses the computed `web_root`. Full spec override via `deployment.ingress.override_yaml`.

**Route** — OpenShift only; enabled by default on OpenShift (`deployment.ingress.enabled` defaults to `true` on OCP). The default Route spec uses `tls.termination: reencrypt` with `insecureEdgeTerminationPolicy: Redirect` — the OpenShift router decrypts and re-encrypts traffic, so Kiali must serve TLS (which it does by default via the auto-provisioned cert secret). To use a different termination mode (e.g., `edge`), override via `deployment.ingress.override_yaml.spec`. The `kiali_route_url` or `auth.openshift.redirect_uris` must be set for the OAuthClient to be created alongside it.

**NetworkPolicy** — enabled by default (`deployment.network_policy.enabled: true`). Allows **inbound** traffic only (no Egress policy). Skipped when `deployment.remote_cluster_resources_only: true`.

**HPA** — created when `deployment.hpa.spec` is non-empty. When HPA is active, `deployment.replicas` is ignored (the template conditionally omits `spec.replicas` to avoid conflicting with the HPA).

**PDB** — created when `deployment.pod_disruption_budget.spec` is non-empty.

**Probes** — all three probes are configurable via `deployment.probes.*`. Defaults: readiness and liveness both have `initial_delay_seconds: 5`, `period_seconds: 30`; startup probe has `initial_delay_seconds: 30`, `period_seconds: 10`, `failure_threshold: 6`. The startup probe is relevant on slow clusters — the default allows up to 90 s for Kiali to become healthy before the pod is marked as failed.

**Default pod annotation** — `values.yaml` includes `pod_annotations: {proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'}` by default. This causes the Kiali pod to wait for the Istio sidecar proxy to be ready before Kiali starts. On clusters without sidecar injection enabled, this annotation can cause the pod to hang indefinitely. Override with `deployment.pod_annotations: {}` if running outside a mesh.

## OpenShift Specifics

OpenShift detection is `kiali-server.isOpenShift` — checks `operator.openshift.io/v1` in the API versions, or the `isOpenShift` value when overridden for local debugging.

When on OpenShift:
- Auth strategy defaults to `openshift` (OAuth integration)
- TLS source defaults to `auto`
- `identity.cert_file` and `private_key_file` default to `/kiali-cert/tls.crt` and `/kiali-cert/tls.key`
- `web_root` defaults to `/`
- `deployment.ingress.enabled` defaults to `true`; a Route is created (not a k8s Ingress)
- `cabundle.yaml` creates a ConfigMap named `<fullname>-cabundle-openshift` that OpenShift automatically populates with `service-ca.crt`. The deployment projects three ConfigMaps into the cabundle volume: `<fullname>-cabundle-openshift` (required on OCP), `<fullname>-cabundle` (optional, for user-provided custom CAs — available on both platforms), and `<fullname>-oauth-cabundle` (optional; purpose not yet documented upstream)
- An OAuthClient is created when `kiali_route_url` OR `auth.openshift.redirect_uris` is set
- A separate `clusterrole-openshift.yaml` grants OAuth and TLS discovery permissions
- `isOpenShift` can be forced via `values.yaml` for local chart debugging without a live OpenShift cluster

## Key Values Reference

| Value | Default | Purpose |
|---|---|---|
| `auth.strategy` | `""` (auto-detected) | Auth strategy: `anonymous`, `token`, `openshift`, `openid` |
| `kiali_route_url` | `""` | Required for `openshift` auth; the external Route URL |
| `deployment.cluster_wide_access` | `true` | ClusterRole vs Role/RoleBinding mode |
| `deployment.discovery_selectors` | `{}` | Namespace selectors when `cluster_wide_access: false` |
| `deployment.image_name` | `quay.io/kiali/kiali` | Kiali server image |
| `deployment.image_version` | `${HELM_IMAGE_TAG}` | Kiali server version |
| `deployment.replicas` | `1` | Replica count (ignored when HPA is active) |
| `deployment.instance_name` | `kiali` | Name prefix for all resources |
| `deployment.view_only_mode` | `false` | Disables write operations in Kiali UI |
| `deployment.network_policy.enabled` | `true` | Emit a NetworkPolicy |
| `deployment.hpa.spec` | `{}` | HPA spec; non-empty triggers HPA creation |
| `deployment.pod_disruption_budget.spec` | `{}` | PDB spec; non-empty triggers PDB creation |
| `deployment.tls_config.source` | `""` (auto) | TLS config source: `auto` or `config` |
| `deployment.ingress.enabled` | `false` (k8s) | Enable Ingress on non-OpenShift |
| `deployment.ingress.class_name` | `nginx` | Ingress class |
| `deployment.remote_cluster_resources_only` | `false` | Skip Deployment/Service (remote cluster install) |
| `deployment.custom_secrets` | `[]` | Additional secrets to mount |
| `deployment.additional_pod_containers_yaml` | `[]` | Sidecar containers (security-guardrailed) |
| `server.port` | `20001` | Kiali HTTP port |
| `server.observability.metrics.enabled` | `true` | Expose Prometheus metrics on `:9090` |
| `server.web_root` | `/kiali` (k8s) / `/` (OCP) | URL path prefix |
| `external_services.prometheus.enabled` | `true` | Include Prometheus integration |
| `external_services.istio.root_namespace` | `""` (→ release namespace) | Istio control plane namespace |
| `clustering.autodetect_secrets.enabled` | `true` | Auto-mount remote cluster secrets |
| `login_token.signing_key` | `""` (random) | JWT signing key; random generated if empty |
| `kiali_feature_flags.disabled_features` | `[]` | Features to disable in the UI; `"logs-tab"` also removes `pods/log` from RBAC |
| `skipResources` | `[]` | RBAC resources to skip creating |
| `chat_ai.enabled` | `false` | Enable ChatAI integration |
