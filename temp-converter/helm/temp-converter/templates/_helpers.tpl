{{- define "temp-converter.name" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "temp-converter.tag" -}}
{{- required "image.tag is required, pass --set image.tag=<git sha>" .Values.image.tag -}}
{{- end -}}

{{- define "temp-converter.labels" -}}
app.kubernetes.io/name: temp-converter
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ include "temp-converter.tag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "temp-converter.selector" -}}
app.kubernetes.io/name: temp-converter
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
