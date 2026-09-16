{{- define "poc-app.name" -}}poc-app{{- end }}
{{- define "poc-app.fullname" -}}{{ .Release.Name }}{{- end }}
{{- define "poc-app.labels" -}}
app.kubernetes.io/name: {{ include "poc-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
