# SRE Portfolio - 本番環境（Production）デプロイ手順書

本手順書では、AWS EKS上に本番環境を構築・デプロイするための手順を説明します。

> **重要**: 本番環境のデプロイは慎重に行ってください。本手順書に従い、各ステップでの確認を怠らないようにしてください。

---

## 目次（チェックリスト）

> 各ステップ完了時にチェックを入れてください。自動スクリプトを使用する場合: `bash scripts/deploy-prod.sh`

- [ ] [環境概要](#1-環境概要) を確認
- [ ] [前提条件](#2-前提条件) を確認
- [ ] [本番環境の特徴](#3-本番環境の特徴) を確認
- [ ] [デプロイ前チェックリスト](#4-デプロイ前チェックリスト) を完了
- [ ] [Step 1: Terraform でインフラ構築](#step-1-terraform-でインフラ構築)
- [ ] [Step 2: コンテナイメージのビルド・プッシュ](#step-2-コンテナイメージのビルドプッシュ)
- [ ] [Step 3: Kubernetes Secrets/ConfigMap 作成](#step-3-kubernetes-secretsconfigmap-作成)
- [ ] [Step 4: アプリケーションデプロイ](#step-4-アプリケーションデプロイ)
- [ ] [Step 5: データベースマイグレーション](#step-5-データベースマイグレーション)
- [ ] [Step 6: 監視設定](#step-6-監視設定)
- [ ] [Step 7: 本番稼働前検証](#step-7-本番稼働前検証)
- [ ] [運用手順](#7-運用手順) を確認
- [ ] [トラブルシューティング](#8-トラブルシューティング) を確認
- [ ] [環境削除手順](#9-環境削除手順) を確認

---

## 1. 環境概要

### 1.1 アーキテクチャ

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Production Environment                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
│  │   AZ-1a     │    │   AZ-1c     │    │   AZ-1d     │                     │
│  │             │    │             │    │             │                     │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │                     │
│  │ │   NAT   │ │    │ │   NAT   │ │    │ │   NAT   │ │  ← Multi-NAT GW    │
│  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │                     │
│  │             │    │             │    │             │                     │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │                     │
│  │ │EKS Node │ │    │ │EKS Node │ │    │ │EKS Node │ │  ← 3+ Nodes        │
│  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │                     │
│  │             │    │             │    │             │                     │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │             │                     │
│  │ │   RDS   │ │    │ │RDS Stdby│ │    │             │  ← Multi-AZ RDS    │
│  │ │ Primary │ │    │ │         │ │    │             │                     │
│  │ └─────────┘ │    │ └─────────┘ │    │             │                     │
│  │             │    │             │    │             │                     │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │                     │
│  │ │ Redis   │ │    │ │ Redis   │ │    │ │ Redis   │ │  ← 3-Node Cluster  │
│  │ │ Primary │ │    │ │ Replica │ │    │ │ Replica │ │                     │
│  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │                     │
│  └─────────────┘    └─────────────┘    └─────────────┘                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 リソース構成

| コンポーネント | 構成 | 備考 |
|---------------|------|------|
| VPC | 10.0.0.0/16 | 3 AZ構成 |
| NAT Gateway | 3個（各AZに1個） | 高可用性 |
| EKS Cluster | v1.32 | 全ログタイプ有効 |
| EKS Nodes | t3.medium × 3-10 | ON_DEMAND、Auto Scaling |
| RDS PostgreSQL | db.t3.small | Multi-AZ、削除保護有効 |
| ElastiCache Redis | cache.t3.small × 3 | Multi-AZ、自動フェイルオーバー |
| CloudWatch | 30日保持 | アラーム設定済み |

---

## 2. 前提条件

### 2.1 必要なツール

```bash
# バージョン確認
aws --version        # 2.x 以上
terraform --version  # 1.5.0 以上
kubectl version      # 1.28 以上
docker --version     # 20.x 以上
helm version         # 3.x 以上
jq --version         # 1.6 以上
```

### 2.2 AWS 認証

```bash
# 認証情報の確認
aws sts get-caller-identity

# 期待される出力:
# {
#     "UserId": "...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

### 2.3 必要な IAM 権限

本番環境のデプロイには以下の権限が必要です：

- `AdministratorAccess` または以下の権限セット:
  - VPC/EC2/EKS 管理権限
  - RDS/ElastiCache 管理権限
  - IAM ロール/ポリシー作成権限
  - CloudWatch/SNS 管理権限
  - Secrets Manager 管理権限
  - ECR 管理権限

---

## 3. 本番環境の特徴

### 3.1 開発環境との差分

| 項目 | 開発環境 (dev) | 本番環境 (prod) |
|------|---------------|-----------------|
| NAT Gateway | 1個（コスト削減） | 3個（高可用性） |
| EKS Nodes | 2ノード | 3-10ノード（Auto Scaling） |
| RDS | Single-AZ | Multi-AZ |
| RDS インスタンス | db.t3.micro | db.t3.small |
| RDS 削除保護 | 無効 | **有効** |
| RDS 最終スナップショット | スキップ | **必須** |
| Redis | 2ノード | 3ノード |
| VPC Flow Logs | 無効 | **有効** |
| ログ保持期間 | 7日 | 30日 |
| アラートメール | オプション | **必須** |

### 3.2 セキュリティ強化項目

- **VPC Flow Logs**: 全ネットワークトラフィックをログ記録
- **削除保護**: RDS の誤削除を防止
- **暗号化**: RDS/Redis の転送時・保存時暗号化
- **Secrets Manager**: 認証情報の安全な管理
- **Performance Insights**: RDS のパフォーマンス監視

---

## 4. デプロイ前チェックリスト

### 4.1 必須確認項目

デプロイを開始する前に、以下を確認してください：

```text
□ AWS 認証情報が正しく設定されている
□ 必要な IAM 権限がある
□ アラート通知先メールアドレスが決定している
□ 開発環境でのテストが完了している
□ コンテナイメージがビルド可能である
□ 本番用の設定値（tfvars）を確認した
□ チームメンバーにデプロイを通知した
□ ロールバック手順を理解している
```

### 4.2 コスト見積もり

本番環境の月額コスト概算（東京リージョン）:

| リソース | 概算月額 |
|---------|---------|
| EKS Cluster | ~$73 |
| EKS Nodes (t3.medium × 3) | ~$124 |
| NAT Gateway × 3 | ~$101 |
| RDS (db.t3.small, Multi-AZ) | ~$50 |
| ElastiCache (cache.t3.small × 3) | ~$75 |
| ALB | ~$22 + データ転送 |
| CloudWatch | ~$10-30 |
| **合計** | **~$455-485/月** |

> **注意**: 実際のコストは使用量により変動します。

---

## Step 1: Terraform でインフラ構築

### 前提条件チェック

```bash
# AWS 認証が有効であることを確認（エラーが出る場合は aws sso login を実行）
aws sts get-caller-identity
# → Account ID と ARN が表示されること
```

### 1.1 作業ディレクトリに移動

```bash
cd environments/prod
```

### 1.2 設定ファイルの確認

```bash
# terraform.tfvars の内容を確認
cat terraform.tfvars

# 特に以下を確認:
# - alert_email が設定されているか（必須）
# - rds_multi_az = true
# - rds_deletion_protection = true
# - single_nat_gateway = false
```

### 1.3 アラートメールの設定

`terraform.tfvars` を編集し、アラートメールを設定：

```bash
# terraform.tfvars に追加
alert_email = "your-ops-team@yourcompany.com"
```

> **重要**: `example.com` などのプレースホルダードメインは使用できません。

### 1.4 Terraform 初期化

```bash
terraform init
```

期待される出力:

```text
Terraform has been successfully initialized!
```

### 1.5 プラン確認

```bash
# プランを確認（重要：本番環境では必ず確認）
terraform plan -out=tfplan

# 作成されるリソース数を確認
# 例: Plan: 50 to add, 0 to change, 0 to destroy.
```

### 1.6 インフラ構築

```bash
# 適用（約25-35分）
terraform apply tfplan

# または対話形式で
terraform apply
```

> **所要時間**: 約25-35分（EKS クラスター作成に15-20分、RDS Multi-AZ に10-15分）

### 1.7 出力値の確認

```bash
# 主要な出力値を確認
terraform output

# kubeconfig 設定
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region ap-northeast-1

# 接続確認
kubectl get nodes

# 期待される出力（3ノード以上）:
# NAME                                            STATUS   ROLES    AGE   VERSION
# ip-10-0-1-xxx.ap-northeast-1.compute.internal   Ready    <none>   5m    v1.32.x
# ip-10-0-2-xxx.ap-northeast-1.compute.internal   Ready    <none>   5m    v1.32.x
# ip-10-0-3-xxx.ap-northeast-1.compute.internal   Ready    <none>   5m    v1.32.x
```

### Step 1 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
kubectl get nodes   # 3 ノード以上が Ready 状態であること
terraform -chdir=environments/prod output cluster_name  # クラスター名が出力されること
```

> **チェック**: ノードが Ready になっていれば Step 1 完了です。目次のチェックボックスを更新してください。

---

## Step 2: コンテナイメージのビルド・プッシュ

### 前提条件チェック

```bash
# Step 1 完了確認: クラスターに接続できることを確認
kubectl get nodes
# → 3 ノード以上が Ready 状態で表示されない場合、Step 1 に戻ってください
```

### 2.1 環境変数設定

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-northeast-1
export IMAGE_TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "Image Tag: ${IMAGE_TAG}"
```

### 2.2 ECR ログイン

```bash
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS \
  --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

### 2.3 プロジェクトルートに移動

```bash
cd ../..
```

### 2.4 API イメージのビルド・プッシュ

> **M1/M2 Mac 使用時:** `--platform linux/amd64` を必ず指定してください。
> EKS ノードは amd64 アーキテクチャのため、arm64 イメージでは動作しません。

```bash
# 本番用イメージのビルド
docker buildx build --platform linux/amd64 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sre-portfolio/api:${IMAGE_TAG} \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sre-portfolio/api:latest \
  --push ./apps/api

# イメージの確認
aws ecr describe-images \
  --repository-name sre-portfolio/api \
  --query 'imageDetails[*].{Tag:imageTags,Pushed:imagePushedAt}' \
  --output table
```

### 2.5 Frontend イメージのビルド・プッシュ

```bash
docker buildx build --platform linux/amd64 \
  --build-arg VITE_API_URL=/api \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sre-portfolio/frontend:${IMAGE_TAG} \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sre-portfolio/frontend:latest \
  --push ./apps/frontend
```

### Step 2 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
aws ecr describe-images --repository-name sre-portfolio/api --query 'imageDetails[*].imageTags' --output text
aws ecr describe-images --repository-name sre-portfolio/frontend --query 'imageDetails[*].imageTags' --output text
# → 両方にイメージタグが表示されること
```

> **チェック**: 両リポジトリにイメージが存在すれば Step 2 完了です。

---

## Step 3: Kubernetes Secrets/ConfigMap 作成

### 前提条件チェック

```bash
# Step 2 完了確認: ECR にイメージが存在することを確認
aws ecr describe-images --repository-name sre-portfolio/api --query 'imageDetails[0].imageTags' --output text &>/dev/null && echo "OK: api image exists" || echo "ERROR: api image not found - Step 2 を実行してください"
aws ecr describe-images --repository-name sre-portfolio/frontend --query 'imageDetails[0].imageTags' --output text &>/dev/null && echo "OK: frontend image exists" || echo "ERROR: frontend image not found - Step 2 を実行してください"
```

### 3.1 認証情報の取得

```bash
# 作業ディレクトリに移動
cd environments/prod

# RDS 認証情報の取得
RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_secret_arn) \
  --query SecretString --output text)

export DB_HOST=$(echo $RDS_SECRET | jq -r '.host')
export DB_PORT=$(echo $RDS_SECRET | jq -r '.port')
export DB_USER=$(echo $RDS_SECRET | jq -r '.username')
export DB_PASSWORD=$(echo $RDS_SECRET | jq -r '.password')

# Redis 認証情報の取得
export REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw redis_secret_arn) \
  --query SecretString --output text | jq -r '.auth_token')
export REDIS_HOST=$(terraform output -raw redis_primary_endpoint)

# 取得結果の確認（パスワードは表示しない）
echo "DB_HOST: ${DB_HOST}"
echo "REDIS_HOST: ${REDIS_HOST}"
```

### 3.2 Namespace 作成

```bash
kubectl apply -f ../../k8s/base/namespace.yaml

# 確認
kubectl get namespace app-production
```

### 3.3 Secrets 作成

```bash
# Database Credentials
kubectl create secret generic db-credentials --namespace app-production --from-literal=host=${DB_HOST} --from-literal=port=${DB_PORT} --from-literal=dbname=taskmanager --from-literal=username=${DB_USER} --from-literal=password=${DB_PASSWORD} --dry-run=client -o yaml | kubectl apply -f -

# Redis Credentials
kubectl create secret generic redis-credentials --namespace app-production --from-literal=auth_token=${REDIS_AUTH_TOKEN} --dry-run=client -o yaml | kubectl apply -f -

# JWT Secret（本番用に強力なシークレットを生成）
# 注意: コマンド置換が正しく動作するよう、値を変数に格納してから実行
JWT_VALUE=$(openssl rand -base64 64 | tr -d '\n')
echo "Generated JWT: ${JWT_VALUE}"  # 値が生成されていることを確認
kubectl create secret generic jwt-secret --namespace app-production --from-literal=secret="${JWT_VALUE}"

# 確認（3つの Secret が存在すること）
kubectl get secrets -n app-production

# jwt-secret の値が空でないことを確認（重要）
kubectl get secret jwt-secret -n app-production -o jsonpath='{.data.secret}' | base64 -d && echo ""
```

> **注意**: jwt-secret の値が空の場合、Pod が `CrashLoopBackOff` になります。
> 上記の確認コマンドで値が表示されない場合は、シークレットを削除して再作成してください。

### 3.4 ConfigMap 作成

```bash
# 環境変数の確認
echo "REDIS_HOST: ${REDIS_HOST}"

# ConfigMap 作成
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: app-production
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  REDIS_HOST: "${REDIS_HOST}"
  REDIS_PORT: "6379"
  REDIS_TLS: "true"
EOF

# 確認
kubectl get configmap api-config -n app-production -o yaml
```

### Step 3 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
echo "--- Secrets ---"
kubectl get secrets -n app-production
# → db-credentials, redis-credentials, jwt-secret の 3 つが存在すること

echo "--- ConfigMap ---"
kubectl get configmap api-config -n app-production -o jsonpath='{.data.REDIS_HOST}' && echo ""
# → Redis エンドポイントが表示されること（空やプレースホルダーでないこと）

echo "--- jwt-secret 検証 ---"
kubectl get secret jwt-secret -n app-production -o jsonpath='{.data.secret}' | base64 -d | wc -c | tr -d ' '
# → 0 より大きい値であること
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

### 4.1 ECR イメージ URL の設定（重要）

kustomization.yaml に ECR リポジトリ URL を設定します。

```bash
# ECR URL を取得
ECR_URL=$(terraform output -raw ecr_api_repository_url)
echo "ECR URL: ${ECR_URL}"

# kustomization.yaml を更新
sed -i '' "s|REPLACE_WITH_ECR_URL|${ECR_URL}|g" ../../k8s/api/kustomization.yaml

# 設定を確認
grep -A2 "newName:" ../../k8s/api/kustomization.yaml
```

> **注意**: この手順をスキップすると、Pod が `InvalidImageName` エラーになります。

### 4.2 Kubernetes マニフェストの確認

```bash
# 本番用の設定を確認
ls -la ../../k8s/api/

# kustomize でビルド結果をプレビュー（実際に適用する前に確認）
kubectl kustomize ../../k8s/api/ | head -100
```

### 4.3 アプリケーションデプロイ

```bash
# API Service（kustomize を使用）
kubectl apply -k ../../k8s/api/

# Frontend Service（k8s/frontend/ ディレクトリが存在する場合）
# kubectl apply -k ../../k8s/frontend/
```

### 4.4 デプロイ状況の確認

```bash
# Pod の状態確認
kubectl get pods -n app-production -w

# 全 Pod が Running になるまで待機
kubectl wait --for=condition=Ready pod \
  -l app=api-service \
  -n app-production \
  --timeout=300s

# デプロイメントの状態確認
kubectl get deployments -n app-production

# 期待される出力:
# NAME          READY   UP-TO-DATE   AVAILABLE   AGE
# api-service   3/3     3            3           2m
```

### 4.5 ALB の確認

```bash
# Ingress の状態確認（ALB 作成には数分かかる）
kubectl get ingress -n app-production -w

# ALB の DNS 名を取得
ALB_DNS=$(kubectl get ingress api-ingress -n app-production \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: ${ALB_DNS}"
```

### Step 4 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
echo "--- Pod Status ---"
kubectl get pods -n app-production
# → api-service の Pod が Running であること

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
kubectl create configmap migration-sql --namespace=app-production --from-file=../../apps/api/migrations/000001_create_users.up.sql --from-file=../../apps/api/migrations/000002_create_tasks.up.sql
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
sleep 15

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

## Step 6: 監視設定

### 前提条件チェック

```bash
# Step 5 完了確認: マイグレーションが完了していることを確認
if kubectl get pod psql-migration -n app-production &>/dev/null; then
  echo "WARN: マイグレーション Pod がまだ存在します。Step 5 のクリーンアップを確認してください"
else
  echo "OK: マイグレーション完了（Pod クリーンアップ済み）"
fi

# アプリケーション Pod が動作していることを確認
kubectl get pods -n app-production
```

### 6.1 EBS CSI Driver のインストール

Prometheus・Grafana の永続化ストレージに EBS ボリュームを使用するため、EBS CSI Driver が必要です。
EBS CSI Driver が EC2 API を呼び出すには IRSA（IAM Roles for Service Accounts）が必要です。

```bash
# クラスター名と OIDC プロバイダー URL を取得
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_URL=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')
echo "OIDC: ${OIDC_URL}"

# EBS CSI Driver 用の IAM 信頼ポリシーを作成
jq -n --arg account "$AWS_ACCOUNT_ID" --arg oidc "$OIDC_URL" '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::\($account):oidc-provider/\($oidc)"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"\($oidc):aud":"sts.amazonaws.com","\($oidc):sub":"system:serviceaccount:kube-system:ebs-csi-controller-sa"}}}]}' > /tmp/ebs-csi-trust-policy.json

# IAM ロールを作成
aws iam create-role --role-name AmazonEKS_EBS_CSI_DriverRole --assume-role-policy-document file:///tmp/ebs-csi-trust-policy.json

# EBS CSI Driver 用の AWS 管理ポリシーをアタッチ
aws iam attach-role-policy --role-name AmazonEKS_EBS_CSI_DriverRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

# IRSA ロール付きで EBS CSI Driver アドオンをインストール
aws eks create-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole

# アドオンの状態を確認（ACTIVE になるまで繰り返し実行）
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query '{status: addon.status, issues: addon.health.issues}'

# gp2 をデフォルト StorageClass に設定
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# StorageClass の確認（gp2 に (default) が表示されること）
kubectl get storageclass
```

> **注意**: IRSA を設定せずにアドオンをインストールすると `CrashLoopBackOff` になります。
> その場合は `aws eks delete-addon` で削除してから、上記の手順で IRSA 付きで再作成してください。

### 6.2 Prometheus Stack のデプロイ

```bash
# Helm リポジトリを追加
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 本番用の values ファイルを作成（<<'EOF' でシングルクォート EOF を使い変数展開を防ぐ）
cat <<'EOF' > /tmp/prometheus-values-prod.yaml
prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        memory: 1Gi
        cpu: 500m
      limits:
        memory: 2Gi
        cpu: 1000m
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m

grafana:
  persistence:
    enabled: true
    storageClassName: gp2
    size: 10Gi
  service:
    type: LoadBalancer
EOF

# Prometheus Stack をインストール
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values /tmp/prometheus-values-prod.yaml --wait --timeout 10m

# Grafana のパスワードを確認
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d && echo ""
```

### 6.3 ServiceMonitor / PrometheusRule の適用

```bash
kubectl apply -f ../../k8s/monitoring/servicemonitor-api.yaml
kubectl apply -f ../../k8s/monitoring/prometheusrule-api-alerts.yaml
```

### 6.4 Grafana ダッシュボードの設定

```bash
kubectl apply -f ../../k8s/monitoring/grafana-dashboard-golden-signals.yaml
kubectl apply -f ../../k8s/monitoring/grafana-dashboard-sli-slo.yaml
```

### 6.5 Fluent Bit（ログ収集）のデプロイ

```bash
# Fluent Bit のデプロイ
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# IAM Role ARN の取得
FLUENT_BIT_ROLE_ARN=$(terraform output -raw fluent_bit_role_arn)

cat <<EOF > /tmp/fluent-bit-values-prod.yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: ${FLUENT_BIT_ROLE_ARN}

config:
  outputs: |
    [OUTPUT]
        Name cloudwatch_logs
        Match *
        region ap-northeast-1
        log_group_name /aws/eks/sre-portfolio-cluster/application
        log_stream_prefix fluent-bit-
        auto_create_group true
EOF

helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace monitoring \
  --values /tmp/fluent-bit-values-prod.yaml
```

### Step 6 完了確認

```bash
# 以下がすべて成功していることを確認してから次へ進んでください
echo "--- Monitoring Pods ---"
kubectl get pods -n monitoring
# → prometheus, grafana, alertmanager, fluent-bit の Pod が Running であること

echo "--- Grafana Service ---"
kubectl get svc -n monitoring kube-prometheus-stack-grafana
# → External IP が割り当てられていること
```

> **チェック**: 監視 Pod が全て Running であれば Step 6 完了です。

---

## Step 7: 本番稼働前検証

### 前提条件チェック

```bash
# Step 6 完了確認: 監視 Pod が動作していることを確認
MONITORING_PODS=$(kubectl get pods -n monitoring --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$MONITORING_PODS" -gt 0 ]; then echo "OK: $MONITORING_PODS monitoring pods running"; else echo "WARN: monitoring Pod がありません - Step 6 を確認してください"; fi
```

### 6.1 ヘルスチェック

```bash
# API ヘルスチェック（エンドポイントは /health/live）
curl -s http://${ALB_DNS}/health/live
```

### 6.2 テストユーザー登録

```bash
# テストユーザーを作成
curl -s -X POST http://${ALB_DNS}/api/v1/auth/register -H "Content-Type: application/json" -d '{"username":"testuser","email":"test@example.com","password":"Password123!"}'

# ログインして JWT トークンを取得
TOKEN=$(curl -s -X POST http://${ALB_DNS}/api/v1/auth/login -H "Content-Type: application/json" -d '{"username":"testuser","password":"Password123!"}' | jq -r '.access_token')
echo "TOKEN: ${TOKEN}"
```

### 6.3 機能テスト

```bash
# タスク一覧を取得（認証が必要）
curl -s http://${ALB_DNS}/api/v1/tasks -H "Authorization: Bearer ${TOKEN}" | jq .

# メトリクスエンドポイント確認
curl -s http://${ALB_DNS}/metrics | head -20
```

### 6.4 監視確認

```bash
# Prometheus ターゲット確認
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# ブラウザで http://localhost:9090/targets を確認

# Grafana アクセス
kubectl get svc -n monitoring kube-prometheus-stack-grafana
# External IP でアクセス
```

### 6.5 アラートテスト

```bash
# テスト用に一時的にエラーを発生させる（オプション）
# 本番では慎重に実行

# SNS トピックの確認
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)
```

### 6.6 本番稼働チェックリスト

```text
□ 全 Pod が Running 状態
□ ALB がヘルシーなターゲットを持っている
□ ヘルスチェックが成功している
□ Prometheus がメトリクスを収集している
□ Grafana ダッシュボードが正常に表示される
□ CloudWatch にログが出力されている
□ アラートメールの購読を確認した
□ バックアップが設定されている（RDS 自動スナップショット）
```

### Step 7 完了確認

> **チェック**: 上記チェックリストの全項目を確認できれば Step 7 完了です。全デプロイ手順が完了しました！

---

## 7. 運用手順

### 7.1 デプロイ（アプリケーション更新）

```bash
# 新しいイメージのデプロイ
export NEW_TAG=v1.2.0

# イメージを更新
kubectl set image deployment/api-service \
  api=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sre-portfolio/api:${NEW_TAG} \
  -n app-production

# ロールアウト状況の監視
kubectl rollout status deployment/api-service -n app-production
```

### 7.2 ロールバック

```bash
# 直前のバージョンにロールバック
kubectl rollout undo deployment/api-service -n app-production

# 特定のリビジョンにロールバック
kubectl rollout history deployment/api-service -n app-production
kubectl rollout undo deployment/api-service -n app-production --to-revision=2
```

### 7.3 スケーリング

```bash
# 手動スケーリング
kubectl scale deployment/api-service --replicas=5 -n app-production

# HPA の確認（Cluster Autoscaler と連携）
kubectl get hpa -n app-production
```

### 7.4 メンテナンス

```bash
# Pod の再起動（ローリング）
kubectl rollout restart deployment/api-service -n app-production

# 特定 Pod の削除（自動再作成される）
kubectl delete pod <pod-name> -n app-production
```

---

## 8. トラブルシューティング

> **参照**: 詳細なトラブルシューティング記録は [TROUBLESHOOTING_2026-01-23.md](./TROUBLESHOOTING_2026-01-23.md) を参照してください。

### 8.1 InvalidImageName エラー

```bash
# 症状: Pod が InvalidImageName ステータス
# 原因: kustomization.yaml の images.newName が未設定

# 確認
kubectl get pods -n app-production
grep -A2 "newName:" ../../k8s/api/kustomization.yaml

# 対処: ECR URL を設定して再デプロイ
ECR_URL=$(terraform output -raw ecr_api_repository_url)
sed -i '' "s|REPLACE_WITH_ECR_URL|${ECR_URL}|g" ../../k8s/api/kustomization.yaml
kubectl apply -k ../../k8s/api/
```

### 8.2 CreateContainerConfigError / CrashLoopBackOff（Secret 関連）

```bash
# 症状: Pod が CreateContainerConfigError または CrashLoopBackOff
# 原因: Secret が存在しない、または値が空

# 確認
kubectl get secrets -n app-production
kubectl describe pod <pod-name> -n app-production | tail -20
kubectl logs -l app=api-service -n app-production --tail=20

# jwt-secret の値が空でないか確認
kubectl get secret jwt-secret -n app-production -o jsonpath='{.data.secret}' | base64 -d && echo ""

# 対処: シークレット再作成
kubectl delete secret jwt-secret -n app-production
JWT_VALUE=$(openssl rand -base64 64 | tr -d '\n')
kubectl create secret generic jwt-secret --namespace app-production --from-literal=secret="${JWT_VALUE}"
kubectl rollout restart deployment/api-service -n app-production
```

### 8.3 Pod が起動しない（その他）

```bash
# Pod の状態確認
kubectl describe pod <pod-name> -n app-production

# ログの確認
kubectl logs <pod-name> -n app-production --previous

# イベントの確認
kubectl get events -n app-production --sort-by='.lastTimestamp'
```

### 8.4 データベース接続エラー

```bash
# Secret の確認
kubectl get secret db-credentials -n app-production -o jsonpath='{.data.host}' | base64 -d

# RDS の状態確認
aws rds describe-db-instances \
  --db-instance-identifier sre-portfolio-db \
  --query 'DBInstances[0].DBInstanceStatus'

# セキュリティグループの確認
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw cluster_primary_security_group_id)
```

### 8.5 Redis 接続エラー

```bash
# Redis エンドポイント確認
terraform output redis_primary_endpoint

# ElastiCache の状態確認
aws elasticache describe-replication-groups \
  --replication-group-id sre-portfolio-redis
```

### 8.6 ALB が作成されない

```bash
# AWS Load Balancer Controller のログを確認
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=30

# Ingress の詳細確認
kubectl describe ingress app-ingress -n app-production
```

### 8.7 EBS CSI Driver が CrashLoopBackOff

**症状:**

```
no EC2 IMDS role found, operation error ec2imds: GetMetadata, canceled, context deadline exceeded
```

**原因:** EBS CSI Driver に IRSA（IAM ロール）が設定されていない。

**対処:**

```bash
# アドオンを削除
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks delete-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver

# 削除完了を確認（NotFound エラーが出れば OK）
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query 'addon.status' 2>&1

# IRSA 付きで再作成（Step 5.1 の手順を参照）
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws eks create-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole

# ACTIVE になるまで確認
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query '{status: addon.status, issues: addon.health.issues}'
```

### 8.8 Helm install/upgrade で PVC エラー

**症状:**

```
Error: UPGRADE FAILED: resource not ready, name: kube-prometheus-stack-grafana, kind: PersistentVolumeClaim
```

**原因:** EBS CSI Driver が未インストール、またはデフォルト StorageClass が未設定。

**対処:**

```bash
# 失敗した Helm リリースと PVC をクリーンアップ
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null
kubectl delete pvc --all -n monitoring

# EBS CSI Driver が ACTIVE か確認
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --query 'addon.status'

# ACTIVE でない場合は Step 5.1 の手順で EBS CSI Driver をインストール

# gp2 がデフォルト StorageClass か確認
kubectl get storageclass

# Prometheus Stack を再インストール
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values /tmp/prometheus-values-prod.yaml --wait --timeout 10m
```

### 8.9 Terraform 実行時の DNS エラー

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

---

## 9. 環境削除手順

> **警告**: 本番環境の削除は慎重に行ってください。削除保護が有効になっているため、以下の手順に従う必要があります。

### 9.1 削除前チェックリスト

```text
□ 削除の承認を得ている
□ 必要なデータのバックアップを取得した
□ 関連する DNS レコードを確認した
□ チームメンバーに通知した
```

### 9.2 Kubernetes リソースの削除

> **重要:** 削除順序を守ってください。Helm リリース → K8s マニフェスト → Namespace の順に削除します。
> Namespace を先に削除すると Helm uninstall が失敗します。

```bash
# 1. Helm リリースの削除（Namespace より先に実行すること）
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
helm uninstall fluent-bit -n monitoring 2>/dev/null || true

# 2. 監視用 K8s マニフェストの削除（個別指定。values ファイルは K8s リソースではないため除外）
kubectl delete -f ../../k8s/monitoring/servicemonitor-api.yaml 2>/dev/null || true
kubectl delete -f ../../k8s/monitoring/prometheusrule-api-alerts.yaml 2>/dev/null || true
kubectl delete -f ../../k8s/monitoring/grafana-dashboard-golden-signals.yaml 2>/dev/null || true
kubectl delete -f ../../k8s/monitoring/grafana-dashboard-sli-slo.yaml 2>/dev/null || true

# 3. アプリケーションの削除（デプロイ時に kubectl apply -k を使用したため -k で削除）
kubectl delete -k ../../k8s/api/ 2>/dev/null || true

# 4. Namespace の削除（配下の残存リソースも全て削除される）
kubectl delete namespace app-production 2>/dev/null || true
kubectl delete namespace monitoring 2>/dev/null || true

# 5. ALB/NLB が完全に削除されるまで待機（VPC 削除失敗を防止）
echo "Waiting for AWS resources cleanup..."
sleep 120
```

### 9.3 削除保護の解除

```bash
cd environments/prod

# RDS 削除保護の解除
aws rds modify-db-instance \
  --db-instance-identifier sre-portfolio-postgres \
  --no-deletion-protection \
  --apply-immediately

# 変更が反映されるまで待機
aws rds wait db-instance-available \
  --db-instance-identifier sre-portfolio-postgres
```

### 9.4 Terraform でインフラ削除

```bash
# 削除プランの確認
terraform plan -destroy

# 削除実行（約15-25分）
terraform destroy

# 確認プロンプトで "yes" を入力
```

### 9.5 削除後の確認

```bash
# リソースが残っていないか確認
aws eks list-clusters --region ap-northeast-1
aws rds describe-db-instances --region ap-northeast-1
aws elasticache describe-replication-groups --region ap-northeast-1

# S3 バケット（Terraform state）の確認
# 必要に応じて手動削除
```

---

## 付録

### A. 環境変数一覧

| 変数名 | 説明 | 設定元 |
|--------|------|--------|
| `AWS_ACCOUNT_ID` | AWS アカウント ID | `aws sts get-caller-identity` |
| `AWS_REGION` | AWS リージョン | `ap-northeast-1` |
| `DB_HOST` | RDS エンドポイント | Secrets Manager |
| `DB_PASSWORD` | RDS パスワード | Secrets Manager |
| `REDIS_HOST` | Redis エンドポイント | Terraform output |
| `REDIS_AUTH_TOKEN` | Redis 認証トークン | Secrets Manager |

### B. 重要な Terraform 出力

```bash
# 全出力の確認
terraform output

# 主要な出力
terraform output cluster_name
terraform output cluster_endpoint
terraform output rds_endpoint
terraform output redis_primary_endpoint
terraform output sns_topic_arn
```

### C. 参考リンク

- [AWS EKS ドキュメント](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubernetes ドキュメント](https://kubernetes.io/docs/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)

---

**最終更新**: 2026-01-23
**作成者**: SRE Team
