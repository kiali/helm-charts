{{/* vim: set filetype=mustache: */}}

{{/*
Create a default fully qualified instance name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
To simulate the way the operator works, use deployment.instance_name.
*/}}
{{- define "kiali-server.fullname" -}}
{{- .Values.deployment.instance_name | trunc 63 }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kiali-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Determine if on OpenShift (when debugging the chart for OpenShift use-cases, set "simulateOpenShift")
*/}}
{{- define "kiali-server.isOpenShift" -}}
{{- .Values.isOpenShift | default (.Capabilities.APIVersions.Has "operator.openshift.io/v1") -}}
{{- end }}

{{/*
Identifies the log_level.
*/}}
{{- define "kiali-server.logLevel" -}}
{{- .Values.deployment.logger.log_level -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kiali-server.labels" -}}
{{- if .Values.deployment.extra_labels }}
{{ toYaml .Values.deployment.extra_labels }}
{{- end }}
helm.sh/chart: {{ include "kiali-server.chart" . }}
app: kiali
{{ include "kiali-server.selectorLabels" . }}
version: {{ .Values.deployment.version_label | default .Chart.AppVersion | quote }}
app.kubernetes.io/version: {{ .Values.deployment.version_label | default .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: "kiali"
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kiali-server.selectorLabels" -}}
app.kubernetes.io/name: kiali
app.kubernetes.io/instance: {{ include "kiali-server.fullname" . }}
{{- end }}

{{/*
Determine the default login token signing key.
*/}}
{{- define "kiali-server.login_token.signing_key" -}}
{{- if .Values.login_token.signing_key }}
  {{- .Values.login_token.signing_key }}
{{- else }}
  {{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Determine the default web root.
*/}}
{{- define "kiali-server.server.web_root" -}}
{{- if .Values.server.web_root  }}
  {{- if (eq .Values.server.web_root "/") }}
    {{- .Values.server.web_root }}
  {{- else }}
    {{- .Values.server.web_root | trimSuffix "/" }}
  {{- end }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "/" }}
  {{- else }}
    {{- "/kiali" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the default identity cert file. There is no default if on k8s; only on OpenShift.
*/}}
{{- define "kiali-server.identity.cert_file" -}}
{{- if hasKey .Values.identity "cert_file" }}
  {{- .Values.identity.cert_file }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "/kiali-cert/tls.crt" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the default identity private key file. There is no default if on k8s; only on OpenShift.
*/}}
{{- define "kiali-server.identity.private_key_file" -}}
{{- if hasKey .Values.identity "private_key_file" }}
  {{- .Values.identity.private_key_file }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "/kiali-cert/tls.key" }}
  {{- else }}
    {{- "" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the default deployment.ingress.enabled. Disable it on k8s; enable it on OpenShift.
*/}}
{{- define "kiali-server.deployment.ingress.enabled" -}}
{{- if hasKey .Values.deployment.ingress "enabled" }}
  {{- .Values.deployment.ingress.enabled }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- true }}
  {{- else }}
    {{- false }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the auth strategy to use - default is "token" on Kubernetes and "openshift" on OpenShift.
*/}}
{{- define "kiali-server.auth.strategy" -}}
{{- if .Values.auth.strategy }}
  {{- if (and ((and (eq .Values.auth.strategy "openshift") (not .Values.kiali_route_url))) (not .Values.auth.openshift.redirect_uris)) }}
    {{- fail "You did not define what the Kiali Route URL will be (--set kiali_route_url=...). Without this set, the openshift auth strategy will not work. Either (a) set that, (b) explicitly define redirect URIs via --set auth.openshift.redirect_uris, or (c) use a different auth strategy via the --set auth.strategy=... option." }}
  {{- end }}
  {{- .Values.auth.strategy }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- if (and (not .Values.kiali_route_url) (not .Values.auth.openshift.redirect_uris)) }}
      {{- fail "You did not define what the Kiali Route URL will be (--set kiali_route_url=...). Without this set, the openshift auth strategy will not work. Either (a) set that, (b) explicitly define redirect URIs via --set auth.openshift.redirect_uris, or (c) use a different auth strategy via the --set auth.strategy=... option." }}
    {{- end }}
    {{- "openshift" }}
  {{- else }}
    {{- "token" }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Determine the root namespace - default is where Kiali is installed.
*/}}
{{- define "kiali-server.external_services.istio.root_namespace" -}}
{{- if .Values.external_services.istio.root_namespace }}
  {{- .Values.external_services.istio.root_namespace }}
{{- else }}
  {{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Autodetect remote cluster secrets if enabled - looks for secrets in the same namespace where Kiali is installed.
Note that this will ignore any secret named "kiali-multi-cluster-secret" because that will optionally be mounted always.
Returns a JSON dict whose keys are the cluster names and values are the cluster secret data.
*/}}
{{- define "kiali-server.remote-cluster-secrets" -}}
{{- $theDict := dict }}
{{- if .Values.clustering.autodetect_secrets.enabled }}
  {{- $secretLabelToLookFor := (regexSplit "=" .Values.clustering.autodetect_secrets.label 2) }}
  {{- $secretLabelNameToLookFor := first $secretLabelToLookFor }}
  {{- $secretLabelValueToLookFor := last $secretLabelToLookFor }}
  {{- range $i, $secret := (lookup "v1" "Secret" .Release.Namespace "").items }}
    {{- if ne $secret.metadata.name "kiali-multi-cluster-secret" }}
      {{- if (and (and (hasKey $secret.metadata "labels") (hasKey $secret.metadata.labels $secretLabelNameToLookFor)) (eq (get $secret.metadata.labels $secretLabelNameToLookFor) ($secretLabelValueToLookFor))) }}
        {{- $clusterName := $secret.metadata.name }}
        {{- if (and (hasKey $secret.metadata "annotations") (hasKey $secret.metadata.annotations "kiali.io/cluster")) }}
          {{- $clusterName = get $secret.metadata.annotations "kiali.io/cluster" }}
        {{- end }}
        {{- $theDict = set $theDict $clusterName $secret.metadata.name }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $theDict | toJson }}
{{- end }}

