# デプロイエラーと解決策サマリー

このドキュメントは、EKSアプリケーションデプロイ時に発生したエラーとその解決策をまとめたものです。

---

## 1. Terraform Output 名の不一致エラー

### 1.1 RDS シークレット ARN の Output 名エラー

**エラーメッセージ**:
```
Error: Output "rds_secrets_arn" not found
The output variable requested could not be found in the state file.
aws: [ERROR]: argument --secret-id: expected one argument
```

**原因**:
- コマンドで使用した出力名: `rds_secrets_arn`（複数形の "s"）
- 実際に定義されている出力名: `rds_secret_arn`（単数形）

**解決コマンド**:
```bash
# 正しい Output 名を使用
RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw rds_secret_arn) \
  --query SecretString --output text)
```

---

### 1.2 ElastiCache エンドポイントの Output 名エラー

**エラーメッセージ**:
```
Error: Output "elasticache_primary_endpoint" not found
The output variable requested could not be found in the state file.
```

**原因**:
- コマンドで使用した出力名: `elasticache_primary_endpoint`
- 実際に定義されている出力名: `redis_primary_endpoint`

**解決コマンド**:
```bash
# 正しい Output 名を使用
REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)
```

---

## 2. AWS Secrets Manager エラー

### 2.1 Redis Auth Token シークレット名の不一致

**エラーメッセージ**:
```
An error occurred (ResourceNotFoundException) when calling the GetSecretValue operation:
Secrets Manager can't find the specified secret.
```

**原因**:
- 使用しようとしたシークレット名: `sre-portfolio-redis-auth-token`（ハイフン区切り）
- 実際に作成されたシークレット名: `sre-portfolio/redis/auth-token`（スラッシュ区切り）

**解決コマンド**:
```bash
# 方法1: Terraform Output から ARN を取得（推奨）
REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform -chdir=environments/dev output -raw redis_secret_arn) \
  --query SecretString --output text | jq -r '.auth_token')

# 方法2: 正しいシークレット名を直接指定
REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "sre-portfolio/redis/auth-token" \
  --query SecretString --output text | jq -r '.auth_token')
```

---

### 2.2 削除待機中のシークレットとの競合

**エラーメッセージ**:
```
Error: creating Secrets Manager Secret (sre-portfolio/redis/auth-token):
operation error Secrets Manager: CreateSecret, StatusCode: 400,
InvalidRequestException: You can't create this secret because a secret
with this name is already scheduled for deletion.

Error: creating Secrets Manager Secret (sre-portfolio/rds/credentials):
operation error Secrets Manager: CreateSecret, StatusCode: 400,
InvalidRequestException: You can't create this secret because a secret
with this name is already scheduled for deletion.
```

**原因**:
- Secrets Manager は削除が非同期で、デフォルト7日間の待機期間がある
- 削除スケジュール中のシークレットと同名のシークレットは作成できない

**解決コマンド**:
```bash
# 削除スケジュール中のシークレットを即座に完全削除
aws secretsmanager delete-secret \
  --secret-id "sre-portfolio/rds/credentials" \
  --force-delete-without-recovery \
  --region ap-northeast-1

aws secretsmanager delete-secret \
  --secret-id "sre-portfolio/redis/auth-token" \
  --force-delete-without-recovery \
  --region ap-northeast-1

# 再度 Terraform apply
terraform apply
```

---

## 3. CloudWatch Log Group 競合エラー

**エラーメッセージ**:
```
Error: creating CloudWatch Logs Log Group (/aws/eks/sre-portfolio-cluster/cluster):
operation error CloudWatch Logs: CreateLogGroup, StatusCode: 400,
ResourceAlreadyExistsException: The specified log group already exists
```

**原因**:
- 既存の CloudWatch Log Group が残っている
- Terraform の state と実際のリソースが不整合

**解決コマンド**:
```bash
# 方法1: 既存のLog Groupを削除してから再作成
aws logs delete-log-group \
  --log-group-name "/aws/eks/sre-portfolio-cluster/cluster" \
  --region ap-northeast-1

terraform apply

# 方法2: 既存のリソースをTerraformにインポート
cd environments/dev
terraform import module.monitoring.aws_cloudwatch_log_group.eks_cluster \
  "/aws/eks/sre-portfolio-cluster/cluster"

terraform apply
```

---

## 4. Docker イメージ アーキテクチャ不一致

**エラーメッセージ**:
```
Failed to pull image "202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest":
rpc error: code = NotFound desc = failed to pull and unpack image
"202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest":
no match for platform in manifest: not found
```

