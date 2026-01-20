# SRE Portfolio - 環境構築・デプロイ手順書

本手順書では、AWS EKS上にタスク管理アプリケーションをデプロイするまでの全工程を説明します。

---

## Quick Start

以下のコマンドを順番に実行することで、検証環境を構築できます。

### 前提条件
- AWS CLI, Terraform, kubectl, Docker, Helm がインストール済み
- AWS 認証情報が設定済み (`aws configure`)

### Step 1: Terraform でインフラ構築

```bash
# 1-1. 作業ディレクトリに移動
cd environments/dev

# 1-2. Terraform 初期化
terraform init

# 1-3. インフラ作成（約20-30分）
terraform apply -var="alert_email=your-email@example.com" -auto-approve

# 1-4. kubeconfig 設定
aws eks update-kubeconfig --name sre-portfolio-cluster --region ap-northeast-1

# 1-5. 接続確認
kubectl get nodes
```

### Step 2: コンテナイメージのビルド・プッシュ

```bash
# 2-1. 環境変数設定
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 2-2. ECR ログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com

# 2-3. プロジェクトルートに移動
cd ../..

# 2-4. API イメージのビルド・プッシュ
docker buildx build --platform linux/amd64 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest \
  --push ./apps/api

# 2-5. Frontend イメージのビルド・プッシュ
docker buildx build --platform linux/amd64 \
  --build-arg VITE_API_URL=/api \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest \
  --push ./apps/frontend
```

### Step 3: Kubernetes Secrets/ConfigMap 作成

```bash
# 3-1. RDS 認証情報の取得
RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw rds_secret_arn) \
  --query SecretString --output text)

export DB_HOST=$(echo $RDS_SECRET | jq -r '.host')
export DB_PORT=$(echo $RDS_SECRET | jq -r '.port')
export DB_USER=$(echo $RDS_SECRET | jq -r '.username')
export DB_PASSWORD=$(echo $RDS_SECRET | jq -r '.password')

# 3-2. Redis 認証情報の取得
export REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw redis_secret_arn) \
  --query SecretString --output text | jq -r '.auth_token')
export REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)

# 3-3. Namespace 作成
kubectl apply -f k8s/base/namespace.yaml

# 3-4. Secrets 作成
kubectl create secret generic db-credentials \
  --namespace app-production \
  --from-literal=host=${DB_HOST} \
  --from-literal=port=${DB_PORT} \
  --from-literal=dbname=taskmanager \
  --from-literal=username=${DB_USER} \
  --from-literal=password=${DB_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic redis-credentials \
  --namespace app-production \
  --from-literal=auth_token=${REDIS_AUTH_TOKEN} \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic jwt-secret \
  --namespace app-production \
  --from-literal=secret=$(openssl rand -base64 32) \
  --dry-run=client -o yaml | kubectl apply -f -

# 3-5. ConfigMap 作成
kubectl create configmap api-config \
  --namespace app-production \
  --from-literal=REDIS_HOST=${REDIS_HOST} \
  --from-literal=REDIS_PORT=6379 \
  --from-literal=LOG_LEVEL=info \
  --from-literal=CORS_ALLOWED_ORIGINS="*" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 4: マニフェスト編集・デプロイ

```bash
# 4-1. イメージ URL を更新（sed で置換）
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/frontend/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/serviceaccount.yaml

# 4-2. アプリケーションデプロイ
kubectl apply -f k8s/base/api/
kubectl apply -f k8s/base/frontend/
kubectl apply -f k8s/base/ingress.yaml

# 4-3. デプロイ確認
kubectl get pods -n app-production -w
```

### Step 5: データベースマイグレーション

```bash
# 5-1. マイグレーション SQL を ConfigMap として作成
kubectl create configmap migration-sql \
  --namespace=app-production \
  --from-file=apps/api/migrations/000001_create_users.up.sql \
  --from-file=apps/api/migrations/000002_create_tasks.up.sql

# 5-2. マイグレーション実行 Pod を作成
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: psql-migration
  namespace: app-production