{{/*
Returns true if the given resource kind is in .Values.skipResources
This aborts if .Values.skipResources has invalid values.
*/}}
{{- define "kiali-server.isSkippedResource" -}}
  {{- $validSkipResources := dict "clusterrole" true "clusterrolebinding" true "sa" true }}
  {{- $ctx := .ctx }}
  {{- $name := .name }}
  {{- range $i, $item := $ctx.Values.skipResources }}
    {{- if not (hasKey $validSkipResources $item) }}
      {{- fail (printf "Aborting due to an invalid entry [%q] in skipResources: %q. Valid list item values are: %q" $item $ctx.Values.skipResources (keys $validSkipResources)) }}
    {{- end }}
  {{- end }}
  {{- has $name $ctx.Values.skipResources }}
{{- end }}

{{/*
Apply security guardrails to user-defined containers.
This enforces the same restrictive security context as the main Kiali container,
ensures secret-backed volumes are mounted read-only, and validates volume mount security.
*/}}
{{- define "kiali-server.secureContainers" -}}
{{- $securedContainers := list }}
{{- $mandatorySecurityContext := dict "allowPrivilegeEscalation" false "privileged" false "readOnlyRootFilesystem" true "runAsNonRoot" true "capabilities" (dict "drop" (list "ALL")) }}
{{- /* Identify secret-backed volumes dynamically */ -}}
{{- $secretVolumes := list }}
{{- $secretVolumes = append $secretVolumes (printf "%s-secret" (include "kiali-server.fullname" .)) }}
{{- $secretVolumes = append $secretVolumes (printf "%s-cert" (include "kiali-server.fullname" .)) }}
{{- $secretVolumes = append $secretVolumes "kiali-multi-cluster-secret" }}
{{- range .Values.deployment.custom_secrets }}
  {{- if not .csi }}
    {{- $secretVolumes = append $secretVolumes .name }}
  {{- end }}
{{- end }}
{{- range $key, $val := (include "kiali-server.remote-cluster-secrets" .) | fromJson }}
  {{- $secretVolumes = append $secretVolumes $key }}
{{- end }}
{{- range .Values.clustering.clusters }}
  {{- if and (.secret_name) (ne .secret_name "kiali-multi-cluster-secret") }}
    {{- $secretVolumes = append $secretVolumes .name }}
  {{- end }}
{{- end }}
{{- /* Add auto-detected credential secrets to protected list */ -}}
{{- range $name, $config := (include "kiali-server.credential-secrets" .) | fromJson }}
  {{- $secretVolumes = append $secretVolumes $name }}
{{- end }}
{{- /* Validate containers don't mount secret volumes read-write */ -}}
{{- range .Values.deployment.additional_pod_containers_yaml }}
  {{- if hasKey . "volumeMounts" }}
    {{- range .volumeMounts }}
      {{- if and (has .name $secretVolumes) (hasKey . "readOnly") (not .readOnly) }}
        {{- fail (printf "User-defined container cannot mount secret-backed volume [%s] as read-write. This volume must be mounted read-only for security." .name) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- /* Apply security guardrails to each container */ -}}
{{- range .Values.deployment.additional_pod_containers_yaml }}
  {{- $container := . }}
  {{- /* Apply mandatory security context */ -}}
  {{- $container = mergeOverwrite $container (dict "securityContext" $mandatorySecurityContext) }}
  {{- /* Secure volume mounts */ -}}
  {{- if hasKey $container "volumeMounts" }}
    {{- $securedMounts := list }}
    {{- range $container.volumeMounts }}
      {{- $mount := . }}
      {{- /* Force read-only for secret-backed volumes */ -}}
      {{- if has $mount.name $secretVolumes }}
        {{- $mount = mergeOverwrite $mount (dict "readOnly" true) }}
      {{- end }}
      {{- $securedMounts = append $securedMounts $mount }}
    {{- end }}
    {{- $container = mergeOverwrite $container (dict "volumeMounts" $securedMounts) }}
  {{- end }}
  {{- $securedContainers = append $securedContainers $container }}
{{- end }}
{{- $securedContainers | toYaml }}
{{- end }}

