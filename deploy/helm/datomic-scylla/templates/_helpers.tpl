{{- define "datomic-scylla.fullname" -}}{{ .Release.Name }}-{{ .Chart.Name }}{{- end -}}
{{- define "datomic-scylla.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "datomic-scylla.secretName" -}}
{{- if .Values.secrets.existingSecret -}}{{ .Values.secrets.existingSecret }}{{- else -}}{{ include "datomic-scylla.fullname" . }}-secrets{{- end -}}
{{- end -}}
{{/* In-cluster CQL Service DNS the Operator creates for the datacenter's clients */}}
{{- define "datomic-scylla.scyllaCqlHost" -}}{{ .Values.scylla.clusterName }}-client.{{ .Values.namespace }}.svc{{- end -}}