spec:
  restartPolicy: Never
  containers:
  - name: psql
    image: postgres:15-alpine
    command: ["/bin/sh", "-c"]
    args:
      - |
        psql -h "$DB_HOST" -U "$DB_USER" -d taskmanager -f /migrations/000001_create_users.up.sql
        psql -h "$DB_HOST" -U "$DB_USER" -d taskmanager -f /migrations/000002_create_tasks.up.sql
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: host
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: username
    volumeMounts:
    - name: migrations
      mountPath: /migrations
  volumes:
  - name: migrations
    configMap:
      name: migration-sql
EOF

# 5-3. 完了待機・ログ確認・クリーンアップ
sleep 15 && kubectl logs psql-migration -n app-production
kubectl delete pod psql-migration -n app-production
kubectl delete configmap migration-sql -n app-production
```

### Step 6: 動作確認

```bash
# 6-1. ALB DNS 取得
export ALB_DNS=$(kubectl get ingress -n app-production app-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://${ALB_DNS}"

# 6-2. ヘルスチェック
curl http://${ALB_DNS}/health/live

# 6-3. ユーザー登録
curl -X POST http://${ALB_DNS}/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com","password":"Password123!"}'

# 6-4. ブラウザでアクセス
open http://${ALB_DNS}
```

---

## 目次（詳細）

1. [前提条件](#1-前提条件)
2. [ローカル開発環境の構築](#2-ローカル開発環境の構築)
3. [AWSインフラストラクチャの構築](#3-awsインフラストラクチャの構築)
4. [コンテナイメージのビルドとプッシュ](#4-コンテナイメージのビルドとプッシュ)
5. [Kubernetesへのデプロイ](#5-kubernetesへのデプロイ)
6. [動作確認](#6-動作確認)
7. [トラブルシューティング](#7-トラブルシューティング)

---

## 1. 前提条件

### 1.1 必要なツール

| ツール | バージョン | 用途 |
|--------|-----------|------|
| AWS CLI | v2.x | AWS リソースの操作 |
| Terraform | v1.5+ | Infrastructure as Code |
| kubectl | v1.28+ | Kubernetes クラスタ操作 |
| Docker | v24+ | コンテナイメージのビルド |
| Helm | v3.x | Kubernetes パッケージ管理 |
| Go | v1.22+ | API アプリケーション開発 |
| Node.js | v20+ | フロントエンド開発 |

```bash
# インストール確認
aws --version && terraform --version && kubectl version --client && docker --version && helm version
```

### 1.2 AWS 認証情報の設定

```bash
aws configure
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region name: ap-northeast-1
# - Default output format: json

# 認証確認
aws sts get-caller-identity
```

---

## 2. ローカル開発環境の構築

AWS リソースを作成する前に、ローカルで動作確認ができます。

```bash
# 起動
docker-compose up --build

# 確認
curl http://localhost:8080/health/live
open http://localhost:3000

# 停止
docker-compose down -v
```

| サービス | ポート | 説明 |
|---------|--------|------|
| api | 8080 | Go API サーバー |
| frontend | 3000 | React フロントエンド |
| postgres | 5432 | PostgreSQL |
| redis | 6379 | Redis |

---

## 3. AWSインフラストラクチャの構築

### 3.1 アーキテクチャ

```
                    ┌──────────────────────────────────────────────────────┐
                    │                   VPC (10.0.0.0/16)                  │
                    │  ┌────────────────────────────────────────────────┐  │
                    │  │         Public Subnets (3 AZs) - ALB, NAT      │  │
                    │  └────────────────────────────────────────────────┘  │
Internet ──► ALB ──►│  ┌────────────────────────────────────────────────┐  │
                    │  │    Private EKS Subnets - API/Frontend Pods     │  │
                    │  └────────────────────────────────────────────────┘  │
                    │  ┌────────────────────────────────────────────────┐  │
                    │  │   Private Data Subnets - RDS, ElastiCache      │  │
                    │  └────────────────────────────────────────────────┘  │
                    └──────────────────────────────────────────────────────┘
```

### 3.2 Terraform 実行

```bash
cd environments/dev
terraform init
terraform validate
terraform plan -var="alert_email=your-email@example.com"
terraform apply -var="alert_email=your-email@example.com" -auto-approve
```

**所要時間:** 約 20-30 分

### 3.3 リソース競合エラー時の対処

以前に `terraform destroy` を実行した環境を再作成する場合：

```bash
# Secrets Manager の削除待機中シークレットを即座に削除
aws secretsmanager delete-secret --secret-id "sre-portfolio/rds/credentials" --force-delete-without-recovery --region ap-northeast-1
aws secretsmanager delete-secret --secret-id "sre-portfolio/redis/auth-token" --force-delete-without-recovery --region ap-northeast-1

# CloudWatch Log Group を削除
aws logs delete-log-group --log-group-name "/aws/eks/sre-portfolio-cluster/cluster" --region ap-northeast-1

# 再度 apply
terraform apply -var="alert_email=your-email@example.com"
```

### 3.4 出力値の確認

```bash
terraform output
```

### 3.5 kubectl の設定

```bash
aws eks update-kubeconfig --name sre-portfolio-cluster --region ap-northeast-1
kubectl cluster-info
kubectl get nodes
```

---

## 4. コンテナイメージのビルドとプッシュ

> **M1/M2 Mac 使用時:** 必ず `--platform linux/amd64` を指定してください。

```bash
# 環境変数
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ECR ログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com

# API イメージ
docker buildx build --platform linux/amd64 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest \
  --push ./apps/api

# Frontend イメージ
docker buildx build --platform linux/amd64 \
  --build-arg VITE_API_URL=/api \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest \
  --push ./apps/frontend

# 確認
aws ecr list-images --repository-name sre-portfolio/api
aws ecr list-images --repository-name sre-portfolio/frontend
```

---

## 5. Kubernetesへのデプロイ

### 5.1 Secrets/ConfigMap の作成

```bash
# RDS 認証情報取得
RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw rds_secret_arn) \
  --query SecretString --output text)