{{/*
Apply security guardrails to user-defined initContainers.
This enforces the same restrictive security context as the main Kiali container,
ensures secret-backed volumes are mounted read-only, and validates volume mount security.
*/}}
{{- define "kiali-server.secureInitContainers" -}}
{{- $securedInitContainers := list }}
{{- $mandatorySecurityContext := dict "allowPrivilegeEscalation" false "privileged" false "readOnlyRootFilesystem" true "runAsNonRoot" true "capabilities" (dict "drop" (list "ALL")) }}
{{- /* Identify secret-backed volumes dynamically */ -}}
{{- $secretVolumes := list }}
{{- $secretVolumes = append $secretVolumes (printf "%s-secret" (include "kiali-server.fullname" .)) }}
{{- $secretVolumes = append $secretVolumes (printf "%s-cert" (include "kiali-server.fullname" .)) }}
{{- $secretVolumes = append $secretVolumes "kiali-multi-cluster-secret" }}
{{- range .Values.deployment.custom_secrets }}
  {{- if not .csi }}
    {{- $secretVolumes = append $secretVolumes .name }}
  {{- end }}
{{- end }}
{{- range $key, $val := (include "kiali-server.remote-cluster-secrets" .) | fromJson }}
  {{- $secretVolumes = append $secretVolumes $key }}
{{- end }}
{{- range .Values.clustering.clusters }}
  {{- if and (.secret_name) (ne .secret_name "kiali-multi-cluster-secret") }}
    {{- $secretVolumes = append $secretVolumes .name }}
  {{- end }}
{{- end }}
{{- /* Add auto-detected credential secrets to protected list */ -}}
{{- range $name, $config := (include "kiali-server.credential-secrets" .) | fromJson }}
  {{- $secretVolumes = append $secretVolumes $name }}
{{- end }}
{{- /* Validate initContainers don't mount secret volumes read-write */ -}}
{{- range .Values.deployment.additional_pod_init_containers_yaml }}
  {{- if hasKey . "volumeMounts" }}
    {{- range .volumeMounts }}
      {{- if and (has .name $secretVolumes) (hasKey . "readOnly") (not .readOnly) }}
        {{- fail (printf "User-defined initContainer cannot mount secret-backed volume [%s] as read-write. This volume must be mounted read-only for security." .name) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- /* Apply security guardrails to each initContainer */ -}}
{{- range .Values.deployment.additional_pod_init_containers_yaml }}
  {{- $container := . }}
  {{- /* Apply mandatory security context */ -}}
  {{- $container = mergeOverwrite $container (dict "securityContext" $mandatorySecurityContext) }}
  {{- /* Secure volume mounts */ -}}
  {{- if hasKey $container "volumeMounts" }}
    {{- $securedMounts := list }}
    {{- range $container.volumeMounts }}
      {{- $mount := . }}
      {{- /* Force read-only for secret-backed volumes */ -}}
      {{- if has $mount.name $secretVolumes }}
        {{- $mount = mergeOverwrite $mount (dict "readOnly" true) }}
      {{- end }}
      {{- $securedMounts = append $securedMounts $mount }}
    {{- end }}
    {{- $container = mergeOverwrite $container (dict "volumeMounts" $securedMounts) }}
  {{- end }}
  {{- $securedInitContainers = append $securedInitContainers $container }}
{{- end }}
{{- $securedInitContainers | toYaml }}
{{- end }}

