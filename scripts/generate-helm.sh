#!/bin/bash

# 设置变量
CHART_NAME="helloworld-rollup"
CHART_PATH="./helm-charts/${CHART_NAME}"

# 创建必要的目录
mkdir -p ${CHART_PATH}/templates

# 创建基础 chart（这会自动创建所有必要文件，包括 _helpers.tpl）
helm create ${CHART_PATH}

# 清理默认的 nginx 相关配置，但保留 _helpers.tpl
rm -f ${CHART_PATH}/templates/deployment.yaml
rm -f ${CHART_PATH}/templates/service.yaml
rm -f ${CHART_PATH}/templates/serviceaccount.yaml
rm -f ${CHART_PATH}/templates/hpa.yaml
rm -f ${CHART_PATH}/templates/ingress.yaml
rm -f ${CHART_PATH}/templates/NOTES.txt
rm -f ${CHART_PATH}/values.yaml

# 创建 PVC 模板
cat > ${CHART_PATH}/templates/mongodb-pvc.yaml << EOL
{{- if and .Values.config.mongodb.enabled .Values.config.mongodb.persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-mongodb-pvc
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.config.mongodb.persistence.size }}
  storageClassName: {{ .Values.config.mongodb.persistence.storageClassName }}
{{- end }}
EOL

# 生成新的 values.yaml
cat > ${CHART_PATH}/values.yaml << EOL
# Default values for ${CHART_NAME}
replicaCount: 1

image:
  repository: ghcr.io/jupiterxiaoxiaoyu/helloworld-rollup
  pullPolicy: IfNotPresent
  tag: "latest"  # 可以是 latest 或 MD5 值

# 应用配置
config:
  mongodb:
    enabled: true
    image:
      repository: mongo
      tag: latest
    port: 27017
    persistence:
      enabled: true
      storageClassName: csi-disk  
      size: 10Gi
  redis:
    enabled: true
    image:
      repository: redis
      tag: latest
    port: 6379
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
  merkle:
    enabled: true
    image:
      repository: sinka2022/zkwasm-merkleservice
      tag: latest
    port: 3030

service:
  type: ClusterIP
  port: 3000

# 初始化容器配置
initContainer:
  enabled: true
  image: node:18-slim

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 128Mi

nodeSelector: {}
tolerations: []
affinity: {}
EOL

# 生成 deployment.yaml
cat > ${CHART_PATH}/templates/deployment.yaml << EOL
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "${CHART_NAME}.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "${CHART_NAME}.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: app
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        command: ["node"]
        args: ["--experimental-modules", "ts/src/service.js"]
        env:
        - name: URI
          value: mongodb://{{ include "${CHART_NAME}.fullname" . }}-mongodb:{{ .Values.config.mongodb.port }}
        - name: REDISHOST
          value: {{ include "${CHART_NAME}.fullname" . }}-redis
        - name: MERKLE_SERVER
          value: http://{{ include "${CHART_NAME}.fullname" . }}-merkle:{{ .Values.config.merkle.port }}
        ports:
        - containerPort: 3000
          name: http
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 15
          periodSeconds: 20
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
EOL

# 生成 service.yaml
cat > ${CHART_PATH}/templates/service.yaml << EOL
apiVersion: v1
kind: Service
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "${CHART_NAME}.selectorLabels" . | nindent 4 }}
EOL