**Kubernetes Pod のステータス**:
```
NAME                               READY   STATUS             RESTARTS   AGE
api-service-xxx                    0/1     ImagePullBackOff   0          5m
frontend-service-xxx               0/1     ImagePullBackOff   0          5m
```

**原因**:
- M1/M2 Mac で arm64 アーキテクチャとしてビルドされた Docker イメージ
- EKS ノード（t3.medium）は amd64/x86_64 アーキテクチャで動作
- アーキテクチャの不一致により、イメージをプルできない

**解決コマンド**:
```bash
# 1. ECR にログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com

# 2. amd64 アーキテクチャでイメージを再ビルド・プッシュ（API）
cd apps/api
docker buildx build \
  --platform linux/amd64 \
  -t 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest \
  --push .

# 3. amd64 アーキテクチャでイメージを再ビルド・プッシュ（Frontend）
cd apps/frontend
docker buildx build \
  --platform linux/amd64 \
  -t 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest \
  --push .

# 4. Kubernetes Pod を再起動
kubectl rollout restart deployment/api-service -n app-production
kubectl rollout restart deployment/frontend-service -n app-production

# 5. 状態確認
kubectl get pods -n app-production -w
```

**補足**: `docker buildx` が使用できない場合:
```bash
# Docker Desktop の場合、buildx は標準で利用可能
# buildx が有効か確認
docker buildx version

# 新しいビルダーインスタンスを作成・使用
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap
```

---

## 5. Kubernetes マニフェストのプレースホルダー未置換

**問題**:
マニフェスト内の `ACCOUNT_ID` プレースホルダーが実際の AWS アカウント ID に置き換わっていない

**影響を受けるファイル**:
- `k8s/base/api/deployment.yaml:37` - ECR イメージ URL
- `k8s/base/frontend/deployment.yaml:30` - ECR イメージ URL
- `k8s/base/api/serviceaccount.yaml:7` - IAM Role ARN

**解決コマンド**:
```bash
# AWS アカウント ID を取得
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 一括置換
find k8s/ -name "*.yaml" -exec sed -i '' "s/ACCOUNT_ID/${ACCOUNT_ID}/g" {} \;

# 変更確認
grep -r "${ACCOUNT_ID}" k8s/

# Kubernetes マニフェストを再適用
kubectl apply -k k8s/overlays/dev/
```

**置換後の例**:
```yaml
# k8s/base/api/deployment.yaml
image: 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest

# k8s/base/frontend/deployment.yaml
image: 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/frontend:latest

# k8s/base/api/serviceaccount.yaml
eks.amazonaws.com/role-arn: "arn:aws:iam::202516977224:role/sre-portfolio-cluster-api-service-role"
```

---

## 6. ConfigMap の REDIS_HOST がプレースホルダーのまま

**Kubernetes Pod のステータス**:
```
NAME                               READY   STATUS             RESTARTS   AGE
api-service-xxx                    0/1     CrashLoopBackOff   10         36m
```

**エラーメッセージ**（Pod ログ）:
```
dial tcp: lookup REDIS_ENDPOINT_HERE on 10.0.0.2:53: no such host
```

**原因**:
- ConfigMap `api-config` の `REDIS_HOST` が `REDIS_ENDPOINT_HERE` というプレースホルダーのまま
- 実際の ElastiCache エンドポイントに置き換わっていない

**確認コマンド**:
```bash
kubectl get configmap api-config -n app-production -o yaml
```

**解決コマンド**:
```bash
# Terraform から実際の Redis エンドポイントを取得
REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)

# ConfigMap を更新
kubectl patch configmap api-config -n app-production \
  --type merge -p "{\"data\":{\"REDIS_HOST\":\"${REDIS_HOST}\"}}"

# Pod を再起動
kubectl rollout restart deployment/api-service -n app-production
```

---

## 7. ElastiCache TLS 接続と AUTH Token 未設定

**Kubernetes Pod のステータス**:
```
NAME                               READY   STATUS             RESTARTS   AGE
api-service-xxx                    0/1     CrashLoopBackOff   12         43m
```

**エラーメッセージ**（Pod ログ）:
```
dial tcp 10.0.x.x:6379: i/o timeout
```

**原因**:
- ElastiCache は `transit_encryption_enabled = true`（デフォルト）で **TLS 接続が必須**
- ElastiCache は AUTH Token（パスワード）による認証が必要
- アプリは `REDIS_HOST` と `REDIS_PORT` のみ設定しており、TLS/AUTH Token 設定がない