export DB_HOST=$(echo $RDS_SECRET | jq -r '.host')
export DB_PORT=$(echo $RDS_SECRET | jq -r '.port')
export DB_USER=$(echo $RDS_SECRET | jq -r '.username')
export DB_PASSWORD=$(echo $RDS_SECRET | jq -r '.password')

# Redis 認証情報取得
export REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw redis_secret_arn) \
  --query SecretString --output text | jq -r '.auth_token')
export REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)

# Namespace
kubectl apply -f k8s/base/namespace.yaml

# Secrets
kubectl create secret generic db-credentials --namespace app-production \
  --from-literal=host=${DB_HOST} --from-literal=port=${DB_PORT} \
  --from-literal=dbname=taskmanager --from-literal=username=${DB_USER} \
  --from-literal=password=${DB_PASSWORD} --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic redis-credentials --namespace app-production \
  --from-literal=auth_token=${REDIS_AUTH_TOKEN} --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic jwt-secret --namespace app-production \
  --from-literal=secret=$(openssl rand -base64 32) --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap
kubectl create configmap api-config --namespace app-production \
  --from-literal=REDIS_HOST=${REDIS_HOST} --from-literal=REDIS_PORT=6379 \
  --from-literal=LOG_LEVEL=info --from-literal=CORS_ALLOWED_ORIGINS="*" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5.2 マニフェストの編集

```bash
# AWS_ACCOUNT_ID を置換
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/frontend/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/serviceaccount.yaml
```

### 5.3 デプロイ

```bash
kubectl apply -f k8s/base/api/
kubectl apply -f k8s/base/frontend/
kubectl apply -f k8s/base/ingress.yaml
kubectl get pods -n app-production -w
```

### 5.4 データベースマイグレーション