# 生成 NOTES.txt
cat > ${CHART_PATH}/templates/NOTES.txt << EOL
1. Get the application URL by running these commands:
{{- if contains "NodePort" .Values.service.type }}
  export NODE_PORT=\$(kubectl get --namespace {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}" services {{ include "${CHART_NAME}.fullname" . }})
  export NODE_IP=\$(kubectl get nodes --namespace {{ .Release.Namespace }} -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://\$NODE_IP:\$NODE_PORT
{{- else if contains "LoadBalancer" .Values.service.type }}
  NOTE: It may take a few minutes for the LoadBalancer IP to be available.
        You can watch the status of by running 'kubectl get --namespace {{ .Release.Namespace }} svc -w {{ include "${CHART_NAME}.fullname" . }}'
  export SERVICE_IP=\$(kubectl get svc --namespace {{ .Release.Namespace }} {{ include "${CHART_NAME}.fullname" . }} --template "{{"{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}"}}")
  echo http://\$SERVICE_IP:{{ .Values.service.port }}
{{- else if contains "ClusterIP" .Values.service.type }}
  export POD_NAME=\$(kubectl get pods --namespace {{ .Release.Namespace }} -l "app.kubernetes.io/name={{ include "${CHART_NAME}.name" . }},app.kubernetes.io/instance={{ .Release.Name }}" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=\$(kubectl get pod --namespace {{ .Release.Namespace }} \$POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace {{ .Release.Namespace }} port-forward \$POD_NAME 8080:\$CONTAINER_PORT
{{- end }}
EOL

# 更新 Chart.yaml
cat > ${CHART_PATH}/Chart.yaml << EOL
apiVersion: v2
name: ${CHART_NAME}
description: A Helm chart for HelloWorld Rollup service
type: application
version: 0.1.0
appVersion: "1.0.0"
EOL

# 生成 .helmignore
cat > ${CHART_PATH}/.helmignore << EOL
# Patterns to ignore when building packages.
*.tgz
.git
.gitignore
.idea/
*.tmproj
.vscode/
EOL

# 生成 mongodb-deployment.yaml
cat > ${CHART_PATH}/templates/mongodb-deployment.yaml << EOL
{{- if .Values.config.mongodb.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-mongodb
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      app: {{ include "${CHART_NAME}.fullname" . }}-mongodb
  template:
    metadata:
      labels:
        app: {{ include "${CHART_NAME}.fullname" . }}-mongodb
    spec:
      containers:
      - name: mongodb
        image: "{{ .Values.config.mongodb.image.repository }}:{{ .Values.config.mongodb.image.tag }}"
        ports:
        - containerPort: {{ .Values.config.mongodb.port }}
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
      volumes:
      - name: mongodb-data
        persistentVolumeClaim:
          claimName: {{ include "${CHART_NAME}.fullname" . }}-mongodb-pvc
{{- end }}
EOL

# 生成 redis-deployment.yaml
cat > ${CHART_PATH}/templates/redis-deployment.yaml << EOL
{{- if .Values.config.redis.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-redis
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      app: {{ include "${CHART_NAME}.fullname" . }}-redis
  template:
    metadata:
      labels:
        app: {{ include "${CHART_NAME}.fullname" . }}-redis
    spec:
      containers:
      - name: redis
        image: "{{ .Values.config.redis.image.repository }}:{{ .Values.config.redis.image.tag }}"
        ports:
        - containerPort: {{ .Values.config.redis.port }}
        resources:
          {{- toYaml .Values.config.redis.resources | nindent 10 }}
{{- end }}
EOL

# 生成 merkle-deployment.yaml
cat > ${CHART_PATH}/templates/merkle-deployment.yaml << EOL
{{- if .Values.config.merkle.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-merkle
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      app: {{ include "${CHART_NAME}.fullname" . }}-merkle
  template:
    metadata:
      labels:
        app: {{ include "${CHART_NAME}.fullname" . }}-merkle
    spec:
      containers:
      - name: merkle
        image: "{{ .Values.config.merkle.image.repository }}:{{ .Values.config.merkle.image.tag }}"
        command: ["./target/release/csm_service"]
        args: ["--uri", "mongodb://{{ include "${CHART_NAME}.fullname" . }}-mongodb:{{ .Values.config.mongodb.port }}"]
        ports:
        - containerPort: {{ .Values.config.merkle.port }}
        env:
        - name: URI
          value: mongodb://{{ include "${CHART_NAME}.fullname" . }}-mongodb:{{ .Values.config.mongodb.port }}
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
{{- end }}
EOL

# 生成 mongodb-pvc.yaml
cat > ${CHART_PATH}/templates/mongodb-pvc.yaml << EOL
{{- if and .Values.config.mongodb.enabled .Values.config.mongodb.persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-mongodb-pvc
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.config.mongodb.persistence.size }}
  storageClassName: {{ .Values.config.mongodb.persistence.storageClassName }}
{{- end }}
EOL

# 生成 mongodb-service.yaml
cat > ${CHART_PATH}/templates/mongodb-service.yaml << EOL
apiVersion: v1
kind: Service
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-mongodb
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  ports:
    - port: {{ .Values.config.mongodb.port }}
      targetPort: {{ .Values.config.mongodb.port }}
      protocol: TCP
      name: mongodb
  selector:
    app: {{ include "${CHART_NAME}.fullname" . }}-mongodb
EOL

# 生成 merkle-service.yaml
cat > ${CHART_PATH}/templates/merkle-service.yaml << EOL
apiVersion: v1
kind: Service
metadata:
  name: {{ include "${CHART_NAME}.fullname" . }}-merkle
  labels:
    {{- include "${CHART_NAME}.labels" . | nindent 4 }}
spec:
  ports:
    - port: {{ .Values.config.merkle.port }}
      targetPort: {{ .Values.config.merkle.port }}
      protocol: TCP
      name: http
  selector:
    app: {{ include "${CHART_NAME}.fullname" . }}-merkle
EOL

# 使脚本可执行
chmod +x scripts/generate-helm.sh

echo "Helm chart generated successfully at ${CHART_PATH}" 