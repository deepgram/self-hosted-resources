{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "deepgram-self-hosted.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "deepgram-self-hosted.labels" -}}
app.kubernetes.io/name: "deepgram-self-hosted"
helm.sh/chart: {{ include "deepgram-self-hosted.chart" . }}
{{ include "deepgram-self-hosted.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $val := .Values.global.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end}}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "deepgram-self-hosted.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Reject FIPS mode on image tags that predate FIPS support. Those images have no
OpenSSL FIPS provider, so the service aborts at startup ("Failed to load FIPS
provider", exit 101) and crash-loops. Tags that are not official Deepgram
release tags are left alone, since a private registry may use its own naming.
*/}}
{{- define "deepgram-self-hosted.validateFipsImageTags" -}}
{{- if (.Values.global.fips).enabled -}}
{{- $components := list (dict "value" "api" "tag" .Values.api.image.tag) (dict "value" "engine" "tag" .Values.engine.image.tag) -}}
{{- if .Values.licenseProxy.enabled -}}
{{- $components = append $components (dict "value" "licenseProxy" "tag" .Values.licenseProxy.image.tag) -}}
{{- end -}}
{{- if .Values.billing.enabled -}}
{{- $components = append $components (dict "value" "billing" "tag" .Values.billing.image.tag) -}}
{{- end -}}
{{- range $component := $components -}}
{{- $tag := toString $component.tag -}}
{{- if regexMatch "^release-[0-9]{6}(-fips)?$" $tag -}}
{{- if lt (atoi (regexFind "[0-9]{6}" $tag)) 260728 -}}
{{- fail (printf "Error: global.fips.enabled is true but %s.image.tag is \"%s\", which predates FIPS support. That image has no OpenSSL FIPS provider, so the service aborts at startup and crash-loops. Use a `-fips` tag from release-260728 or later, or disable global.fips.enabled." $component.value $tag) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