{{/*
Get the list of accessible namespaces when cluster_wide_access is false.
This function uses discovery_selectors to find namespaces that match the label selectors (only works with helm install/upgrade, not template).
It always includes the Kiali deployment namespace.
Note: The Istio control plane namespace should be included by the user in the defined discovery_selectors
Returns a comma-separated string of namespace names.
*/}}
{{- define "kiali-server.accessible-namespaces" -}}
{{- $namespaces := list }}
{{- $kialiNamespace := .Release.Namespace }}
{{- if .Values.deployment.cluster_wide_access }}
  {{- /* When cluster_wide_access is true, this function should not be called */ -}}
  {{- fail "kiali-server.accessible-namespaces should only be called when cluster_wide_access is false" }}
{{- else }}
  {{- /* Always include Kiali's own namespace */ -}}
  {{- $namespaces = append $namespaces $kialiNamespace }}
  {{- /* Process discovery selectors if they are defined (only works with helm install/upgrade, not helm template) */ -}}
  {{- if and .Values.deployment.discovery_selectors .Values.deployment.discovery_selectors.default }}
    {{- /* Note: lookup only works with helm install/upgrade, not helm template */ -}}
    {{- /* During helm template, lookup returns nil/empty, so this section is safely skipped */ -}}
    {{- $allNamespaces := lookup "v1" "Namespace" "" "" }}
    {{- if $allNamespaces }}
      {{- if kindIs "map" $allNamespaces }}
        {{- if hasKey $allNamespaces "items" }}
          {{- range $selector := .Values.deployment.discovery_selectors.default }}
            {{- range $ns := $allNamespaces.items }}
              {{- $labelsMatch := true }}
              {{- $exprsMatch := true }}
              {{- if $ns.metadata.labels }}
                {{- if $selector.matchLabels }}
                  {{- $labelsMatch = false }}
                  {{- $allLabelsMatch := true }}
                  {{- range $key, $value := $selector.matchLabels }}
                    {{- if not (hasKey $ns.metadata.labels $key) }}
                      {{- $allLabelsMatch = false }}
                    {{- else if ne (get $ns.metadata.labels $key) $value }}
                      {{- $allLabelsMatch = false }}
                    {{- end }}
                  {{- end }}
                  {{- if $allLabelsMatch }}
                    {{- $labelsMatch = true }}
                  {{- end }}
                {{- end }}
                {{- if $selector.matchExpressions }}
                  {{- $exprsMatch = false }}
                  {{- $allExprsMatch := true }}
                  {{- range $expr := $selector.matchExpressions }}
                    {{- if eq $expr.operator "In" }}
                      {{- if hasKey $ns.metadata.labels $expr.key }}
                        {{- if not (has (get $ns.metadata.labels $expr.key) $expr.values) }}
                          {{- $allExprsMatch = false }}
                        {{- end }}
                      {{- else }}
                        {{- $allExprsMatch = false }}
                      {{- end }}
                    {{- else if eq $expr.operator "NotIn" }}
                      {{- if hasKey $ns.metadata.labels $expr.key }}
                        {{- if has (get $ns.metadata.labels $expr.key) $expr.values }}
                          {{- $allExprsMatch = false }}
                        {{- end }}
                      {{- end }}
                    {{- else if eq $expr.operator "Exists" }}
                      {{- if not (hasKey $ns.metadata.labels $expr.key) }}
                        {{- $allExprsMatch = false }}
                      {{- end }}
                    {{- else if eq $expr.operator "DoesNotExist" }}
                      {{- if hasKey $ns.metadata.labels $expr.key }}
                        {{- $allExprsMatch = false }}
                      {{- end }}
                    {{- end }}
                  {{- end }}
                  {{- if $allExprsMatch }}
                    {{- $exprsMatch = true }}
                  {{- end }}
                {{- end }}
              {{- end }}
              {{- if and $labelsMatch $exprsMatch }}
                {{- if not (has $ns.metadata.name $namespaces) }}
                  {{- $namespaces = append $namespaces $ns.metadata.name }}
                {{- end }}
              {{- end }}
            {{- end }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $namespaces | uniq | sortAlpha | join "," }}
{{- end }}