**設定の不一致**:
| 項目 | ElastiCache 側 | アプリ側 |
|------|---------------|---------|
| TLS | 有効（必須） | 未対応 |
| AUTH Token | 必要 | 未設定 |

**解決方法**:

### Step 1: アプリコードに TLS 設定を追加

**`apps/api/internal/config/config.go`**:
```go
type RedisConfig struct {
    Host       string
    Port       string
    Password   string
    DB         int
    TLSEnabled bool  // 追加
}

// Load() 関数内
Redis: RedisConfig{
    Host:       getEnv("REDIS_HOST", "localhost"),
    Port:       getEnv("REDIS_PORT", "6379"),
    Password:   getEnv("REDIS_PASSWORD", ""),
    DB:         getEnvInt("REDIS_DB", 0),
    TLSEnabled: getEnvBool("REDIS_TLS_ENABLED", false),  // 追加
},

// getEnvBool 関数を追加
func getEnvBool(key string, defaultValue bool) bool {
    if value, exists := os.LookupEnv(key); exists {
        boolValue, err := strconv.ParseBool(value)
        if err != nil {
            return defaultValue
        }
        return boolValue
    }
    return defaultValue
}
```

**`apps/api/internal/cache/redis.go`**:
```go
import (
    "crypto/tls"
    // ...
)

func NewRedis(cfg config.RedisConfig) (*RedisClient, error) {
    opts := &redis.Options{
        Addr:     fmt.Sprintf("%s:%s", cfg.Host, cfg.Port),
        Password: cfg.Password,
        DB:       cfg.DB,
    }

    // TLS 設定を追加（AWS ElastiCache with transit encryption）
    if cfg.TLSEnabled {
        opts.TLSConfig = &tls.Config{
            MinVersion: tls.VersionTLS12,
        }
    }

    client := redis.NewClient(opts)
    // ...
}
```

### Step 2: Kubernetes マニフェストに環境変数を追加

**`k8s/base/api/deployment.yaml`**:
```yaml
env:
  # ... 既存の環境変数 ...
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: redis-credentials
        key: auth_token
  - name: REDIS_TLS_ENABLED
    value: "true"
```

### Step 3: Kubernetes シークレットを作成

```bash
# Secrets Manager から AUTH Token を取得
export AWS_PROFILE=playground
REDIS_SECRET_ARN=$(terraform -chdir=environments/dev output -raw redis_secret_arn)
REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "$REDIS_SECRET_ARN" \
  --query SecretString --output text | jq -r '.auth_token')

# Kubernetes シークレットを作成
kubectl create secret generic redis-credentials \
  --from-literal=auth_token="$REDIS_AUTH_TOKEN" \
  -n app-production
```

### Step 4: Docker イメージを再ビルドしてデプロイ

```bash
# ECR にログイン
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com

# amd64 でビルド・プッシュ
cd apps/api
docker buildx build \
  --platform linux/amd64 \
  -t 202516977224.dkr.ecr.ap-northeast-1.amazonaws.com/sre-portfolio/api:latest \
  --push .

# マニフェストを適用して Pod を再起動
kubectl apply -f k8s/base/api/deployment.yaml
kubectl rollout restart deployment/api-service -n app-production

# 状態確認
kubectl get pods -n app-production -l app=api-service -w
```

**確認コマンド**:
```bash
# Pod が Running になっていることを確認
kubectl get pods -n app-production -l app=api-service

# ヘルスチェックが成功していることを確認
kubectl logs -n app-production -l app=api-service --tail=20
# 期待される出力: [GET] /health/ready ... 200
```

---

## 8. データベースマイグレーションコマンドエラー

**エラーメッセージ**:
```
error: Internal error occurred: error executing command in container:
failed to exec in container: failed to start exec "xxx":
OCI runtime exec failed: exec failed: unable to start container process:
exec: "/app/migrate": stat /app/migrate: no such file or directory: unknown
```

**原因**:
- Dockerfile で `/app/migrate` バイナリがビルドされていない
- コンテナには `/server` バイナリのみが存在
- マイグレーションは別の方法で実行する必要がある

**確認コマンド**:
```bash
# コンテナ内のファイル一覧を確認
API_POD=$(kubectl get pods -n app-production -l app=api-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n app-production ${API_POD} -- ls -la /app/
```

