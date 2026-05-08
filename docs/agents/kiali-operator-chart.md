---
title: Kiali Operator Chart
scribe:
  scan: bf3d52eb75870fdca1cedc32630a0735669bd525
  freshness: 100
  human_input: 1
  completeness: 78
  watch_paths:
    - kiali-operator/
  inferred_sections:
    - id: overview
      heading: Overview
    - id: resources-produced
      heading: Resources Produced
    - id: rbac-model
      heading: RBAC Model
    - id: operator-deployment
      heading: Operator Deployment
    - id: crds
      heading: CRDs
    - id: key-values
      heading: Key Values Reference
    - id: openshift-support
      heading: OpenShift Support
    - id: managed-cr
      heading: Managed Kiali CR
  stale_flags: []
  review_notes:
    - finding: "Startup probe parameters (initialDelaySeconds: 30, periodSeconds: 10, failureThreshold: 6) not documented — relevant for slow cluster deployments"
      severity: minor
      tag: TAG-011
      confidence: 1.0
      date: "2026-05-08"
    - finding: "debug.enabled defaults to true — full Ansible logs are dumped after each reconciliation by default, with log-volume implications"
      severity: minor
      tag: TAG-015
      confidence: 1.0
      date: "2026-05-08"
    - finding: "ALLOW_AD_HOC_OSSMCONSOLE_IMAGE env var is OpenShift-only (conditionally rendered) — not called out explicitly in the env var list"
      severity: minor
      tag: TAG-013
      confidence: 1.0
      date: "2026-05-08"
    - finding: "Secrets RBAC model collapses three distinct rules — the exact verb scoping per secret name is in the template but not in the doc"
      severity: minor
      tag: TAG-009
      confidence: 0.9
      date: "2026-05-08"
---

# Kiali Operator Chart

> Helm chart for installing the Kiali Operator — an Ansible-based Kubernetes operator that watches for `Kiali` CRs and reconciles them into running Kiali Server instances.

## Overview

The `kiali-operator` chart installs the Kiali Operator into a dedicated namespace (typically `kiali-operator`). Once installed, the operator watches for `Kiali` custom resources across the cluster (or a specific namespace) and installs, upgrades, or removes Kiali Server deployments in response.

The operator itself is built on the Ansible Operator SDK. Each reconciliation run executes Ansible playbooks to manage Kiali's lifecycle. This chart does not install Kiali Server directly — for that, use `kiali-server` or create a `Kiali` CR after installing the operator.

## Resources Produced