```bash
# ConfigMap 作成
kubectl create configmap migration-sql --namespace=app-production \
  --from-file=apps/api/migrations/000001_create_users.up.sql \
  --from-file=apps/api/migrations/000002_create_tasks.up.sql

# マイグレーション実行
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: psql-migration
  namespace: app-production
spec:
  restartPolicy: Never
  containers:
  - name: psql
    image: postgres:15-alpine
    command: ["/bin/sh", "-c"]
    args:
      - |
        psql -h "$DB_HOST" -U "$DB_USER" -d taskmanager -f /migrations/000001_create_users.up.sql
        psql -h "$DB_HOST" -U "$DB_USER" -d taskmanager -f /migrations/000002_create_tasks.up.sql
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: host
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: username
    volumeMounts:
    - name: migrations
      mountPath: /migrations
  volumes:
  - name: migrations
    configMap:
      name: migration-sql
EOF

# 完了待機・クリーンアップ
sleep 15 && kubectl logs psql-migration -n app-production
kubectl delete pod psql-migration -n app-production
kubectl delete configmap migration-sql -n app-production
```

---

## 6. 動作確認

```bash
# ALB DNS 取得
export ALB_DNS=$(kubectl get ingress -n app-production app-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://${ALB_DNS}"

# ヘルスチェック
curl http://${ALB_DNS}/health/live

# ユーザー登録
curl -X POST http://${ALB_DNS}/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com","password":"Password123!"}'

# ログイン
curl -X POST http://${ALB_DNS}/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"Password123!"}'

# ブラウザでアクセス
open http://${ALB_DNS}
```

**ログイン情報:**
- ユーザー名: `testuser`
- パスワード: `Password123!`

---

## 7. トラブルシューティング

### 7.1 ImagePullBackOff エラー

```bash
kubectl describe pod -n app-production -l app=api-service
```

| 原因 | 対処 |
|------|------|
| アーキテクチャ不一致 | `--platform linux/amd64` で再ビルド |
| ECR 認証切れ | `aws ecr get-login-password` で再ログイン |
| イメージが存在しない | `aws ecr list-images` で確認 |

### 7.2 CrashLoopBackOff エラー

```bash
kubectl logs -n app-production -l app=api-service --tail=50
```

| エラー | 対処 |
|--------|------|
| `lookup REDIS_ENDPOINT_HERE: no such host` | ConfigMap の REDIS_HOST を正しく設定 |
| `dial tcp: i/o timeout` | Redis TLS/AUTH Token 設定を確認 |

### 7.3 ALB が作成されない

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl describe ingress -n app-production app-ingress
```

### 7.4 Pod の状態確認

```bash
kubectl get events -n app-production --sort-by='.lastTimestamp'
kubectl top nodes
kubectl top pods -n app-production
```

---

## 付録

### A. 環境削除

> **重要:** 削除順序を守らないと、AWS リソース（NLB, ENI）が残留し、手動クリーンアップが必要になります。

```bash
# 1. 監視基盤の削除（Helm リリース）
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall fluent-bit -n monitoring

# 2. アプリケーションリソースの削除
kubectl delete -f k8s/base/

# 3. Namespace の削除
kubectl delete ns app-production
kubectl delete ns monitoring

# 4. ALB/NLB が完全に削除されるまで待機（1-2分）
echo "Waiting for AWS resources cleanup..."
sleep 60

# 5. Terraform リソース削除
cd environments/dev
terraform destroy -var="alert_email=your-email@example.com"
```

**削除順序の理由:**
- Grafana の NLB が残った状態で VPC を削除しようとすると失敗する
- Ingress (ALB) を先に削除しないとサブネット削除が失敗する

### B. API エンドポイント一覧

| メソッド | エンドポイント | 説明 | 認証 |
|---------|---------------|------|------|
| POST | `/api/v1/auth/register` | ユーザー登録 | 不要 |
| POST | `/api/v1/auth/login` | ログイン | 不要 |
| GET | `/api/v1/tasks` | タスク一覧 | 必要 |
| POST | `/api/v1/tasks` | タスク作成 | 必要 |
| PUT | `/api/v1/tasks/:id` | タスク更新 | 必要 |
| DELETE | `/api/v1/tasks/:id` | タスク削除 | 必要 |
