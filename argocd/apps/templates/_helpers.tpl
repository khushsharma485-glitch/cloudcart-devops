{{/* Common Application boilerplate. */}}
{{- define "apps.meta" -}}
namespace: argocd
labels:
  app.kubernetes.io/part-of: cloudcart
  cloudcart.io/environment: {{ .Values.environment }}
finalizers:
  # Deleting the Application also deletes what it deployed.
  - resources-finalizer.argocd.argoproj.io
{{- end -}}

{{- define "apps.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true     # remove objects deleted from Git
    selfHeal: true  # revert manual kubectl changes (drift)
  retry:
    limit: 5
    backoff:
      duration: 10s
      factor: 2
      maxDuration: 3m
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
{{- end -}}
