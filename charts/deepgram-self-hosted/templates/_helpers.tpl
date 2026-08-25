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
Reject FIPS mode unless every deployed component runs a FIPS image. Standard
images are not built for FIPS: depending on the base OS, one either aborts at
startup ("Failed to load FIPS provider", exit 101) or starts and reports
openssl_fips_enabled=true without providing FIPS-validated crypto. Tags that are
not official Deepgram release tags are left alone, since a private registry may
use its own naming.
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
{{- fail (printf "Error: global.fips.enabled is true but %s.image.tag is \"%s\", which predates the FIPS image variants. Those start at release-260728. Use a `-fips` tag from release-260728 or later, or disable global.fips.enabled." $component.value $tag) -}}
{{- end -}}
{{- if not (hasSuffix "-fips" $tag) -}}
{{- fail (printf "Error: global.fips.enabled is true but %s.image.tag is \"%s\", which is a standard image. Standard images are not built for FIPS: depending on the base OS, one either aborts at startup (\"Failed to load FIPS provider\", exit 101) or starts and reports openssl_fips_enabled=true without providing FIPS-validated crypto. Use \"%s-fips\", or disable global.fips.enabled." $component.value $tag $tag) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
