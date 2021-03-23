{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "kiali-olm.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kiali-olm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kiali-olm.labels" -}}
helm.sh/chart: {{ include "kiali-olm.chart" . }}
app.kubernetes.io/name: {{ include "kiali-olm.name" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: "kiali-olm"
{{- end }}

{{/*
Settings
*/}}
{{- define "subscription.name" -}}
{{- if .Values.name -}}
  {{- .Values.name }}
{{- else if eq .Values.operatorType "community" -}}
  kiali
{{- else if eq .Values.operatorType "redhat" -}}
  kiali-ossm
{{- else -}}
  {{- fail (printf "Invalid operatorType [%s]. Must be either 'community' or 'redhat'" .Values.operatorType) -}}
{{- end }}
{{- end }}

{{- define "subscription.namespace" -}}
{{- .Values.namespace | default "openshift-operators" }}
{{- end }}

{{- define "subscription.channel" -}}
{{- .Values.channel | default "stable" }}
{{- end }}

{{- define "subscription.source" -}}
{{- if .Values.source -}}
  {{- .Values.source }}
{{- else if eq .Values.operatorType "community" -}}
  community-operators
{{- else if eq .Values.operatorType "redhat" -}}
  redhat-operators
{{- else }}
  {{- fail (printf "Invalid operatorType [%s]. Must be either 'community' or 'redhat'" .Values.operatorType) -}}
{{- end }}
{{- end }}

{{- define "subscription.sourceNamespace" -}}
{{- .Values.sourceNamespace | default "openshift-marketplace" }}
{{- end }}

{{- define "subscription.installPlanApproval" -}}
{{- .Values.installPlanApproval | default "Automatic" }}
{{- end }}
