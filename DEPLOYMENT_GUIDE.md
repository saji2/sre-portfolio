# SRE Portfolio - 環境構築・デプロイ手順書

本手順書では、AWS EKS上にタスク管理アプリケーションをデプロイするまでの全工程を説明します。

---

## 目次

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

以下のツールをインストールしてください。

| ツール | バージョン | 用途 |
|--------|-----------|------|
| AWS CLI | v2.x | AWS リソースの操作 |
| Terraform | v1.5+ | Infrastructure as Code |
| kubectl | v1.28+ | Kubernetes クラスタ操作 |
| Docker | v24+ | コンテナイメージのビルド |
| Helm | v3.x | Kubernetes パッケージ管理 |
| Go | v1.22+ | API アプリケーション開発 |
| Node.js | v20+ | フロントエンド開発 |

**インストール確認コマンド:**

```bash
aws --version
terraform --version
kubectl version --client
docker --version
helm version
go version
node --version
```

### 1.2 AWS 認証情報の設定

**理由:** Terraform と AWS CLI が AWS リソースを作成・管理するために認証情報が必要です。

```bash
# AWS CLI の設定
aws configure

# 設定項目:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region name: ap-northeast-1
# - Default output format: json

# 認証確認
aws sts get-caller-identity
```

### 1.3 必要な AWS IAM 権限

Terraform 実行ユーザーには以下の権限が必要です:

- VPC (作成・管理)
- EKS (クラスタ・ノードグループ管理)
- RDS (インスタンス作成)
- ElastiCache (クラスタ作成)
- ECR (リポジトリ作成)
- IAM (ロール・ポリシー作成)
- CloudWatch (ログ・アラーム作成)
- SNS (トピック作成)
- Secrets Manager (シークレット管理)

---

## 2. ローカル開発環境の構築

### 2.1 Docker Compose による起動

**理由:** AWS リソースを作成する前に、ローカルでアプリケーションの動作確認ができます。開発コストを抑え、イテレーションを高速化します。

```bash
# プロジェクトルートに移動
cd terraform-claude

# コンテナのビルドと起動
docker-compose up --build

# バックグラウンドで起動する場合
docker-compose up -d --build
```

### 2.2 ローカル環境の構成

Docker Compose は以下のサービスを起動します:

| サービス | ポート | 説明 |
|---------|--------|------|
| api | 8080 | Go API サーバー |
| frontend | 3000 | React フロントエンド (Nginx) |
| postgres | 5432 | PostgreSQL データベース |
| redis | 6379 | Redis キャッシュ |

### 2.3 動作確認

```bash
# API ヘルスチェック
curl http://localhost:8080/health/live

# フロントエンドアクセス
open http://localhost:3000
```

### 2.4 ローカル環境の停止

```bash
# 停止
docker-compose down

# ボリュームも削除する場合
docker-compose down -v
```

---

## 3. AWSインフラストラクチャの構築

### 3.1 アーキテクチャ概要

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                        VPC (10.0.0.0/16)                │
                    │  ┌─────────────────────────────────────────────────┐   │
                    │  │              Public Subnets (3 AZs)              │   │
                    │  │         ALB, NAT Gateway, Internet Gateway       │   │
                    │  └─────────────────────────────────────────────────┘   │
                    │  ┌─────────────────────────────────────────────────┐   │
                    │  │           Private EKS Subnets (3 AZs)           │   │
                    │  │              EKS Worker Nodes                    │   │
                    │  │         ┌─────────┐    ┌──────────┐             │   │
Internet ──► ALB ──►│  │         │   API   │    │ Frontend │             │   │
                    │  │         │  Pods   │    │   Pods   │             │   │
                    │  │         └────┬────┘    └──────────┘             │   │
                    │  └──────────────┼───────────────────────────────────┘   │
                    │  ┌──────────────┼───────────────────────────────────┐   │
                    │  │           Private Data Subnets (2 AZs)          │   │
                    │  │    ┌────────▼─────────┐   ┌──────────────┐      │   │
                    │  │    │   RDS PostgreSQL │   │ ElastiCache  │      │   │
                    │  │    │     (Multi-AZ)   │   │    Redis     │      │   │
                    │  │    └──────────────────┘   └──────────────┘      │   │
                    │  └─────────────────────────────────────────────────┘   │
                    └─────────────────────────────────────────────────────────┘
