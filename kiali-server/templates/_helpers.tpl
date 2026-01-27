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
Determine the default deployment.tls_config.source.
- If user sets it, honor it.
- Otherwise: "auto" on OpenShift (to read TLSSecurityProfile), "config" elsewhere.
*/}}
{{- define "kiali-server.deployment.tls_config.source" -}}
{{- if .Values.deployment.tls_config.source }}
  {{- .Values.deployment.tls_config.source }}
{{- else }}
  {{- if eq "true" (include "kiali-server.isOpenShift" .) }}
    {{- "auto" }}
  {{- else }}
    {{- "config" }}
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
Returns a list of all secret-backed volume names that require read-only protection.
This centralizes the logic for identifying protected volumes used by both
secureContainers and secureInitContainers helpers.
Returns a JSON array that must be parsed with fromJsonArray.
*/}}
{{- define "kiali-server.secret-volume-names" -}}
{{- $secretVolumes := list }}
{{- /* Core Kiali secrets */ -}}
{{- $secretVolumes = append $secretVolumes (printf "%s-secret" (include "kiali-server.fullname" .)) }}
{{- $secretVolumes = append $secretVolumes (printf "%s-cert" (include "kiali-server.fullname" .)) }}
{{- $secretVolumes = append $secretVolumes "kiali-multi-cluster-secret" }}
{{- /* Custom secrets (non-CSI only) */ -}}
{{- range .Values.deployment.custom_secrets }}
  {{- if not .csi }}
    {{- $secretVolumes = append $secretVolumes .name }}
  {{- end }}
{{- end }}
{{- /* Remote cluster secrets from autodetection */ -}}
{{- range $key, $val := (include "kiali-server.remote-cluster-secrets" .) | fromJson }}
  {{- $secretVolumes = append $secretVolumes $key }}
{{- end }}
{{- /* Explicitly configured cluster secrets */ -}}
{{- range .Values.clustering.clusters }}
  {{- if and (.secret_name) (ne .secret_name "kiali-multi-cluster-secret") }}
    {{- $secretVolumes = append $secretVolumes .name }}
  {{- end }}
{{- end }}
{{- /* Auto-detected credential secrets */ -}}
{{- range $name, $config := (include "kiali-server.credential-secrets" .) | fromJson }}
  {{- $secretVolumes = append $secretVolumes $name }}
{{- end }}
{{- $secretVolumes | toJson }}
{{- end }}

{{/*
Apply security guardrails to user-defined containers.
This enforces the same restrictive security context as the main Kiali container,
ensures secret-backed volumes are mounted read-only, and validates volume mount security.
*/}}
{{- define "kiali-server.secureContainers" -}}
{{- $securedContainers := list }}
{{- $mandatorySecurityContext := dict "allowPrivilegeEscalation" false "privileged" false "readOnlyRootFilesystem" true "runAsNonRoot" true "capabilities" (dict "drop" (list "ALL")) }}
{{- $secretVolumes := include "kiali-server.secret-volume-names" . | fromJsonArray }}
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
{{- $secretVolumes := include "kiali-server.secret-volume-names" . | fromJsonArray }}
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
Extract a single credential secret from a value if it matches the secret:<name>:<key> pattern.
Returns a single-entry dict as JSON, or empty dict if no match.

Parameters (passed as dict):
  - value: The credential value to check
  - volumeName: The volume name to use for the secret
  - fileName: The file name to use (or "useSecretKey" to use the secret key as filename)

Example: include "kiali-server.extract-secret" (dict "value" $auth.password "volumeName" "prometheus-password" "fileName" "value.txt")
*/}}
{{- define "kiali-server.extract-secret" -}}
{{- $result := dict }}
{{- if and .value (regexMatch "^secret:.+:.+" .value) }}
  {{- $parts := regexSplit ":" .value 3 }}
  {{- $secretName := index $parts 1 }}
  {{- $secretKey := index $parts 2 }}
  {{- $fileName := .fileName }}
  {{- if eq $fileName "useSecretKey" }}
    {{- $fileName = $secretKey }}
  {{- end }}
  {{- $result = dict .volumeName (dict "secret_name" $secretName "secret_key" $secretKey "file_name" $fileName) }}
{{- end }}
{{- $result | toJson }}
{{- end }}

{{/*
Process all standard auth credentials for a service.
Returns a dict of secrets as JSON.

Parameters (passed as dict):
  - auth: The auth object containing username, password, token, cert_file, key_file
  - prefix: The volume name prefix (e.g., "prometheus", "grafana")
  - hasToken: Whether token auth is supported (default true)

Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead.
*/}}
{{- define "kiali-server.process-auth-secrets" -}}
{{- $result := dict }}
{{- if .auth }}
  {{- /* Username */ -}}
  {{- $result = merge $result (include "kiali-server.extract-secret" (dict "value" .auth.username "volumeName" (printf "%s-username" .prefix) "fileName" "value.txt") | fromJson) }}
  {{- /* Password */ -}}
  {{- $result = merge $result (include "kiali-server.extract-secret" (dict "value" .auth.password "volumeName" (printf "%s-password" .prefix) "fileName" "value.txt") | fromJson) }}
  {{- /* Token (if supported) */ -}}
  {{- if (ne .hasToken false) }}
    {{- $result = merge $result (include "kiali-server.extract-secret" (dict "value" .auth.token "volumeName" (printf "%s-token" .prefix) "fileName" "value.txt") | fromJson) }}
  {{- end }}
  {{- /* Cert file - uses secret key as filename */ -}}
  {{- $result = merge $result (include "kiali-server.extract-secret" (dict "value" .auth.cert_file "volumeName" (printf "%s-cert" .prefix) "fileName" "useSecretKey") | fromJson) }}
  {{- /* Key file - uses secret key as filename */ -}}
  {{- $result = merge $result (include "kiali-server.extract-secret" (dict "value" .auth.key_file "volumeName" (printf "%s-key" .prefix) "fileName" "useSecretKey") | fromJson) }}
{{- end }}
{{- $result | toJson }}
{{- end }}

