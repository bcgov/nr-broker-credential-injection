{{/*
Expand the name of the chart.
*/}}
{{- define "knox-tools-sync.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name (just the release name).
*/}}
{{- define "knox-tools-sync.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "knox-tools-sync.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "knox-tools-sync.labels" -}}
helm.sh/chart: {{ include "knox-tools-sync.chart" . }}
{{ include "knox-tools-sync.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "knox-tools-sync.selectorLabels" -}}
app.kubernetes.io/name: {{ include "knox-tools-sync.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Values.global.name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "knox-tools-sync.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- "nr-broker-sync" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create the name of the long-lived token secret to use.
*/}}
{{- define "knox-tools-sync.tokenSecretName" -}}
{{- if .Values.token.name }}
{{- .Values.token.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-token" (include "knox-tools-sync.serviceAccountName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