{{/*
Convert accessible namespaces to discovery selectors format for the ConfigMap.
When cluster_wide_access is false, this converts the discovered namespace list into
a discovery selector that uses matchExpressions on kubernetes.io/metadata.name.
This ensures the Kiali server knows the exact namespaces it has RBAC access to.
Returns a dict structure (not YAML string).
*/}}
{{- define "kiali-server.discovery-selectors-for-config" -}}
{{- if not .Values.deployment.cluster_wide_access }}
  {{- $accessibleNamespacesStr := include "kiali-server.accessible-namespaces" . -}}
  {{- $accessibleNamespaces := splitList "," $accessibleNamespacesStr -}}
  {{- if $accessibleNamespaces }}
    {{- $matchExpression := dict "key" "kubernetes.io/metadata.name" "operator" "In" "values" $accessibleNamespaces }}
    {{- $selector := dict "matchExpressions" (list $matchExpression) }}
    {{- $result := dict "default" (list $selector) }}
    {{- $result | toYaml }}
  {{- else }}
    {{- dict | toYaml }}
  {{- end }}
{{- else }}
  {{- if .Values.deployment.discovery_selectors }}
    {{- .Values.deployment.discovery_selectors | toYaml }}
  {{- else }}
    {{- dict | toYaml }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Detect credential values that use the secret:<secretName>:<secretKey> pattern.
Scans external_services auth fields and login_token.signing_key.
Returns a JSON object with volume configurations for auto-mounting these secrets.

For simple credentials (username, password, token), the file is named "value.txt".
For file-based credentials (ca_file, cert_file, key_file), the original secret key name is preserved.

Example output:
{
  "prometheus-password": {"secret_name": "my-creds", "secret_key": "password", "file_name": "value.txt"},
  "grafana-cert": {"secret_name": "tls-certs", "secret_key": "tls.crt", "file_name": "tls.crt"}
}
*/}}
{{- define "kiali-server.credential-secrets" -}}
{{- $secrets := dict }}

