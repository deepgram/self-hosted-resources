{{/*
Chart name + version for the helm.sh/chart label.
*/}}
{{- define "deepgram-aiworks.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully-qualified app name. Truncated to 63 chars (k8s name limit). Suffixed
with the Helm release name so multiple releases in one namespace don't collide.
*/}}
{{- define "deepgram-aiworks.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "deepgram-aiworks.labels" -}}
app.kubernetes.io/name: "deepgram-aiworks"
helm.sh/chart: {{ include "deepgram-aiworks.chart" . }}
{{ include "deepgram-aiworks.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: deepgram
{{- end -}}

{{/*
Selector labels — applied to pods. Must remain stable across upgrades or
the Deployment selector breaks.
*/}}
{{- define "deepgram-aiworks.selectorLabels" -}}
app.kubernetes.io/name: "deepgram-aiworks"
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the secret that holds DEEPGRAM_API_KEY and VW_API_KEY. Uses an
existing Secret if .Values.secrets.existingSecret is set; otherwise the
chart creates one named "<fullname>-credentials".
*/}}
{{- define "deepgram-aiworks.credentialsSecretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- printf "%s-credentials" (include "deepgram-aiworks.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Name of the TLS Secret. Uses an existing kubernetes.io/tls Secret if set;
otherwise the chart creates one. When server.tls.enabled=false, neither
the existingSecret nor the inline cert/key matter.
*/}}
{{- define "deepgram-aiworks.tlsSecretName" -}}
{{- if .Values.server.tls.existingSecret -}}
{{- .Values.server.tls.existingSecret -}}
{{- else -}}
{{- printf "%s-tls" (include "deepgram-aiworks.fullname" .) -}}
{{- end -}}
{{- end -}}