```

### 3.2 Terraform の初期化

**理由:** Terraform プロバイダーとモジュールをダウンロードし、バックエンド（状態管理）を初期化します。

```bash
cd environments/dev

# 初期化
terraform init
```

**出力例:**
```
Initializing modules...
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.100.0...
- Installing hashicorp/kubernetes v2.38.0...
- Installing hashicorp/helm v2.17.0...

Terraform has been successfully initialized!
```

### 3.3 設定の検証

**理由:** 構文エラーや設定ミスを事前に検出し、apply 時の失敗を防ぎます。

```bash
# 構文チェック
terraform validate

# フォーマット修正
terraform fmt -recursive
```

### 3.4 実行計画の確認

**理由:** 実際に作成されるリソースを事前に確認し、意図しない変更を防ぎます。

```bash
# 実行計画の表示
terraform plan -var="alert_email=saji55627@gmail.com"
```

**確認ポイント:**
- 作成されるリソース数
- リソース名・設定値
- 依存関係

### 3.5 インフラストラクチャの作成

**理由:** AWS 上に VPC、EKS、RDS、ElastiCache などのリソースを作成します。

```bash
# インフラ作成（確認プロンプトあり）
terraform apply -var="alert_email=saji55627@gmail.com"

# 確認をスキップする場合
terraform apply -var="alert_email=saji55627@gmail.com" -auto-approve
```

**所要時間:** 約 20-30 分

#### リソース競合エラーが発生した場合

以前に `terraform destroy` を実行した環境を再作成する場合、以下のエラーが発生することがあります：

```
Error: creating Secrets Manager Secret: secret with this name is already scheduled for deletion
Error: creating CloudWatch Logs Log Group: The specified log group already exists
```

**対処方法:**

```bash
# Secrets Manager の削除待機中シークレットを即座に削除
aws secretsmanager delete-secret \
  --secret-id "sre-portfolio/rds/credentials" \
  --force-delete-without-recovery \
  --region ap-northeast-1

aws secretsmanager delete-secret \
  --secret-id "sre-portfolio/redis/auth-token" \
  --force-delete-without-recovery \
  --region ap-northeast-1

# CloudWatch Log Group を削除
aws logs delete-log-group \
  --log-group-name "/aws/eks/sre-portfolio-cluster/cluster" \
  --region ap-northeast-1

# 再度 apply を実行
terraform apply -var="alert_email=your-email@example.com"
```

**作成されるリソース:**

| モジュール | 主なリソース | 理由 |
|-----------|-------------|------|
| VPC | VPC, サブネット, NAT GW, IGW | ネットワーク分離とセキュリティ境界の確立 |
| EKS | クラスタ, ノードグループ, OIDC | コンテナオーケストレーション基盤 |
| RDS | PostgreSQL インスタンス | アプリケーションデータの永続化 |
| ElastiCache | Redis クラスタ | セッション・キャッシュデータの高速処理 |
| ECR | コンテナリポジトリ | Docker イメージの安全な保存・配布 |
| Monitoring | CloudWatch, SNS | 可観測性とアラート通知 |

### 3.6 出力値の確認

```bash
# 出力値の表示
terraform output
```

**重要な出力値:**

```hcl
# EKS クラスタ接続情報
eks_cluster_name     = "sre-portfolio-cluster"
eks_cluster_endpoint = "https://xxxxx.eks.ap-northeast-1.amazonaws.com"

# データベース接続情報
rds_endpoint         = "sre-portfolio-db.xxxxx.ap-northeast-1.rds.amazonaws.com"
rds_secret_arn       = "arn:aws:secretsmanager:ap-northeast-1:xxxxx:secret:..."  # ※ rds_secrets_arn ではない

# Redis 接続情報
redis_primary_endpoint = "master.sre-portfolio-redis.xxxxx.cache.amazonaws.com"  # ※ elasticache_primary_endpoint ではない
redis_secret_arn       = "arn:aws:secretsmanager:ap-northeast-1:xxxxx:secret:..."