{{- /* Helper to check if value matches secret pattern and add to secrets dict */ -}}
{{- /* Process Prometheus auth credentials (always processed, no enabled check) */ -}}
{{- if .Values.external_services }}
  {{- if .Values.external_services.prometheus }}
    {{- if .Values.external_services.prometheus.auth }}
      {{- $auth := .Values.external_services.prometheus.auth }}
      {{- if and $auth.username (regexMatch "^secret:.+:.+" $auth.username) }}
        {{- $parts := regexSplit ":" $auth.username 3 }}
        {{- $secrets = set $secrets "prometheus-username" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
      {{- end }}
      {{- if and $auth.password (regexMatch "^secret:.+:.+" $auth.password) }}
        {{- $parts := regexSplit ":" $auth.password 3 }}
        {{- $secrets = set $secrets "prometheus-password" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
      {{- end }}
      {{- if and $auth.token (regexMatch "^secret:.+:.+" $auth.token) }}
        {{- $parts := regexSplit ":" $auth.token 3 }}
        {{- $secrets = set $secrets "prometheus-token" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
      {{- end }}
      {{- /* Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead */ -}}
      {{- if and $auth.cert_file (regexMatch "^secret:.+:.+" $auth.cert_file) }}
        {{- $parts := regexSplit ":" $auth.cert_file 3 }}
        {{- $secrets = set $secrets "prometheus-cert" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
      {{- end }}
      {{- if and $auth.key_file (regexMatch "^secret:.+:.+" $auth.key_file) }}
        {{- $parts := regexSplit ":" $auth.key_file 3 }}
        {{- $secrets = set $secrets "prometheus-key" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- /* Process Grafana auth credentials (only if enabled) */ -}}
  {{- if .Values.external_services.grafana }}
    {{- if .Values.external_services.grafana.enabled }}
      {{- if .Values.external_services.grafana.auth }}
        {{- $auth := .Values.external_services.grafana.auth }}
        {{- if and $auth.username (regexMatch "^secret:.+:.+" $auth.username) }}
          {{- $parts := regexSplit ":" $auth.username 3 }}
          {{- $secrets = set $secrets "grafana-username" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.password (regexMatch "^secret:.+:.+" $auth.password) }}
          {{- $parts := regexSplit ":" $auth.password 3 }}
          {{- $secrets = set $secrets "grafana-password" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.token (regexMatch "^secret:.+:.+" $auth.token) }}
          {{- $parts := regexSplit ":" $auth.token 3 }}
          {{- $secrets = set $secrets "grafana-token" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- /* Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead */ -}}
        {{- if and $auth.cert_file (regexMatch "^secret:.+:.+" $auth.cert_file) }}
          {{- $parts := regexSplit ":" $auth.cert_file 3 }}
          {{- $secrets = set $secrets "grafana-cert" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
        {{- if and $auth.key_file (regexMatch "^secret:.+:.+" $auth.key_file) }}
          {{- $parts := regexSplit ":" $auth.key_file 3 }}
          {{- $secrets = set $secrets "grafana-key" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- /* Process Tracing auth credentials (only if enabled) */ -}}
  {{- if .Values.external_services.tracing }}
    {{- if .Values.external_services.tracing.enabled }}
      {{- if .Values.external_services.tracing.auth }}
        {{- $auth := .Values.external_services.tracing.auth }}
        {{- if and $auth.username (regexMatch "^secret:.+:.+" $auth.username) }}
          {{- $parts := regexSplit ":" $auth.username 3 }}
          {{- $secrets = set $secrets "tracing-username" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.password (regexMatch "^secret:.+:.+" $auth.password) }}
          {{- $parts := regexSplit ":" $auth.password 3 }}
          {{- $secrets = set $secrets "tracing-password" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.token (regexMatch "^secret:.+:.+" $auth.token) }}
          {{- $parts := regexSplit ":" $auth.token 3 }}
          {{- $secrets = set $secrets "tracing-token" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- /* Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead */ -}}
        {{- if and $auth.cert_file (regexMatch "^secret:.+:.+" $auth.cert_file) }}
          {{- $parts := regexSplit ":" $auth.cert_file 3 }}
          {{- $secrets = set $secrets "tracing-cert" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
        {{- if and $auth.key_file (regexMatch "^secret:.+:.+" $auth.key_file) }}
          {{- $parts := regexSplit ":" $auth.key_file 3 }}
          {{- $secrets = set $secrets "tracing-key" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- /* Process Perses auth credentials (only if enabled) */ -}}
  {{- if .Values.external_services.perses }}
    {{- if .Values.external_services.perses.enabled }}
      {{- if .Values.external_services.perses.auth }}
        {{- $auth := .Values.external_services.perses.auth }}
        {{- if and $auth.username (regexMatch "^secret:.+:.+" $auth.username) }}
          {{- $parts := regexSplit ":" $auth.username 3 }}
          {{- $secrets = set $secrets "perses-username" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.password (regexMatch "^secret:.+:.+" $auth.password) }}
          {{- $parts := regexSplit ":" $auth.password 3 }}
          {{- $secrets = set $secrets "perses-password" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- /* Note: Perses does not support token auth in Kiali server */ -}}
        {{- /* Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead */ -}}
        {{- if and $auth.cert_file (regexMatch "^secret:.+:.+" $auth.cert_file) }}
          {{- $parts := regexSplit ":" $auth.cert_file 3 }}
          {{- $secrets = set $secrets "perses-cert" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
        {{- if and $auth.key_file (regexMatch "^secret:.+:.+" $auth.key_file) }}
          {{- $parts := regexSplit ":" $auth.key_file 3 }}
          {{- $secrets = set $secrets "perses-key" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- /* Process Custom Dashboards Prometheus auth credentials (always processed) */ -}}
  {{- if .Values.external_services.custom_dashboards }}
    {{- if .Values.external_services.custom_dashboards.prometheus }}
      {{- if .Values.external_services.custom_dashboards.prometheus.auth }}
        {{- $auth := .Values.external_services.custom_dashboards.prometheus.auth }}
        {{- if and $auth.username (regexMatch "^secret:.+:.+" $auth.username) }}
          {{- $parts := regexSplit ":" $auth.username 3 }}
          {{- $secrets = set $secrets "customdashboards-prometheus-username" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.password (regexMatch "^secret:.+:.+" $auth.password) }}
          {{- $parts := regexSplit ":" $auth.password 3 }}
          {{- $secrets = set $secrets "customdashboards-prometheus-password" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- if and $auth.token (regexMatch "^secret:.+:.+" $auth.token) }}
          {{- $parts := regexSplit ":" $auth.token 3 }}
          {{- $secrets = set $secrets "customdashboards-prometheus-token" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
        {{- end }}
        {{- /* Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead */ -}}
        {{- if and $auth.cert_file (regexMatch "^secret:.+:.+" $auth.cert_file) }}
          {{- $parts := regexSplit ":" $auth.cert_file 3 }}
          {{- $secrets = set $secrets "customdashboards-prometheus-cert" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
        {{- if and $auth.key_file (regexMatch "^secret:.+:.+" $auth.key_file) }}
          {{- $parts := regexSplit ":" $auth.key_file 3 }}
          {{- $secrets = set $secrets "customdashboards-prometheus-key" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" (index $parts 2)) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- /* Process login_token.signing_key (always processed) */ -}}
{{- if .Values.login_token }}
  {{- if and .Values.login_token.signing_key (regexMatch "^secret:.+:.+" .Values.login_token.signing_key) }}
    {{- $parts := regexSplit ":" .Values.login_token.signing_key 3 }}
    {{- $secrets = set $secrets "login-token-signing-key" (dict "secret_name" (index $parts 1) "secret_key" (index $parts 2) "file_name" "value.txt") }}
  {{- end }}
{{- end }}

{{- $secrets | toJson }}
{{- end }}