**解決方法（ConfigMap + psql Pod を使用）**:
```bash
# Step 1: マイグレーション SQL を ConfigMap として作成
kubectl create configmap migration-sql \
  --namespace=app-production \
  --from-file=apps/api/migrations/000001_create_users.up.sql \
  --from-file=apps/api/migrations/000002_create_tasks.up.sql

# Step 2: psql Pod を作成してマイグレーション実行
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

# Step 3: ログを確認
sleep 10
kubectl logs psql-migration -n app-production

# Step 4: クリーンアップ
kubectl delete pod psql-migration -n app-production
kubectl delete configmap migration-sql -n app-production

# Step 5: テーブル作成を確認
kubectl run psql-verify --rm -i --restart=Never \
  --image=postgres:15-alpine \
  --namespace=app-production \
  --env="PGPASSWORD=$(kubectl get secret db-credentials -n app-production -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h "$(kubectl get secret db-credentials -n app-production -o jsonpath='{.data.host}' | base64 -d)" \
  -U "$(kubectl get secret db-credentials -n app-production -o jsonpath='{.data.username}' | base64 -d)" \
  -d taskmanager -c "\dt"
```

**期待される出力**:
```
        List of relations
 Schema | Name  | Type  |  Owner
--------+-------+-------+---------
 public | tasks | table | dbadmin
 public | users | table | dbadmin
(2 rows)
```

**補足**:
- シェルエスケープの問題（PostgreSQL の `$$` ドルクォート構文）を回避するため、ConfigMap を使用
- 直接 `kubectl run` で SQL を渡そうとすると、シェルが `$` を変数展開しようとしてエラーになる

---

## エラーカテゴリ別サマリー

| カテゴリ | エラー数 | 主な原因 |
|---------|---------|---------|
| 設定・命名の誤り | 3件 | Output名やシークレット名のタイポ |
| AWSリソース競合 | 2件 | 削除待機中/既存リソースとの重複 |
| アーキテクチャ不一致 | 1件 | arm64でビルドしたイメージをamd64で実行 |
| プレースホルダー未置換 | 2件 | Kubernetesマニフェスト/ConfigMapの環境変数 |
| TLS/認証設定の不一致 | 1件 | ElastiCacheのTLS/AUTH要件とアプリ側設定の乖離 |
| マイグレーション | 1件 | コンテナ内にmigrateバイナリが存在しない |

---

## 予防策・ベストプラクティス

1. **Terraform Output 名は事前に確認**
   ```bash
   terraform output
   ```

2. **シークレット名は Terraform Output の ARN を使用**
   - ハードコードせず、常に `terraform output -raw xxx_secret_arn` を使用

3. **リソース削除時は完全削除を検討**
   ```bash
   aws secretsmanager delete-secret --force-delete-without-recovery
   ```

4. **Docker イメージは常に対象アーキテクチャを指定**
   ```bash
   docker buildx build --platform linux/amd64 ...
   ```

5. **マニフェストのプレースホルダーはデプロイ前に置換**
   - CI/CD パイプラインで自動置換するか、envsubst を使用

6. **ConfigMap/Secret の値はデプロイ前に確認**
   ```bash
   kubectl get configmap <name> -n <namespace> -o yaml
   kubectl get secret <name> -n <namespace> -o yaml
   ```

7. **AWS マネージドサービスの暗号化設定を確認**
   - ElastiCache: `transit_encryption_enabled` が true の場合、TLS 接続と AUTH Token が必須
   - RDS: `storage_encrypted` と SSL 接続設定を確認
   - アプリ側のクライアント設定がサーバー側の要件と一致しているか確認

8. **デプロイ前のチェックリスト**
   - [ ] Terraform output の確認
   - [ ] ConfigMap/Secret の値確認
   - [ ] Docker イメージのアーキテクチャ確認
   - [ ] マネージドサービスの接続要件（TLS/認証）確認

---

## デプロイ時のエラー発生順序（2026/01/16 17時台）