# ECR リポジトリ
ecr_api_repository_url      = "xxxxx.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api"
ecr_frontend_repository_url = "xxxxx.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend"
```

> **注意:** Output 名を間違えると `Output not found` エラーになります。
> 正確な Output 名は `terraform output` で確認してください。

### 3.7 kubectl の設定

**理由:** EKS クラスタと通信するために kubeconfig を設定します。

```bash
# kubeconfig の更新
aws eks update-kubeconfig \
  --name sre-portfolio-cluster \
  --region ap-northeast-1

# 接続確認
kubectl cluster-info
kubectl get nodes
```

---

## 4. コンテナイメージのビルドとプッシュ

### 4.1 ECR へのログイン

**理由:** ECR は認証が必要なプライベートレジストリです。Docker CLI に認証トークンを設定します。

```bash
# AWS アカウント ID の取得
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ECR ログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
```

### 4.2 API イメージのビルドとプッシュ

**理由:** Go アプリケーションをコンテナ化し、EKS からアクセス可能な ECR に保存します。

> **重要:** M1/M2 Mac を使用している場合、必ず `--platform linux/amd64` を指定してください。
> EKS ノード（t3.medium）は amd64 アーキテクチャで動作するため、arm64 でビルドしたイメージは動作しません。

```bash
# プロジェクトルートに移動
cd /path/to/terraform-claude

# API イメージのビルドとプッシュ（amd64 アーキテクチャ指定）
docker buildx build \
  --platform linux/amd64 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest \
  --push \
  ./apps/api
```

**docker buildx が使用できない場合:**
```bash
# buildx の確認
docker buildx version

# 新しいビルダーインスタンスを作成・使用
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap
```

### 4.3 Frontend イメージのビルドとプッシュ

**理由:** React アプリケーションを Nginx コンテナとしてビルドし、静的ファイル配信を最適化します。

```bash
# Frontend イメージのビルドとプッシュ（amd64 アーキテクチャ指定）
docker buildx build \
  --platform linux/amd64 \
  --build-arg VITE_API_URL=/api \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest \
  --push \
  ./apps/frontend
```

### 4.4 イメージの確認

```bash
# ECR リポジトリ内のイメージ一覧
aws ecr list-images --repository-name sre-portfolio/api
aws ecr list-images --repository-name sre-portfolio/frontend
```

---

## 5. Kubernetesへのデプロイ

### 5.1 Secrets の設定

**理由:** データベースや JWT の認証情報を安全に管理します。平文で保存せず、Kubernetes Secrets として暗号化されます。

#### 5.1.1 RDS 認証情報の取得

```bash
# Secrets Manager から RDS 認証情報を取得
RDS_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id $(terraform -chdir=environments/dev output -raw rds_secret_arn) \
    --query SecretString --output text)

# 各値を抽出
DB_HOST=$(echo $RDS_SECRET | jq -r '.host')
DB_PORT=$(echo $RDS_SECRET | jq -r '.port')
DB_USER=$(echo $RDS_SECRET | jq -r '.username')
DB_PASSWORD=$(echo $RDS_SECRET | jq -r '.password')
```

#### 5.1.2 Redis 認証情報の取得

> **重要:** ElastiCache は `transit_encryption_enabled = true`（デフォルト）で TLS 接続と AUTH Token が必須です。

```bash
# ElastiCache Auth Token を取得
REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
    --secret-id $(terraform -chdir=environments/dev output -raw redis_secret_arn) \
    --query SecretString --output text | jq -r '.auth_token')

# Redis エンドポイントを取得
REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)

# 取得した値を確認
echo "REDIS_HOST: ${REDIS_HOST}"
echo "REDIS_AUTH_TOKEN length: ${#REDIS_AUTH_TOKEN}"
```

#### 5.1.3 Kubernetes Secrets の作成

```bash
# Namespace 作成
kubectl apply -f k8s/base/namespace.yaml

