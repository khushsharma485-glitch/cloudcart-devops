{{/*
Merged settings for one service: serviceDefaults overlaid with the
service's own block. Usage: include "cloudcart.svc" (dict "root" $ "name" $name)
returns YAML; callers use fromYaml.
*/}}
{{- define "cloudcart.svc" -}}
{{- $own := index .root.Values.services .name | default dict -}}
{{- $merged := mergeOverwrite (deepCopy .root.Values.serviceDefaults) (deepCopy $own) -}}
{{- toYaml $merged -}}
{{- end -}}

{{- define "cloudcart.labels" -}}
app.kubernetes.io/part-of: cloudcart
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
cloudcart.io/environment: {{ .root.Values.global.environment }}
{{- if .name }}
{{ include "cloudcart.selectorLabels" . }}
{{- end }}
{{- end -}}

{{- define "cloudcart.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
{{- end -}}

{{/* Full image reference: [registry/]prefix/name:tag */}}
{{- define "cloudcart.image" -}}
{{- $img := .root.Values.global.image -}}
{{- $svc := .svc -}}
{{- $tag := default $img.tag (dig "image" "tag" "" $svc) -}}
{{- if not $tag -}}
{{- fail (printf "No image tag for %s: set global.image.tag or services.%s.image.tag" .name .name) -}}
{{- end -}}
{{- $repo := printf "%s/%s" $img.repositoryPrefix .name -}}
{{- if $img.registry -}}
{{- printf "%s/%s:%s" $img.registry $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{/*
Pod template shared by Deployment and Rollout.
Args: dict "root" $ "name" $name "svc" $svc
*/}}
{{- define "cloudcart.podTemplate" -}}
{{- $root := .root -}}
{{- $svc := .svc -}}
metadata:
  labels:
    {{- include "cloudcart.labels" . | nindent 4 }}
    cloudcart.io/tier: backend
  annotations:
    # Roll pods when the ConfigMap content changes.
    checksum/config: {{ include (print $root.Template.BasePath "/configmap.yaml") $root | sha256sum }}
spec:
  serviceAccountName: {{ .name }}
  automountServiceAccountToken: false
  terminationGracePeriodSeconds: 30
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          {{- include "cloudcart.selectorLabels" . | nindent 10 }}
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          {{- include "cloudcart.selectorLabels" . | nindent 10 }}
  containers:
    - name: app
      image: {{ include "cloudcart.image" . }}
      imagePullPolicy: {{ $root.Values.global.image.pullPolicy }}
      ports:
        - name: http
          containerPort: 8080
      envFrom:
        - configMapRef:
            name: cloudcart-config
      env:
        - name: APP_VERSION
          value: {{ include "cloudcart.image" . | splitList ":" | last | quote }}
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: {{ $root.Values.database.secretName }}
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ $root.Values.database.secretName }}
              key: password
        {{- range $k, $v := $svc.extraEnv }}
        - name: {{ $k }}
          value: {{ $v | quote }}
        {{- end }}
      resources:
        {{- toYaml $svc.resources | nindent 8 }}
      startupProbe:
        httpGet:
          path: /actuator/health/liveness
          port: http
        periodSeconds: {{ $svc.probes.startup.periodSeconds }}
        failureThreshold: {{ $svc.probes.startup.failureThreshold }}
      readinessProbe:
        httpGet:
          path: /actuator/health/readiness
          port: http
        periodSeconds: {{ $svc.probes.readiness.periodSeconds }}
        timeoutSeconds: {{ $svc.probes.readiness.timeoutSeconds }}
        failureThreshold: {{ $svc.probes.readiness.failureThreshold }}
      livenessProbe:
        httpGet:
          path: /actuator/health/liveness
          port: http
        periodSeconds: {{ $svc.probes.liveness.periodSeconds }}
        timeoutSeconds: {{ $svc.probes.liveness.timeoutSeconds }}
        failureThreshold: {{ $svc.probes.liveness.failureThreshold }}
      lifecycle:
        preStop:
          sleep:
            seconds: 5
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir:
        sizeLimit: 64Mi
{{- end -}}
