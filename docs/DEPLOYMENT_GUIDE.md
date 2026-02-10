# SRE Portfolio - 検証環境（Dev）デプロイ手順書

本手順書では、AWS EKS 上に検証環境を構築・デプロイするための手順を説明します。
コマンドを上から順に実行していくことで、環境が構築されます。

---

## 目次（チェックリスト）

> 各ステップ完了時にチェックを入れてください。自動スクリプトを使用する場合: `bash scripts/deploy-dev.sh`

- [ ] [環境概要](#1-環境概要) を確認
- [ ] [前提条件](#2-前提条件) を確認
- [ ] [Step 1: Terraform でインフラ構築](#step-1-terraform-でインフラ構築)
- [ ] [Step 2: コンテナイメージのビルド・プッシュ](#step-2-コンテナイメージのビルドプッシュ)
- [ ] [Step 3: Kubernetes Secrets/ConfigMap 作成](#step-3-kubernetes-secretsconfigmap-作成)
- [ ] [Step 4: アプリケーションデプロイ](#step-4-アプリケーションデプロイ)
- [ ] [Step 5: データベースマイグレーション](#step-5-データベースマイグレーション)
- [ ] [Step 6: 動作確認](#step-6-動作確認)
- [ ] [Step 7: 監視設定](#step-7-監視設定)
- [ ] [運用手順](#8-運用手順) を確認
- [ ] [トラブルシューティング](#9-トラブルシューティング) を確認
- [ ] [環境削除手順](#10-環境削除手順) を確認

---

## 1. 環境概要

### 1.1 アーキテクチャ

```text
┌──────────────────────────────────────────────────────────────────────┐
│                          Dev Environment                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │
│  │   AZ-1a     │    │   AZ-1c     │    │   AZ-1d     │              │
│  │             │    │             │    │             │              │
│  │ ┌─────────┐ │    │             │    │             │              │
│  │ │   NAT   │ │    │             │    │             │  ← Single    │
│  │ └─────────┘ │    │             │    │             │    NAT GW    │
│  │             │    │             │    │             │              │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │              │
│  │ │EKS Node │ │    │ │EKS Node │ │    │ │EKS Node │ │  ← 2-6      │
│  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │    Nodes     │
│  │             │    │             │    │             │              │
│  │ ┌─────────┐ │    │             │    │             │              │
│  │ │   RDS   │ │    │             │    │             │  ← Single-AZ │
│  │ │ Primary │ │    │             │    │             │    RDS       │
│  │ └─────────┘ │    │             │    │             │              │
│  │             │    │             │    │             │              │
│  │ ┌─────────┐ │    │             │    │             │              │
│  │ │ Redis   │ │    │             │    │             │  ← Single    │
│  │ │ Primary │ │    │             │    │             │    Node      │
│  │ └─────────┘ │    │             │    │             │              │
│  └─────────────┘    └─────────────┘    └─────────────┘              │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                    ALB (Ingress Controller)                    │    │
│  │   /api, /health, /metrics → api-service                       │    │
│  │   / → frontend-service                                        │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.2 リソース構成

| コンポーネント | 構成 | 備考 |
|---------------|------|------|
| VPC | 10.0.0.0/16 | 3 AZ 構成 |
| NAT Gateway | 1 個 | コスト削減（Single NAT） |
| EKS Cluster | v1.32 | Managed Node Group |
| EKS Nodes | t3.medium × 3（2-6） | Auto Scaling |
| RDS PostgreSQL | db.t3.micro | Single-AZ、削除保護なし |
| ElastiCache Redis | cache.t3.micro × 1 | Single Node |
| CloudWatch | 7 日保持 | アラーム無効 |

### 1.3 本番環境との差分

| 項目 | 検証環境 (dev) | 本番環境 (prod) |
|------|---------------|-----------------|
| NAT Gateway | 1 個 | 3 個（高可用性） |
| EKS Nodes | 2-6 ノード | 3-10 ノード |
| RDS | Single-AZ、db.t3.micro | Multi-AZ、db.t3.small |
| RDS 削除保護 | 無効 | 有効 |
| Redis | 1 ノード | 3 ノード（Multi-AZ） |
| ログ保持 | 7 日 | 30 日 |
| CloudWatch Alarms | 無効 | 有効 |

---

## 2. 前提条件

### 2.1 必要なツール

```bash
# 各ツールのバージョンを確認
aws --version        # 2.x 以上
terraform --version  # 1.5.0 以上
kubectl version      # 1.28 以上
docker --version     # 20.x 以上
helm version         # 3.x 以上
jq --version         # 1.6 以上
```

### 2.2 AWS 認証

```bash
# AWS 認証情報が有効か確認
aws sts get-caller-identity

# 期待される出力:
# {
#     "UserId": "...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:..."
# }
```

> SSO を使用している場合は `aws sso login` で事前にログインしてください。

---

## Step 1: Terraform でインフラ構築

### 前提条件チェック

```bash
# AWS 認証が有効であることを確認（エラーが出る場合は aws sso login を実行）
aws sts get-caller-identity
```

### 1.1 作業ディレクトリに移動

```bash
# プロジェクトルートからの相対パスで移動
cd environments/dev
```

### 1.2 Terraform 初期化

```bash
# プロバイダーとモジュールをダウンロード
terraform init
```

期待される出力:

```text
Terraform has been successfully initialized!
```

### 1.3 リソース競合の確認（再作成時のみ）

以前に `terraform destroy` を実行した環境を再作成する場合、Secrets Manager のシークレットが削除待機中の場合があります。

```bash
# 削除待機中のシークレットを強制削除（初回構築時は不要）
aws secretsmanager delete-secret --secret-id "sre-portfolio/rds/credentials" --force-delete-without-recovery --region ap-northeast-1 2>/dev/null || true
aws secretsmanager delete-secret --secret-id "sre-portfolio/redis/auth-token" --force-delete-without-recovery --region ap-northeast-1 2>/dev/null || true

# 残存する CloudWatch Log Group を削除（初回構築時は不要）
aws logs delete-log-group --log-group-name "/aws/eks/sre-portfolio-cluster/cluster" --region ap-northeast-1 2>/dev/null || true
```

### 1.4 プラン確認

```bash
# 作成されるリソースを事前確認
terraform plan
```

### 1.5 インフラ構築

```bash
# リソースを作成（確認プロンプトで yes を入力）
terraform apply
```

> EKS クラスター作成に 15-20 分、RDS に 5-10 分かかります。

### 1.6 出力値の確認

```bash
# Terraform が作成したリソースの情報を確認
terraform output
```

### 1.7 kubeconfig 設定

```bash
# kubectl が EKS クラスターに接続できるよう設定
aws eks update-kubeconfig --name sre-portfolio-cluster --region ap-northeast-1

# クラスターへの接続を確認
kubectl get nodes

# 期待される出力（2-3 ノード）:
# NAME                                            STATUS   ROLES    AGE   VERSION
# ip-10-0-xx-xxx.ap-northeast-1.compute.internal  Ready    <none>   5m    v1.32.x
```

### Step 1 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
kubectl get nodes   # ノードが Ready 状態であること
terraform -chdir=environments/dev output cluster_name  # クラスター名が出力されること
```

> **チェック**: ノードが Ready になっていれば Step 1 完了です。目次のチェックボックスを更新してください。

---

## Step 2: コンテナイメージのビルド・プッシュ

### 前提条件チェック

```bash
# Step 1 完了確認: クラスターに接続できることを確認
kubectl get nodes
# → ノードが Ready 状態で表示されない場合、Step 1 に戻ってください
```

### 2.1 環境変数設定

```bash
# AWS アカウント ID を取得して環境変数に設定
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
```

### 2.2 ECR ログイン

```bash
# ECR に Docker 認証を行う（有効期限: 12 時間）
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
```

### 2.3 プロジェクトルートに移動

```bash
# アプリケーションのソースコードがあるルートディレクトリに移動
cd ../..
```

### 2.4 API イメージのビルド・プッシュ

> **M1/M2 Mac 使用時:** `--platform linux/amd64` を必ず指定してください。
> EKS ノードは amd64 アーキテクチャのため、arm64 イメージでは動作しません。

```bash
# Go API サーバーのコンテナイメージをビルドして ECR にプッシュ
docker buildx build --platform linux/amd64 -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest --push ./apps/api

# プッシュされたイメージを確認
aws ecr list-images --repository-name sre-portfolio/api --query 'imageIds[*].imageTag' --output table
```

### 2.5 Frontend イメージのビルド・プッシュ

> **M1/M2 Mac 使用時:** `--platform linux/amd64` を必ず指定してください。
> EKS ノードは amd64 アーキテクチャのため、arm64 イメージでは動作しません。

```bash
# React フロントエンドのコンテナイメージをビルドして ECR にプッシュ
# VITE_API_URL=/api で API のプロキシパスを設定
docker buildx build --platform linux/amd64 --build-arg VITE_API_URL=/api -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest --push ./apps/frontend

# プッシュされたイメージを確認
aws ecr list-images --repository-name sre-portfolio/frontend --query 'imageIds[*].imageTag' --output table
```

### Step 2 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
aws ecr list-images --repository-name sre-portfolio/api --query 'imageIds[*].imageTag' --output text
aws ecr list-images --repository-name sre-portfolio/frontend --query 'imageIds[*].imageTag' --output text
# → 両方に "latest" タグが表示されること
```

> **チェック**: 両リポジトリにイメージが存在すれば Step 2 完了です。

---

## Step 3: Kubernetes Secrets/ConfigMap 作成

### 前提条件チェック

```bash
# Step 2 完了確認: ECR にイメージが存在することを確認
aws ecr list-images --repository-name sre-portfolio/api --query 'imageIds[*].imageTag' --output text | grep -q "latest" && echo "OK: api image exists" || echo "ERROR: api image not found - Step 2 を実行してください"
aws ecr list-images --repository-name sre-portfolio/frontend --query 'imageIds[*].imageTag' --output text | grep -q "latest" && echo "OK: frontend image exists" || echo "ERROR: frontend image not found - Step 2 を実行してください"
```

### 3.1 認証情報の取得

```bash
# RDS の接続情報を Secrets Manager から取得
RDS_SECRET=$(aws secretsmanager get-secret-value --secret-id $(terraform -chdir=environments/dev output -raw rds_secret_arn) --query SecretString --output text)

# 取得した JSON から各フィールドを環境変数に設定
export DB_HOST=$(echo $RDS_SECRET | jq -r '.host')
export DB_PORT=$(echo $RDS_SECRET | jq -r '.port')
export DB_USER=$(echo $RDS_SECRET | jq -r '.username')
export DB_PASSWORD=$(echo $RDS_SECRET | jq -r '.password')

# Redis の認証トークンを Secrets Manager から取得
export REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value --secret-id $(terraform -chdir=environments/dev output -raw redis_secret_arn) --query SecretString --output text | jq -r '.auth_token')

# Redis エンドポイントを Terraform output から取得
export REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)

# 取得した値を確認（パスワードは表示しない）
echo "DB_HOST: ${DB_HOST}"
echo "DB_PORT: ${DB_PORT}"
echo "REDIS_HOST: ${REDIS_HOST}"
```

> DB_HOST や REDIS_HOST が空の場合、後続の手順で Pod がエラーになります。
> 必ず値が表示されていることを確認してください。

### 3.2 Namespace 作成

```bash
# アプリケーション用の namespace を作成
kubectl apply -f k8s/base/namespace.yaml

# namespace が作成されたことを確認
kubectl get namespace app-production
```

### 3.3 Secrets 作成

```bash
# RDS 接続用の Secret を作成（ユーザー名・パスワード・ホスト情報）
kubectl create secret generic db-credentials --namespace app-production --from-literal=host=${DB_HOST} --from-literal=port=${DB_PORT} --from-literal=dbname=taskmanager --from-literal=username=${DB_USER} --from-literal=password=${DB_PASSWORD} --dry-run=client -o yaml | kubectl apply -f -

# Redis 認証用の Secret を作成
kubectl create secret generic redis-credentials --namespace app-production --from-literal=auth_token=${REDIS_AUTH_TOKEN} --dry-run=client -o yaml | kubectl apply -f -

# JWT トークン署名用のシークレットを生成して Secret を作成
JWT_VALUE=$(openssl rand -base64 32 | tr -d '\n')
echo "Generated JWT: ${JWT_VALUE}"
kubectl create secret generic jwt-secret --namespace app-production --from-literal=secret="${JWT_VALUE}"

# 3 つの Secret が作成されたことを確認
kubectl get secrets -n app-production

# jwt-secret の値が空でないことを確認（重要）
kubectl get secret jwt-secret -n app-production -o jsonpath='{.data.secret}' | base64 -d && echo ""
```

> **注意**: jwt-secret の値が空の場合、Pod が `CrashLoopBackOff` になります。
> 値が表示されない場合は、Secret を削除して再作成してください。

### 3.4 ConfigMap 作成

```bash
# Redis エンドポイントが設定されていることを再確認
echo "REDIS_HOST: ${REDIS_HOST}"

# アプリケーション設定用の ConfigMap を作成
kubectl create configmap api-config --namespace app-production --from-literal=REDIS_HOST=${REDIS_HOST} --from-literal=REDIS_PORT=6379 --from-literal=LOG_LEVEL=info --from-literal=CORS_ALLOWED_ORIGINS="*" --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap の内容を確認（REDIS_HOST がプレースホルダーでないことを確認）
kubectl get configmap api-config -n app-production -o yaml
```

> REDIS_HOST が `REDIS_ENDPOINT_HERE` や空になっている場合、[トラブルシューティング 9.3](#93-redis-接続エラー) を参照してください。

### Step 3 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
echo "--- Secrets ---"
kubectl get secrets -n app-production
# → db-credentials, redis-credentials, jwt-secret の 3 つが存在すること

echo "--- ConfigMap ---"
kubectl get configmap api-config -n app-production -o jsonpath='{.data.REDIS_HOST}' && echo ""
# → Redis エンドポイントが表示されること（空やプレースホルダーでないこと）
```

> **チェック**: 3 つの Secret と ConfigMap が正しく設定されていれば Step 3 完了です。

---

## Step 4: アプリケーションデプロイ

### 前提条件チェック

```bash
# Step 3 完了確認: 必要な Secrets が存在することを確認
SECRET_COUNT=$(kubectl get secrets -n app-production --no-headers 2>/dev/null | grep -c -E "db-credentials|redis-credentials|jwt-secret")
if [ "$SECRET_COUNT" -ge 3 ]; then echo "OK: 3 Secrets found"; else echo "ERROR: Secrets が不足しています ($SECRET_COUNT/3) - Step 3 を実行してください"; fi
```

### 4.1 マニフェストの編集

```bash
# デプロイメント・ServiceAccount 内の AWS アカウント ID プレースホルダーを実際の値に置換
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/frontend/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/serviceaccount.yaml

# 置換結果を確認（image フィールドに正しい ECR URL が設定されていること）
grep "image:" k8s/base/api/deployment.yaml
grep "image:" k8s/base/frontend/deployment.yaml
```

> **注意**: プレースホルダーが残っている場合、Pod が `InvalidImageName` エラーになります。

### 4.2 アプリケーションデプロイ

```bash
# API Service のマニフェストを適用（Deployment, Service, HPA, ServiceAccount）
kubectl apply -f k8s/base/api/

# Frontend Service のマニフェストを適用（Deployment, Service）
kubectl apply -f k8s/base/frontend/

# Ingress（ALB）を作成
kubectl apply -f k8s/base/ingress.yaml
```

### 4.3 デプロイ状況の確認

```bash
# Pod の起動状況を監視（全 Pod が Running になるまで待機、Ctrl+C で終了）
kubectl get pods -n app-production -w

# 全 Pod が Ready になるまで待機（タイムアウト: 5 分）
kubectl wait --for=condition=Ready pod -l app=api-service -n app-production --timeout=300s

# Deployment の状態を確認
kubectl get deployments -n app-production

# 期待される出力:
# NAME               READY   UP-TO-DATE   AVAILABLE   AGE
# api-service        3/3     3            3           2m
# frontend-service   2/2     2            2           2m
```

### 4.4 ALB の確認

```bash
# Ingress の状態を確認（ALB の作成には数分かかる）
kubectl get ingress -n app-production

# ALB の DNS 名を取得して環境変数に設定
export ALB_DNS=$(kubectl get ingress -n app-production app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: ${ALB_DNS}"
```

> ALB_DNS が空の場合、ALB の作成がまだ完了していません。数分待って再実行してください。
> それでも空の場合は [トラブルシューティング 9.5](#95-alb-が作成されない) を参照してください。

### Step 4 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
echo "--- Pod Status ---"
kubectl get pods -n app-production
# → api-service, frontend-service の Pod が Running であること

echo "--- Deployments ---"
kubectl get deployments -n app-production
# → READY カラムが期待通りであること（例: 3/3）

echo "--- Ingress ---"
kubectl get ingress -n app-production
# → ADDRESS が設定されていること（ALB DNS 名）
```

> **チェック**: Pod が Running、Deployment が Ready であれば Step 4 完了です。

---

## Step 5: データベースマイグレーション

### 前提条件チェック

```bash
# Step 4 完了確認: Pod が Running であることを確認
RUNNING=$(kubectl get pods -n app-production --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$RUNNING" -gt 0 ]; then echo "OK: $RUNNING pods running"; else echo "ERROR: Running Pod がありません - Step 4 を実行してください"; fi
```

### 5.1 マイグレーション用 ConfigMap 作成

```bash
# SQL マイグレーションファイルを ConfigMap として Kubernetes に登録
kubectl create configmap migration-sql --namespace=app-production --from-file=apps/api/migrations/000001_create_users.up.sql --from-file=apps/api/migrations/000002_create_tasks.up.sql
```

### 5.2 マイグレーション実行

```bash
# PostgreSQL クライアント Pod を作成してマイグレーション SQL を実行
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
```

### 5.3 マイグレーション結果の確認とクリーンアップ

```bash
# Pod が完了するまで待機
kubectl wait --for=condition=Ready=false pod/psql-migration -n app-production --timeout=60s 2>/dev/null; sleep 10

# マイグレーションのログを確認（CREATE TABLE が表示されれば成功）
kubectl logs psql-migration -n app-production

# マイグレーション用の一時リソースを削除
kubectl delete pod psql-migration -n app-production
kubectl delete configmap migration-sql -n app-production
```

### Step 5 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
# マイグレーション Pod が完了していること（クリーンアップ済みなら NotFound が正常）
kubectl get pod psql-migration -n app-production 2>&1 || echo "OK: マイグレーション Pod はクリーンアップ済み"
```

> **チェック**: マイグレーションログに CREATE TABLE が表示され、一時リソースが削除されていれば Step 5 完了です。

---

## Step 6: 動作確認

### 前提条件チェック

```bash
# Step 5 完了確認: マイグレーションが完了していることを確認
# Pod がクリーンアップ済みであること
if kubectl get pod psql-migration -n app-production &>/dev/null; then
  echo "WARN: マイグレーション Pod がまだ存在します。Step 5 のクリーンアップを確認してください"
else
  echo "OK: マイグレーション完了（Pod クリーンアップ済み）"
fi
```

### 6.1 ヘルスチェック

```bash
# ALB DNS を再取得（環境変数がリセットされた場合）
export ALB_DNS=$(kubectl get ingress -n app-production app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# API のヘルスチェックエンドポイントにリクエスト
curl -s http://${ALB_DNS}/health/live

# 期待される出力: {"status":"ok"} または {"status":"healthy"}
```

### 6.2 ユーザー登録

```bash
# テストユーザーを作成
curl -s -X POST http://${ALB_DNS}/api/v1/auth/register -H "Content-Type: application/json" -d '{"username":"testuser","email":"test@example.com","password":"Password123!"}'
```

### 6.3 ログイン

```bash
# 作成したユーザーでログイン（JWT トークンが返却される）
curl -s -X POST http://${ALB_DNS}/api/v1/auth/login -H "Content-Type: application/json" -d '{"username":"testuser","password":"Password123!"}'
```

### 6.4 ブラウザアクセス

```bash
# ブラウザでフロントエンドを開く
echo "Application URL: http://${ALB_DNS}"
open http://${ALB_DNS}
```

**ログイン情報:**

- ユーザー名: `testuser`
- パスワード: `Password123!`

### Step 6 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
ALB_DNS=$(kubectl get ingress -n app-production app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s "http://${ALB_DNS}/health/live"
# → {"status":"ok"} または {"status":"healthy"} が返ること
```

> **チェック**: ヘルスチェックが成功し、ブラウザでアクセスできれば Step 6 完了です。

---

## Step 7: 監視設定

### 前提条件チェック

```bash
# Step 6 完了確認: アプリケーションが動作していることを確認
ALB_DNS=$(kubectl get ingress -n app-production app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -n "$ALB_DNS" ]; then
  HEALTH=$(curl -s "http://${ALB_DNS}/health/live" 2>/dev/null)
  echo "Health: ${HEALTH}"
  echo "$HEALTH" | grep -q "ok\|healthy" && echo "OK: ヘルスチェック成功" || echo "WARN: ヘルスチェック応答が想定外です"
else
  echo "ERROR: ALB DNS が取得できません - Step 4, 6 を確認してください"
fi
```

### 7.1 Prometheus Stack のデプロイ

```bash
# Helm リポジトリを追加
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 検証環境用の values ファイルを作成（永続化なし、リソース軽量）
cat <<'EOF' > /tmp/prometheus-values-dev.yaml
prometheus:
  prometheusSpec:
    retention: 3d
    resources:
      requests:
        memory: 512Mi
        cpu: 250m
      limits:
        memory: 1Gi
        cpu: 500m
    storageSpec: {}

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 128Mi
        cpu: 50m
    storage: {}

grafana:
  adminPassword: "admin123"
  persistence:
    enabled: false
  service:
    type: LoadBalancer
EOF

# Prometheus Stack をインストール
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values /tmp/prometheus-values-dev.yaml --wait --timeout 10m
```

> **EBS CSI Driver エラーが発生した場合**: [トラブルシューティング 9.6](#96-helm-installupgrade-で-pvc-エラー) を参照してください。

### 7.2 ServiceMonitor / PrometheusRule の適用

```bash
# API Service のメトリクス収集設定を適用
kubectl apply -f k8s/monitoring/servicemonitor-api.yaml

# アラートルールを適用
kubectl apply -f k8s/monitoring/prometheusrule-api-alerts.yaml
```

### 7.3 Grafana ダッシュボードの設定

```bash
# Golden Signals ダッシュボードを適用
kubectl apply -f k8s/monitoring/grafana-dashboard-golden-signals.yaml

# SLI/SLO ダッシュボードを適用
kubectl apply -f k8s/monitoring/grafana-dashboard-sli-slo.yaml
```

### 7.4 Grafana アクセス

```bash
# Grafana の External IP を取得
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# Grafana にログイン
# ユーザー名: admin
# パスワード: admin123
```

### 7.5 Fluent Bit（ログ収集）のデプロイ

```bash
# Fluent Bit の Helm リポジトリを追加
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# Fluent Bit 用の IRSA ロール ARN を取得
FLUENT_BIT_ROLE_ARN=$(terraform -chdir=environments/dev output -raw fluent_bit_role_arn)

# Fluent Bit をインストール（CloudWatch Logs に転送）
helm upgrade --install fluent-bit fluent/fluent-bit --namespace monitoring --values k8s/monitoring/fluent-bit-values.yaml --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${FLUENT_BIT_ROLE_ARN}"
```

### Step 7 完了確認

```bash
# 以下がすべて成功していることを確認してください
echo "--- Monitoring Pods ---"
kubectl get pods -n monitoring
# → prometheus, grafana, alertmanager, fluent-bit の Pod が Running であること

echo "--- Grafana Service ---"
kubectl get svc -n monitoring kube-prometheus-stack-grafana
# → External IP が割り当てられていること
```

> **チェック**: 監視 Pod が全て Running であれば Step 7 完了です。全デプロイ手順が完了しました！

---

## 8. 運用手順

### 8.1 アプリケーション更新

```bash
# 新しいイメージをビルド・プッシュした後、Deployment のイメージを更新
kubectl set image deployment/api-service api=${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest -n app-production

# ロールアウトの進行状況を監視
kubectl rollout status deployment/api-service -n app-production
```

### 8.2 ロールバック

```bash
# 直前のバージョンにロールバック
kubectl rollout undo deployment/api-service -n app-production

# リビジョン履歴を確認
kubectl rollout history deployment/api-service -n app-production

# 特定のリビジョンにロールバック
kubectl rollout undo deployment/api-service -n app-production --to-revision=2
```

### 8.3 スケーリング

```bash
# 手動でレプリカ数を変更
kubectl scale deployment/api-service --replicas=5 -n app-production

# HPA の状態を確認
kubectl get hpa -n app-production
```

### 8.4 Pod の再起動

```bash
# 全 Pod をローリング再起動（設定変更の反映時に使用）
kubectl rollout restart deployment/api-service -n app-production
```

---

## 9. トラブルシューティング

### 9.1 InvalidImageName エラー

**症状:**

```
Error: InvalidImageName
Failed to apply default image tag "${ECR_API_REPOSITORY_URL}:latest"
```

**原因:** マニフェストの image フィールドにプレースホルダーが残っている。

**対処:**

```bash
# 現在の image 設定を確認
grep "image:" k8s/base/api/deployment.yaml

# AWS アカウント ID が正しく置換されていない場合、再実行
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/api/deployment.yaml
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/base/frontend/deployment.yaml

# マニフェストを再適用
kubectl apply -f k8s/base/api/
```

### 9.2 CreateContainerConfigError / CrashLoopBackOff（Secret 関連）

**症状:**

```
Error: secret "jwt-secret" not found
```

または

```
FATAL: JWT_SECRET must be set in production environment
```

**原因:** Secret が存在しない、または値が空。

**対処:**

```bash
# Secret の存在を確認
kubectl get secrets -n app-production

# jwt-secret の値が空でないか確認
kubectl get secret jwt-secret -n app-production -o jsonpath='{.data.secret}' | base64 -d && echo ""

# 値が空または Secret が存在しない場合、再作成
kubectl delete secret jwt-secret -n app-production 2>/dev/null
JWT_VALUE=$(openssl rand -base64 32 | tr -d '\n')
echo "Generated JWT: ${JWT_VALUE}"
kubectl create secret generic jwt-secret --namespace app-production --from-literal=secret="${JWT_VALUE}"

# Pod を再起動して新しい Secret を読み込む
kubectl rollout restart deployment/api-service -n app-production
```

### 9.3 Redis 接続エラー

**症状:**

```
Failed to connect to Redis: dial tcp: lookup REDIS_ENDPOINT_HERE on 172.20.0.10:53: no such host
```

**原因:** ConfigMap の `REDIS_HOST` がプレースホルダーのまま。

**対処:**

```bash
# ConfigMap の現在の値を確認
kubectl get configmap api-config -n app-production -o jsonpath='{.data.REDIS_HOST}'
echo ""

# 正しい Redis エンドポイントを取得
export REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)
echo "Redis Endpoint: ${REDIS_HOST}"

# ConfigMap を更新
kubectl patch configmap api-config -n app-production --type merge -p "{\"data\":{\"REDIS_HOST\":\"${REDIS_HOST}\"}}"

# Pod を再起動して新しい設定を反映
kubectl rollout restart deployment/api-service -n app-production

# ログでエラーが解消されたことを確認
kubectl logs -l app=api-service -n app-production --tail=20
```

### 9.4 ImagePullBackOff エラー

**症状:**

```
Failed to pull image: Error response from daemon: pull access denied
```

**原因と対処:**

| 原因 | 対処 |
|------|------|
| ECR 認証切れ | `aws ecr get-login-password` で再ログインしてイメージを再プッシュ |
| イメージが存在しない | `aws ecr list-images --repository-name sre-portfolio/api` で確認 |
| アーキテクチャ不一致 | `--platform linux/amd64` を指定して再ビルド |

```bash
# Pod のイベントで詳細を確認
kubectl describe pod -n app-production -l app=api-service | tail -20
```

### 9.5 ALB が作成されない

**症状:** Ingress の ADDRESS が空のまま。

**対処:**

```bash
# AWS Load Balancer Controller のログを確認
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=30

# Ingress のイベントを確認
kubectl describe ingress -n app-production app-ingress

# Load Balancer Controller の Pod が Running か確認
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### 9.6 Helm install/upgrade で PVC エラー

**症状:**

```
Error: UPGRADE FAILED: resource not ready, name: kube-prometheus-stack-grafana, kind: PersistentVolumeClaim
```

**原因:** EBS CSI Driver がインストールされていない、またはデフォルト StorageClass が未設定。

**対処（方法 A: 永続化を無効にする - 検証環境向け）:**

```bash
# Helm リリースを削除
helm uninstall kube-prometheus-stack -n monitoring

# 残存する PVC を削除
kubectl delete pvc --all -n monitoring

# 永続化なしの values で再インストール（Step 7.1 のコマンドを再実行）
```

**対処（方法 B: EBS CSI Driver をインストール）:**

EBS CSI Driver には IRSA（IAM ロール）が必要です。

```bash
# クラスター名と OIDC プロバイダー URL を取得
CLUSTER_NAME=$(terraform -chdir=environments/dev output -raw cluster_name)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_URL=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')

# EBS CSI Driver 用の IAM 信頼ポリシーを作成
jq -n --arg account "$AWS_ACCOUNT_ID" --arg oidc "$OIDC_URL" '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::\($account):oidc-provider/\($oidc)"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"\($oidc):aud":"sts.amazonaws.com","\($oidc):sub":"system:serviceaccount:kube-system:ebs-csi-controller-sa"}}}]}' > /tmp/ebs-csi-trust-policy.json

# IAM ロールを作成してポリシーをアタッチ
aws iam create-role --role-name AmazonEKS_EBS_CSI_DriverRole --assume-role-policy-document file:///tmp/ebs-csi-trust-policy.json
aws iam attach-role-policy --role-name AmazonEKS_EBS_CSI_DriverRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

# IRSA 付きで EBS CSI Driver をインストール
aws eks create-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole

# ACTIVE になるまで確認（数分かかる）
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query '{status: addon.status, issues: addon.health.issues}'

# gp2 をデフォルト StorageClass に設定
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Helm を再実行
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --values /tmp/prometheus-values-dev.yaml --wait --timeout 10m
```

> **注意**: IRSA を設定せずにインストールすると `CrashLoopBackOff` になります。
> その場合は `aws eks delete-addon` で削除してから IRSA 付きで再作成してください。

### 9.7 EBS CSI Driver が CrashLoopBackOff

**症状:**

```
no EC2 IMDS role found, operation error ec2imds: GetMetadata, canceled, context deadline exceeded
```

**原因:** EBS CSI Driver に IRSA（IAM ロール）が設定されていない。

**対処:**

```bash
# アドオンを削除
CLUSTER_NAME=$(terraform -chdir=environments/dev output -raw cluster_name)
aws eks delete-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver

# 削除完了を確認（NotFound エラーが出れば OK）
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query 'addon.status' 2>&1

# IRSA 付きで再作成（9.6 方法 B の手順を参照）
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws eks create-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole

# ACTIVE になるまで確認
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query '{status: addon.status, issues: addon.health.issues}'
```

### 9.8 Terraform 実行時の DNS エラー

**症状:**

```
dial tcp: lookup eks.ap-northeast-1.amazonaws.com: no such host
```

**原因:** AWS の認証セッション（SSO 等）が切れている。

**対処:**

```bash
# SSO を再認証
aws sso login

# 認証が有効であることを確認
aws sts get-caller-identity

# Terraform コマンドを再実行
```

### 9.9 Pod の状態を総合的に確認

```bash
# 直近のイベントを時系列で確認
kubectl get events -n app-production --sort-by='.lastTimestamp' | tail -20

# ノードのリソース使用量を確認
kubectl top nodes

# Pod のリソース使用量を確認
kubectl top pods -n app-production

# ラベルセレクタで特定サービスのログを確認（Pod 名を指定しない）
kubectl logs -l app=api-service -n app-production --tail=50
```

---

## 10. 環境削除手順

> **重要:** 削除順序を守らないと AWS リソース（ALB, NLB, ENI）が残留し、VPC 削除が失敗します。

### 10.1 監視リソースの削除

> **重要:** Helm リリースは Namespace より先に削除してください。
> Namespace を先に削除すると Helm uninstall が失敗します。

```bash
# Helm でインストールした監視基盤を削除
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
helm uninstall fluent-bit -n monitoring 2>/dev/null || true

# 監視用 K8s マニフェストの削除（個別指定。values ファイルは K8s リソースではないため除外）
kubectl delete -f k8s/monitoring/servicemonitor-api.yaml 2>/dev/null || true
kubectl delete -f k8s/monitoring/prometheusrule-api-alerts.yaml 2>/dev/null || true
kubectl delete -f k8s/monitoring/grafana-dashboard-golden-signals.yaml 2>/dev/null || true
kubectl delete -f k8s/monitoring/grafana-dashboard-sli-slo.yaml 2>/dev/null || true
```

### 10.2 アプリケーションリソースの削除

```bash
# Ingress を先に削除（ALB の削除を開始）
kubectl delete -f k8s/base/ingress.yaml 2>/dev/null || true

# アプリケーションを削除
kubectl delete -f k8s/base/api/ 2>/dev/null || true
kubectl delete -f k8s/base/frontend/ 2>/dev/null || true

# Secrets と ConfigMap を削除
kubectl delete secret db-credentials redis-credentials jwt-secret -n app-production 2>/dev/null || true
kubectl delete configmap api-config -n app-production 2>/dev/null || true
```

### 10.3 Namespace の削除

```bash
# Namespace を削除（配下の残存リソースも全て削除される）
kubectl delete ns app-production 2>/dev/null || true
kubectl delete ns monitoring 2>/dev/null || true

# ALB/NLB が完全に削除されるまで待機（VPC 削除失敗を防止）
echo "Waiting for AWS resources cleanup..."
sleep 120
```

### 10.4 Terraform でインフラ削除

```bash
# 作業ディレクトリに移動
cd environments/dev

# 削除を実行（確認プロンプトで yes を入力）
terraform destroy
```

### 10.5 削除後の確認

```bash
# リソースが残っていないことを確認
aws eks list-clusters --region ap-northeast-1 --query 'clusters'
aws rds describe-db-instances --region ap-northeast-1 --query 'DBInstances[*].DBInstanceIdentifier'
aws elasticache describe-replication-groups --region ap-northeast-1 --query 'ReplicationGroups[*].ReplicationGroupId'
```

---

## 付録

### A. API エンドポイント一覧

| メソッド | エンドポイント | 説明 | 認証 |
|---------|---------------|------|------|
| GET | `/health/live` | ヘルスチェック | 不要 |
| POST | `/api/v1/auth/register` | ユーザー登録 | 不要 |
| POST | `/api/v1/auth/login` | ログイン | 不要 |
| GET | `/api/v1/tasks` | タスク一覧 | 必要 |
| POST | `/api/v1/tasks` | タスク作成 | 必要 |
| PUT | `/api/v1/tasks/:id` | タスク更新 | 必要 |
| DELETE | `/api/v1/tasks/:id` | タスク削除 | 必要 |
| GET | `/metrics` | Prometheus メトリクス | 不要 |

### B. 環境変数一覧

| 変数名 | 説明 | 取得元 |
|--------|------|--------|
| `AWS_ACCOUNT_ID` | AWS アカウント ID | `aws sts get-caller-identity` |
| `DB_HOST` | RDS エンドポイント | Secrets Manager |
| `DB_PORT` | RDS ポート | Secrets Manager |
| `DB_USER` | RDS ユーザー名 | Secrets Manager |
| `DB_PASSWORD` | RDS パスワード | Secrets Manager |
| `REDIS_HOST` | Redis エンドポイント | `terraform output` |
| `REDIS_AUTH_TOKEN` | Redis 認証トークン | Secrets Manager |
| `ALB_DNS` | ALB の DNS 名 | `kubectl get ingress` |

### C. コスト見積もり

検証環境の月額コスト概算（東京リージョン）:

| リソース | 概算月額 |
|---------|---------|
| EKS Cluster | ~$73 |
| EKS Nodes (t3.medium × 3) | ~$124 |
| NAT Gateway × 1 | ~$34 |
| RDS (db.t3.micro, Single-AZ) | ~$15 |
| ElastiCache (cache.t3.micro × 1) | ~$13 |
| ALB | ~$22 + データ転送 |
| **合計** | **~$281/月** |

> 使用しない時間は `terraform destroy` で削除することでコストを抑えられます。

---

**最終更新**: 2026-01-26