# DB Secrets の作成
kubectl create secret generic db-credentials \
  --namespace app-production \
  --from-literal=host=${DB_HOST} \
  --from-literal=port=${DB_PORT} \
  --from-literal=dbname=taskmanager \
  --from-literal=username=${DB_USER} \
  --from-literal=password=${DB_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -

# Redis Secrets の作成（TLS 接続に必要）
kubectl create secret generic redis-credentials \
  --namespace app-production \
  --from-literal=auth_token=${REDIS_AUTH_TOKEN} \
  --dry-run=client -o yaml | kubectl apply -f -

# JWT Secret の作成（ランダム生成）
JWT_SECRET=$(openssl rand -base64 32)
kubectl create secret generic jwt-secret \
  --namespace app-production \
  --from-literal=secret=${JWT_SECRET} \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5.2 ConfigMap の設定

**理由:** 環境変数などの設定値を外部化し、イメージを再ビルドせずに設定変更できるようにします。

> **重要:** `REDIS_HOST` には実際の ElastiCache エンドポイントを設定してください。
> プレースホルダー（`REDIS_ENDPOINT_HERE`）のままだと Pod が起動しません。

```bash
# ConfigMap の作成（Redis エンドポイントを設定）
kubectl create configmap api-config \
  --namespace app-production \
  --from-literal=REDIS_HOST=${REDIS_HOST} \
  --from-literal=REDIS_PORT=6379 \
  --from-literal=LOG_LEVEL=info \
  --from-literal=CORS_ALLOWED_ORIGINS="*" \
  --dry-run=client -o yaml | kubectl apply -f -

# 設定内容を確認
kubectl get configmap api-config -n app-production -o yaml
```

**注意:** Redis 認証トークン（`REDIS_PASSWORD`）は Secret 経由で設定されます（`redis-credentials`）。
ConfigMap には含めないでください。

### 5.3 マニフェストの編集

**理由:** 環境固有の値（ECR URL、IAM Role ARN）をマニフェストに反映します。

#### 5.3.1 イメージ URL の更新

`k8s/base/api/deployment.yaml` を編集:

```yaml
spec:
  containers:
  - name: api
    image: <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest
```

`k8s/base/frontend/deployment.yaml` を編集:

```yaml
spec:
  containers:
  - name: frontend
    image: <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest
```

#### 5.3.2 ServiceAccount の IAM Role 設定

`k8s/base/api/serviceaccount.yaml` を編集:

```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/sre-portfolio-cluster-api-service-role
```

### 5.4 アプリケーションのデプロイ

**理由:** Kubernetes マニフェストを適用し、Pod、Service、Ingress を作成します。

```bash
# 全リソースのデプロイ
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/api/
kubectl apply -f k8s/base/frontend/
kubectl apply -f k8s/base/ingress.yaml
```

### 5.5 デプロイ状況の確認

```bash
# Pod の状態確認
kubectl get pods -n app-production -w

# すべてのリソース確認
kubectl get all -n app-production

# Pod の詳細（トラブルシューティング用）
kubectl describe pod -n app-production -l app=api-service
```

### 5.6 データベースマイグレーション

**理由:** テーブル構造を作成し、アプリケーションがデータを保存できるようにします。

> **注意:** API コンテナには migrate バイナリが含まれていないため、ConfigMap を使用して psql Pod から直接マイグレーションを実行します。

```bash
# Step 1: マイグレーション SQL ファイルから ConfigMap を作成
kubectl create configmap migration-sql \
  --namespace=app-production \
  --from-file=apps/api/migrations/000001_create_users.up.sql \
  --from-file=apps/api/migrations/000002_create_tasks.up.sql

# Step 2: psql Pod を使用してマイグレーションを実行
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
        echo "Running migration 000001_create_users.up.sql..."
        psql -h "$DB_HOST" -U "$DB_USER" -d taskmanager -f /migrations/000001_create_users.up.sql
        echo "Running migration 000002_create_tasks.up.sql..."
        psql -h "$DB_HOST" -U "$DB_USER" -d taskmanager -f /migrations/000002_create_tasks.up.sql
        echo "Migrations completed!"
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

# Step 3: マイグレーション完了を待機してログを確認
sleep 10
kubectl logs psql-migration -n app-production

# Step 4: リソースのクリーンアップ
kubectl delete pod psql-migration -n app-production
kubectl delete configmap migration-sql -n app-production
```

**テーブル作成の確認:**

```bash
# 一時的な psql Pod でテーブル一覧を確認
kubectl run psql-verify --rm -i --restart=Never \
  --image=postgres:15-alpine \
  --namespace=app-production \
  --env="PGPASSWORD=$(kubectl get secret db-credentials -n app-production -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h "$(kubectl get secret db-credentials -n app-production -o jsonpath='{.data.host}' | base64 -d)" \
  -U "$(kubectl get secret db-credentials -n app-production -o jsonpath='{.data.username}' | base64 -d)" \
  -d taskmanager -c "\dt"
```

**期待される出力:**
```
        List of relations
 Schema | Name  | Type  |  Owner
--------+-------+-------+---------
 public | tasks | table | dbadmin
 public | users | table | dbadmin
(2 rows)
```

---

## 6. 動作確認

### 6.1 ALB エンドポイントの取得

**理由:** ALB が作成されるまで数分かかります。エンドポイントを確認してアクセスします。

```bash
# Ingress の外部 URL を取得
kubectl get ingress -n app-production

# ALB DNS 名の取得
ALB_DNS=$(kubectl get ingress -n app-production app-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Application URL: http://${ALB_DNS}"
```

### 6.2 ヘルスチェック

```bash
# API ヘルスチェック
curl http://${ALB_DNS}/health/live

# 期待される応答:
# {"status":"ok"}
```

### 6.3 フロントエンドアクセス

```bash
# ブラウザでアクセス
open http://${ALB_DNS}
```

### 6.4 ログの確認

```bash
# API ログ
kubectl logs -n app-production -l app=api-service --tail=100 -f

# Frontend ログ
kubectl logs -n app-production -l app=frontend-service --tail=100 -f
```

### 6.5 初期ユーザーの作成

**理由:** データベースには初期ユーザーが存在しないため、アプリケーションにログインするにはユーザー登録が必要です。

#### 6.5.1 API 経由でユーザーを登録

```bash
# ALB DNS を取得（未取得の場合）
ALB_DNS=$(kubectl get ingress -n app-production app-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# ユーザー登録 API を呼び出す
curl -X POST http://${ALB_DNS}/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "Password123!"
  }'
```

**期待される応答:**
```json
{
  "data": {
    "created_at": "2026-01-17T07:56:57.079901Z",
    "email": "test@example.com",
    "id": 1,
    "username": "testuser"
  }
}
```

#### 6.5.2 ログイン確認

```bash
# ログイン API を呼び出す
curl -X POST http://${ALB_DNS}/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "Password123!"
  }'
```

**期待される応答:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 900,
  "token_type": "Bearer"
}
```

#### 6.5.3 ブラウザからログイン

以下の情報でログイン画面からアクセスできます:

| 項目 | 値 |
|------|-----|
| ユーザー名 | `testuser` |
| パスワード | `Password123!` |

**API エンドポイント一覧（参考）:**

| メソッド | エンドポイント | 説明 | 認証 |
|---------|---------------|------|------|
| POST | `/api/v1/auth/register` | ユーザー登録 | 不要 |
| POST | `/api/v1/auth/login` | ログイン | 不要 |
| POST | `/api/v1/auth/refresh` | トークン更新 | 不要 |
| POST | `/api/v1/auth/logout` | ログアウト | 必要 |
| GET | `/api/v1/tasks` | タスク一覧 | 必要 |
| POST | `/api/v1/tasks` | タスク作成 | 必要 |
| GET | `/api/v1/tasks/:id` | タスク取得 | 必要 |
| PUT | `/api/v1/tasks/:id` | タスク更新 | 必要 |
| DELETE | `/api/v1/tasks/:id` | タスク削除 | 必要 |
| PATCH | `/api/v1/tasks/:id/status` | ステータス更新 | 必要 |

---

## 7. トラブルシューティング

### 7.1 ImagePullBackOff エラー

```bash
# Pod の状態確認
kubectl describe pod -n app-production -l app=api-service
```

**エラーメッセージ例:**
```
Failed to pull image: no match for platform in manifest: not found
```

**原因と対処:**

| 原因 | 対処方法 |
|------|---------|
| アーキテクチャ不一致（arm64 vs amd64） | `docker buildx build --platform linux/amd64` で再ビルド |
| ECR 認証切れ | `aws ecr get-login-password` で再ログイン |
| イメージが存在しない | `aws ecr list-images` でイメージ存在確認 |

```bash
# amd64 で再ビルド・プッシュ
docker buildx build \
  --platform linux/amd64 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest \
  --push \
  ./apps/api