| Template | Kind | Purpose |
|---|---|---|
| `templates/deployment.yaml` | `Deployment` | Operator pod running the Ansible controller |
| `templates/clusterrole.yaml` | `ClusterRole` | All permissions the operator needs to manage Kiali |
| `templates/clusterrolebinding.yaml` | `ClusterRoleBinding` | Binds the ClusterRole to the operator's ServiceAccount |
| `templates/serviceaccount.yaml` | `ServiceAccount` | Identity used by the operator pod |
| `templates/kiali-cr.yaml` | `Kiali` (CRD instance) | Optional Kiali CR created at install time (`cr.create: true`) |
| `crds/crds.yaml` | `CustomResourceDefinition` | Defines the `kialis.kiali.io` CRD (installed by Helm's `crds/` mechanism) |
| `templates/ossmconsole-crd.yaml` | `CustomResourceDefinition` | Defines `ossmconsoles.kiali.io` — only rendered on OpenShift |

Resources in `skipResources` (`clusterrole`, `clusterrolebinding`, `sa`) are conditionally omitted to support environments where RBAC is managed externally.

## RBAC Model

The ClusterRole (`kiali-operator/templates/clusterrole.yaml`) covers two distinct permission sets:

**Operator management permissions** — what the operator needs to install and manage Kiali:
- Full CRUD on `configmaps`, `endpoints`, `pods`, `serviceaccounts`, `services`, `services/finalizers`, `deployments`, `replicasets`, `horizontalpodautoscalers`, `poddisruptionbudgets`
- `apps/deployments/finalizers` — `update` only, **scoped to resourceName `kiali-operator`**
- `kiali.io/*` resources — full CRUD
- `rbac.authorization.k8s.io` roles and rolebindings — always. **Clusterroles and clusterrolebindings are only added when `clusterRoleCreator: true` OR when `cr.create: true` and `cr.spec.deployment.cluster_wide_access: true`** — this conditionality is security-relevant.
- `extensions`/`networking.k8s.io` ingresses and networkpolicies; `route.openshift.io/routes` (incl. `routes/custom-host`); `oauth.openshift.io/oauthclients`; `console.openshift.io/consolelinks`
- `apiextensions.k8s.io/customresourcedefinitions` — get/list/watch
- `authorization.k8s.io/selfsubjectaccessreviews` — list
- `monitoring.coreos.com/servicemonitors` — create/get
- `config.openshift.io/clusteroperators` — list/watch; get by resourceName `kube-apiserver`
- On OpenShift only: `console.openshift.io/consoleplugins` (full CRUD) and `operator.openshift.io/consoles` (get/list/patch/update/watch)
- Namespace `get`/`list`/`patch`
- Secrets: `create/list/watch` on all secrets; `delete/get/list/patch/update/watch` scoped to `kiali-signing-key`; `get/list/watch` scoped to `kiali-multi-cluster-secret`

**Kiali runtime permissions (escalation)** — the operator must hold all permissions it grants to Kiali, because Kubernetes prevents privilege escalation:
- Read (`get`/`list`/`watch`) on: `configmaps`, `endpoints`, `pods/log`, `namespaces`, `pods`, `replicationcontrollers`, `services`, `daemonsets`, `deployments`, `replicasets`, `statefulsets`, `cronjobs`, `jobs`, `apps.openshift.io/deploymentconfigs`, `config.openshift.io/apiservers`, `route.openshift.io/routes`, `admissionregistration.k8s.io/mutatingwebhookconfigurations`
- `pods/portforward` — create/post
- `authentication.k8s.io/tokenreviews` — create
- All Istio API groups (`config.istio.io`, `networking.istio.io`, `authentication.istio.io`, `rbac.istio.io`, `security.istio.io`, `extensions.istio.io`, `telemetry.istio.io`, `gateway.networking.k8s.io`, `inference.networking.k8s.io`) — `get`/`list`/`watch` always
- When `onlyViewOnlyMode: false` (default): additionally `create`, `delete`, `patch` on all Istio resources, and `patch` on workloads (`pods`, `replicationcontrollers`, `services`, `daemonsets`, `deployments`, `replicasets`, `statefulsets`) and batch resources (`cronjobs`, `jobs`) and `apps.openshift.io/deploymentconfigs`

`onlyViewOnlyMode: true` removes all write verbs from the Kiali runtime section, producing a strictly read-only Kiali installation.

## Operator Deployment

The operator runs as a single pod (controlled by `replicaCount`). Key implementation details:

**Image selection** — configured via `image.repo`, `image.tag`, and `image.digest`. Tag and repo are placeholder tokens (`${HELM_IMAGE_REPO}` / `${HELM_IMAGE_TAG}`) replaced at build time via `envsubst`.

**Watches file** — determines which CRDs the operator reconciles. When `watchesFile` is empty (the default), the template selects automatically:
- OpenShift: `watches-os.yaml` (includes OSSMConsole)
- Kubernetes: `watches-k8s.yaml`

The namespace-watching variants (`watches-os-ns.yaml`, `watches-k8s-ns.yaml`) are **not** selected automatically — they require explicitly setting `watchesFile`. When used, they enable the operator to auto-grant Kiali access to newly created namespaces without a CR update.

**Environment variables passed to the Ansible runtime:**
- `WATCH_NAMESPACE` — restricts operator scope; empty string means watch all namespaces
- `POD_NAME` / `POD_NAMESPACE` — injected via the Kubernetes downward API; conventional Operator SDK vars
- `ALLOW_AD_HOC_KIALI_NAMESPACE` / `ALLOW_AD_HOC_KIALI_IMAGE` / `ALLOW_AD_HOC_CONTAINERS` — security gates that control what Kiali CR authors can override
- `ALLOW_SECURITY_CONTEXT_OVERRIDE` — when false, the operator enforces a restrictive security context on the Kiali container regardless of what the CR specifies
- `ALLOW_ALL_ACCESSIBLE_NAMESPACES` — defaults to `true` (mirrors `allowAllAccessibleNamespaces: true` in `values.yaml`). The template expression is `(cr.create AND cr.spec.deployment.cluster_wide_access) OR allowAllAccessibleNamespaces`, so changing this to false requires explicitly setting `allowAllAccessibleNamespaces: false`
- `ALLOW_AD_HOC_OSSMCONSOLE_IMAGE` — OpenShift only; controls whether CR authors can specify a custom OSSMC image
- `ANSIBLE_DEBUG_LOGS` / `ANSIBLE_VERBOSITY_KIALI_KIALI_IO` — controlled by `debug.enabled` and `debug.verbosity`
- `ANSIBLE_VERBOSITY_OSSMCONSOLE_KIALI_IO` — OpenShift only; set from `debug.verbosity`, same as the Kiali verbosity var
- `ANSIBLE_CONFIG` — switches to profiler config when `debug.enableProfiler: true`
- `ANSIBLE_LOCAL_TEMP` / `ANSIBLE_REMOTE_TEMP` — both set to `/tmp/ansible/tmp`; redirects Ansible's temp file writes into the `/tmp` emptyDir volume mount. This is what makes `readOnlyRootFilesystem: true` viable — without this, Ansible would attempt to write to the root filesystem and fail.
- `PROFILE_TASKS_TASK_OUTPUT_LIMIT` — hardcoded to `"100"`; caps the number of task entries shown in Ansible profiler output

**Security context** — default is restrictive: `allowPrivilegeEscalation: false`, `privileged: false`, `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]`. Overridable via `securityContext`. The pod mounts a `/tmp` emptyDir volume to give Ansible a writable scratch space under the read-only root.

**Probes** — readiness checks `/readyz` on port 6789 (period 30s); liveness checks `/healthz` on port 6789 (period 30s); startup probe checks `/healthz` with `initialDelaySeconds: 30`, `periodSeconds: 10`, `failureThreshold: 6`.

**Metrics** — exposed on `:8080/metrics`. The pod annotation `prometheus.io/scrape` is set to `metrics.enabled` (default `true`).

## CRDs

**`crds/crds.yaml`** — defines `kialis.kiali.io` (`v1alpha1`). Installed via Helm's `crds/` directory mechanism, which means:
- Created on `helm install`, not updated on `helm upgrade` (Helm does not manage CRD lifecycle post-install)
- Kept in sync with the golden copy from the `kiali-operator` upstream repo via `make sync-crds` / `make validate-crd-sync`

**`templates/ossmconsole-crd.yaml`** — defines `ossmconsoles.kiali.io` (`v1alpha1`). Placed in `templates/` rather than `crds/` deliberately: it should only be installed on OpenShift (gated by `.Capabilities.APIVersions.Has "route.openshift.io/v1"`), and `crds/` is never templated by Helm. Important consequence: because this CRD is in `templates/`, **running `helm uninstall` on the operator also deletes this CRD, which purges any existing `OSSMConsole` CRs on the cluster**.

## Key Values Reference

| Value | Default | Purpose |
|---|---|---|
| `image.repo` | `${HELM_IMAGE_REPO}` | Operator image repository |
| `image.tag` | `${HELM_IMAGE_TAG}` | Operator image tag |
| `image.pullPolicy` | `Always` | Image pull policy (e.g., `IfNotPresent` for dev) |
| `watchNamespace` | `""` | Namespace(s) to watch; empty = all |
| `clusterRoleCreator` | `true` | Allow operator to create ClusterRoles for Kiali |
| `onlyViewOnlyMode` | `false` | Restrict all Kiali installs to view-only |
| `allowAdHocKialiNamespace` | `true` | Allow CR to install Kiali in a different namespace |
| `allowAdHocKialiImage` | `false` | Allow CR to specify custom Kiali image |
| `allowAdHocOSSMConsoleImage` | `false` | Allow CR to specify custom OSSMC image (OpenShift only) |
| `allowAdHocContainers` | `false` | Allow CR to add sidecar containers |
| `allowSecurityContextOverride` | `false` | Allow CR to override Kiali container security context |
| `allowAllAccessibleNamespaces` | `true` | Allow `cluster_wide_access: true` in Kiali CRs |
| `skipResources` | `[]` | RBAC resources to skip (for external management) |
| `metrics.enabled` | `true` | Expose Prometheus metrics on `:8080` |
| `debug.enabled` | `true` | Dump full Ansible logs after each reconciliation (verbose by default) |
| `debug.verbosity` | `"1"` | Ansible verbosity level (higher = more output) |
| `debug.enableProfiler` | `false` | Log timing for expensive tasks |
| `watchesFile` | `""` | Override watches file selection |
| `cr.create` | `false` | Create a Kiali CR during install |
| `cr.name` | `kiali` | Name of the Kiali CR to create |
| `cr.namespace` | `""` | Namespace for the Kiali CR (defaults to operator namespace) |
| `cr.spec` | `{deployment: {cluster_wide_access: true}}` | Kiali CR spec |

## OpenShift Support

The operator chart has conditional OpenShift behavior driven by `.Capabilities.APIVersions.Has "route.openshift.io/v1"`:
- When on OpenShift: `ALLOW_AD_HOC_OSSMCONSOLE_IMAGE` env var is injected; `ANSIBLE_VERBOSITY_OSSMCONSOLE_KIALI_IO` is set; the `ossmconsole-crd.yaml` CRD is rendered; additional ClusterRole rules for `consoleplugins` and `operator.openshift.io/consoles` are added.
- When not on OpenShift: none of the above are emitted.

## Managed Kiali CR

Setting `cr.create: true` (default: `false`) causes the chart to create a `Kiali` CR. The namespace precedence is: `watchNamespace` if set → `cr.namespace` if set → the release namespace (implicit). The CR is templated from `cr.spec`.

Note: the default `cr.spec` sets `deployment.cluster_wide_access: true`. When `cr.create: true` and that default is retained, the chart also forces `ALLOW_ALL_ACCESSIBLE_NAMESPACES=true` in the operator deployment, which requires `clusterRoleCreator: true` as well. This cascade is automatic, but means enabling `cr.create` without customizing `cr.spec` implicitly expands the operator's RBAC surface.

The CR's `ansible.sdk.operatorframework.io/verbosity` annotation is set from `debug.verbosity` to control per-CR reconciliation logging independently of the global setting.
