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
Render the --log-format flag for a component, or an empty string if unset.
Callers must place the result ahead of the subcommand: the Deepgram binaries
expose --log-format only as a top-level option, and reject it after `serve`.
Takes a dict of "key" (values path, for the error message), "value", and the
component's "extraEnv", which is checked for the legacy JSON=true variable:
the containers panic when it is combined with any format other than json.
*/}}
{{- define "deepgram-self-hosted.logFormatArg" -}}
{{- with .value -}}
{{- if not (has . (list "full" "compact" "pretty" "json")) -}}
{{- fail (printf "Error: %s must be one of full, compact, pretty, json (got %q)" $.key .) -}}
{{- end -}}
{{- if ne . "json" -}}
{{- $envKey := printf "%s.extraEnv" (trimSuffix ".logFormat" $.key) -}}
{{- range $.extraEnv -}}
{{- if and (eq (toString (.name | default "")) "JSON") (eq (lower (toString (.value | default ""))) "true") -}}
{{- fail (printf "Error: %s is %q, but %s sets JSON=true, which forces JSON output. The container panics when both are set. Remove the JSON variable, or set %s to json." $.key $.value $envKey $.key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- printf "--log-format=%s" . -}}
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