{{/*
Sanitize a name to be used in credential secret volume names.
*/}}
{{- define "kiali-server.sanitize-credential-name" -}}
{{- $name := lower . -}}
{{- $name = regexReplaceAll "[^a-z0-9-]+" $name "-" -}}
{{- $name = trimAll "-" $name -}}
{{- if eq $name "" }}unknown{{ else }}{{ $name }}{{ end }}
{{- end }}

{{/*
Detect credential values that use the secret:<secretName>:<secretKey> pattern.
Scans external_services auth fields and login_token.signing_key.
Returns a JSON object with volume configurations for auto-mounting these secrets.

For simple credentials (username, password, token), the file is named "value.txt".
For file-based credentials (cert_file, key_file), the original secret key name is preserved.
Note: ca_file is deprecated in Kiali - use kiali-cabundle ConfigMap instead.

Example output:
{
  "prometheus-password": {"secret_name": "my-creds", "secret_key": "password", "file_name": "value.txt"},
  "grafana-cert": {"secret_name": "tls-certs", "secret_key": "tls.crt", "file_name": "tls.crt"}
}
*/}}
{{- define "kiali-server.credential-secrets" -}}
{{- $secrets := dict }}

{{- if .Values.external_services }}
  {{- /* Prometheus - always processed, no enabled check */ -}}
  {{- if and .Values.external_services.prometheus .Values.external_services.prometheus.auth }}
    {{- $secrets = merge $secrets (include "kiali-server.process-auth-secrets" (dict "auth" .Values.external_services.prometheus.auth "prefix" "prometheus") | fromJson) }}
  {{- end }}

  {{- /* Grafana - only if enabled */ -}}
  {{- if and .Values.external_services.grafana .Values.external_services.grafana.enabled .Values.external_services.grafana.auth }}
    {{- $secrets = merge $secrets (include "kiali-server.process-auth-secrets" (dict "auth" .Values.external_services.grafana.auth "prefix" "grafana") | fromJson) }}
  {{- end }}

  {{- /* Tracing - only if enabled */ -}}
  {{- if and .Values.external_services.tracing .Values.external_services.tracing.enabled .Values.external_services.tracing.auth }}
    {{- $secrets = merge $secrets (include "kiali-server.process-auth-secrets" (dict "auth" .Values.external_services.tracing.auth "prefix" "tracing") | fromJson) }}
  {{- end }}

  {{- /* Perses - only if enabled, no token support */ -}}
  {{- if and .Values.external_services.perses .Values.external_services.perses.enabled .Values.external_services.perses.auth }}
    {{- $secrets = merge $secrets (include "kiali-server.process-auth-secrets" (dict "auth" .Values.external_services.perses.auth "prefix" "perses" "hasToken" false) | fromJson) }}
  {{- end }}

  {{- /* Custom Dashboards Prometheus - only if enabled */ -}}
  {{- if and .Values.external_services.custom_dashboards .Values.external_services.custom_dashboards.enabled .Values.external_services.custom_dashboards.prometheus .Values.external_services.custom_dashboards.prometheus.auth }}
    {{- $secrets = merge $secrets (include "kiali-server.process-auth-secrets" (dict "auth" .Values.external_services.custom_dashboards.prometheus.auth "prefix" "customdashboards-prometheus") | fromJson) }}
  {{- end }}
{{- end }}

{{- if and .Values.chat_ai .Values.chat_ai.enabled }}
  {{- range $provider := .Values.chat_ai.providers }}
    {{- $providerName := include "kiali-server.sanitize-credential-name" $provider.name }}
    {{- if $provider.enabled }}
      {{- if and $provider.key (regexMatch "^secret:.+:.+" $provider.key) }}
        {{- $volumeName := printf "chat-ai-provider-%s" $providerName }}
        {{- $secrets = merge $secrets (include "kiali-server.extract-secret" (dict "value" $provider.key "volumeName" $volumeName "fileName" "value.txt") | fromJson) }}
      {{- end }}
      {{- range $model := $provider.models }}
        {{- $modelName := include "kiali-server.sanitize-credential-name" $model.name }}
        {{- if and $model.enabled $model.key (regexMatch "^secret:.+:.+" $model.key) }}
          {{- $volumeName := printf "chat-ai-model-%s-%s" $providerName $modelName }}
          {{- $secrets = merge $secrets (include "kiali-server.extract-secret" (dict "value" $model.key "volumeName" $volumeName "fileName" "value.txt") | fromJson) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- /* Login token signing key - always processed */ -}}
{{- if .Values.login_token }}
  {{- $secrets = merge $secrets (include "kiali-server.extract-secret" (dict "value" .Values.login_token.signing_key "volumeName" "login-token-signing-key" "fileName" "value.txt") | fromJson) }}
{{- end }}

{{- $secrets | toJson }}
{{- end }}