# Pod 再起動
kubectl rollout restart deployment/api-service -n app-production
```

### 7.2 CrashLoopBackOff エラー

```bash
# Pod ログの確認
kubectl logs -n app-production -l app=api-service --tail=50

# 前回終了時のログ
kubectl logs -n app-production -l app=api-service --previous
```

**よくあるエラーと対処:**

#### 7.2.1 DNS 解決エラー
```
dial tcp: lookup REDIS_ENDPOINT_HERE: no such host
```

**原因:** ConfigMap の `REDIS_HOST` がプレースホルダーのまま

**対処:**
```bash
# 正しい Redis エンドポイントで ConfigMap を更新
REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)
kubectl patch configmap api-config -n app-production \
  --type merge -p "{\"data\":{\"REDIS_HOST\":\"${REDIS_HOST}\"}}"
kubectl rollout restart deployment/api-service -n app-production
```

#### 7.2.2 Redis 接続タイムアウト
```
dial tcp 10.0.x.x:6379: i/o timeout
```

**原因:** ElastiCache TLS 有効だがアプリが TLS 未対応、または AUTH Token 未設定

**対処:**
1. `redis-credentials` シークレットが存在するか確認
2. Deployment に `REDIS_PASSWORD` と `REDIS_TLS_ENABLED` が設定されているか確認

```bash
# シークレット確認
kubectl get secret redis-credentials -n app-production