EKS アプリケーションデプロイ時に発生したエラーと解決の流れをタイムラインで示します。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 1: terraform apply 実行                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ ❌ エラー: Secrets Manager シークレット競合                                  │
│    - sre-portfolio/rds/credentials が削除スケジュール中                      │
│    - sre-portfolio/redis/auth-token が削除スケジュール中                     │
│ ❌ エラー: CloudWatch Log Group 既存                                         │
│    - /aws/eks/sre-portfolio-cluster/cluster が既に存在                      │
│                                                                             │
│ 🔧 解決: AWS CLI でリソース削除                                              │
│    aws secretsmanager delete-secret --force-delete-without-recovery         │
│    aws logs delete-log-group                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 2: terraform apply 再実行                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ ✅ 成功: インフラストラクチャ作成完了                                        │
│    - EKS クラスター                                                         │
│    - RDS PostgreSQL                                                         │
│    - ElastiCache Redis                                                      │
│    - Secrets Manager シークレット                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 3: kubectl apply 実行                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ ❌ Pod ステータス: ImagePullBackOff                                          │
│    エラー: no match for platform in manifest: not found                     │
│    原因: M1/M2 Mac (arm64) でビルドしたイメージを EKS (amd64) で実行         │
│                                                                             │
│ 🔧 解決: amd64 アーキテクチャでイメージ再ビルド                              │
│    docker buildx build --platform linux/amd64 --push                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 4: Pod 再起動後                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ ❌ Pod ステータス: CrashLoopBackOff                                          │
│    エラー: dial tcp: lookup REDIS_ENDPOINT_HERE: no such host               │
│    原因: ConfigMap の REDIS_HOST がプレースホルダーのまま                    │
│                                                                             │
│ 🔧 解決: ConfigMap を実際のエンドポイントで更新                              │
│    kubectl patch configmap api-config --type merge                          │
│    -p '{"data":{"REDIS_HOST":"master.xxx.cache.amazonaws.com"}}'            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 5: Pod 再起動後                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ ❌ Pod ステータス: CrashLoopBackOff                                          │
│    エラー: dial tcp 10.0.x.x:6379: i/o timeout                              │
│    原因: ElastiCache TLS 有効だがアプリは TLS 未対応                         │
│          AUTH Token 必要だがアプリに REDIS_PASSWORD 未設定                   │
│                                                                             │
│ 🔧 解決:                                                                     │
│    1. アプリコードに TLS 設定追加 (redis.go, config.go)                      │
│    2. K8s マニフェストに REDIS_PASSWORD, REDIS_TLS_ENABLED 追加             │
│    3. redis-credentials シークレット作成                                    │
│    4. Docker イメージ再ビルド・プッシュ                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 6: 最終デプロイ                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ ✅ Pod ステータス: Running (3/3)                                             │
│ ✅ ヘルスチェック: /health/live → 200 OK                                     │
│ ✅ ヘルスチェック: /health/ready → 200 OK                                    │
│                                                                             │
│ 🎉 デプロイ成功！                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### エラー解決に要した主なコマンド

```bash
# Step 1: Terraform リソース競合解決
aws secretsmanager delete-secret --secret-id "sre-portfolio/rds/credentials" --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id "sre-portfolio/redis/auth-token" --force-delete-without-recovery
aws logs delete-log-group --log-group-name "/aws/eks/sre-portfolio-cluster/cluster"
terraform apply

# Step 3: Docker イメージ amd64 再ビルド
aws ecr get-login-password | docker login --username AWS --password-stdin <ECR_URL>
docker buildx build --platform linux/amd64 -t <ECR_URL>/sre-portfolio/api:latest --push .
kubectl rollout restart deployment/api-service -n app-production

# Step 4: ConfigMap 更新
REDIS_HOST=$(terraform -chdir=environments/dev output -raw redis_primary_endpoint)
kubectl patch configmap api-config -n app-production --type merge -p "{\"data\":{\"REDIS_HOST\":\"${REDIS_HOST}\"}}"

# Step 5: Redis TLS/AUTH 設定
REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value --secret-id $(terraform output -raw redis_secret_arn) --query SecretString --output text | jq -r '.auth_token')
kubectl create secret generic redis-credentials --from-literal=auth_token="$REDIS_AUTH_TOKEN" -n app-production
# アプリコード修正後
docker buildx build --platform linux/amd64 -t <ECR_URL>/sre-portfolio/api:latest --push .
kubectl apply -f k8s/base/api/deployment.yaml
kubectl rollout restart deployment/api-service -n app-production
```

### 学んだ教訓

1. **インフラ削除→再作成時は残存リソースに注意**
   - Secrets Manager は 7 日間の削除待機期間がある
   - CloudWatch Log Group は手動削除が必要な場合がある

2. **M1/M2 Mac での開発時はアーキテクチャを意識**
   - 常に `--platform linux/amd64` を指定してビルド

3. **マネージドサービスの設定とアプリの設定を一致させる**
   - ElastiCache TLS 有効 → アプリも TLS 接続必須
   - AUTH Token 必要 → アプリに REDIS_PASSWORD 設定必須

4. **プレースホルダーは自動化で置換する**
   - CI/CD パイプラインで Terraform output を使用して自動置換
