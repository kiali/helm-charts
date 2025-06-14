{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "kiali-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kiali-operator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kiali-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kiali-operator.labels" -}}
{{- if .Values.extraLabels }}
{{ toYaml .Values.extraLabels }}
{{- end }}
helm.sh/chart: {{ include "kiali-operator.chart" . }}
app: {{ include "kiali-operator.name" . }}
{{ include "kiali-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/part-of: "kiali-operator"
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kiali-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kiali-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Returns true if the given resource kind is in .Values.skipResources
This aborts if .Values.skipResources has invalid values.
*/}}
{{- define "kiali-operator.isSkippedResource" -}}
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