# シークレットがない場合は作成
REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw redis_secret_arn) \
  --query SecretString --output text | jq -r '.auth_token')

kubectl create secret generic redis-credentials \
  --namespace app-production \
  --from-literal=auth_token=${REDIS_AUTH_TOKEN}
```

### 7.3 Pod が起動しない（その他）

```bash
# イベントログの確認
kubectl get events -n app-production --sort-by='.lastTimestamp'
```

**よくある原因:**
- Secret/ConfigMap 未設定 → 必要なリソースが存在するか確認
- リソース不足 → ノードのリソース状況を確認

### 7.4 データベース接続エラー

```bash
# RDS セキュリティグループ確認
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*rds*"

# DB 接続テスト（Pod 内から）
kubectl exec -it -n app-production <api-pod> -- \
  nc -zv <rds-endpoint> 5432
```

### 7.5 ALB が作成されない

```bash
# AWS Load Balancer Controller のログ確認
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Ingress の状態確認
kubectl describe ingress -n app-production app-ingress
```

### 7.6 クラスタノードの状況

```bash
# ノード一覧
kubectl get nodes -o wide

# ノードのリソース使用状況
kubectl top nodes

# Pod のリソース使用状況
kubectl top pods -n app-production
```

---

## 付録

### A. コスト最適化のヒント

| リソース | Dev 環境 | 理由 |
|---------|---------|------|
| NAT Gateway | 1個 | 可用性より コスト優先 |
| RDS | db.t3.micro | 開発用途に十分 |
| EKS ノード | t3.medium × 3 | 最小構成 |
| ElastiCache | cache.t3.micro × 2 | 最小構成 |

### B. 環境削除

```bash
# Kubernetes リソース削除
kubectl delete -f k8s/base/

# Terraform リソース削除
cd environments/dev
terraform destroy -var="alert_email=your-email@example.com"
```

### C. CI/CD パイプライン

GitHub Actions による自動デプロイが設定されています:

1. `main` ブランチへの push でトリガー
2. テスト実行
3. Docker イメージビルド・プッシュ
4. EKS へのローリングデプロイ

**必要な GitHub Secrets:**
- `AWS_ROLE_ARN`: OIDC 用 IAM Role ARN
- `AWS_ACCOUNT_ID`: AWS アカウント ID

---

## 参考リンク

- [AWS EKS ドキュメント](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [Kubernetes ドキュメント](https://kubernetes.io/docs/)
