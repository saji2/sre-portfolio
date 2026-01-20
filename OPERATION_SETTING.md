# 運用設定ガイド - 監視・ログ基盤構築

このドキュメントでは、SREポートフォリオプロジェクトの監視・ログ基盤の構築手順を記載します。

---

## Quick Start

以下のコマンドを順番に実行することで、監視基盤を構築できます。

### 前提条件
- EKSクラスタが稼働していること
- kubectlがクラスタに接続できること
- Helmがインストールされていること

### Step 1: Namespace 作成

```bash
kubectl apply -f k8s/monitoring/namespace.yaml
```

### Step 2: kube-prometheus-stack デプロイ

```bash
# Helm リポジトリ追加
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# デプロイ
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 5m
```

### Step 3: Fluent Bit デプロイ

```bash
# Helm リポジトリ追加
helm repo add aws https://aws.github.io/eks-charts
helm repo update

# AWS アカウント ID を取得して values ファイルを更新
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/monitoring/fluent-bit-values.yaml

# デプロイ
helm upgrade --install fluent-bit aws/aws-for-fluent-bit \
  --namespace monitoring \
  --values k8s/monitoring/fluent-bit-values.yaml \
  --wait --timeout 5m
```

### Step 4: 動作確認

```bash
# Pod 確認
kubectl get pods -n monitoring

# Grafana URL 取得
kubectl get svc kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo

# Grafana パスワード取得
kubectl get secrets kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

**Grafana アクセス情報:**
- URL: `http://<EXTERNAL-IP>`
- ユーザー: `admin`
- パスワード: `SrePortfolio2024!`

---

## 概要

| コンポーネント | 説明 | デプロイ方法 |
|--------------|------|------------|
| Prometheus | メトリクス収集・保存 | Helm (kube-prometheus-stack) |
| Grafana | ダッシュボード・可視化 | Helm (kube-prometheus-stack) |
| Alertmanager | アラート管理 | Helm (kube-prometheus-stack) |
| kube-state-metrics | Kubernetesオブジェクトメトリクス | Helm (kube-prometheus-stack) |
| node-exporter | ノードメトリクス | Helm (kube-prometheus-stack) |
| Fluent Bit | ログ収集・転送 | Helm (aws-for-fluent-bit) |

---

## 1. 事前準備

### 1.1 前提条件

- EKSクラスタが稼働していること
- kubectlがクラスタに接続できること
- Helmがインストールされていること
- Terraform で monitoring モジュールがデプロイ済み

### 1.2 クラスタ接続確認

```bash
kubectl get nodes
kubectl get pods -n app-production
```

---

## 2. monitoring Namespace の作成

```bash
kubectl apply -f k8s/monitoring/namespace.yaml
```

---

## 3. kube-prometheus-stack のデプロイ

### 3.1 Helm リポジトリの追加

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 3.2 デプロイ

Values ファイル: `k8s/monitoring/prometheus-stack-values.yaml`

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 5m
```

> `helm upgrade --install` を使用することで、新規インストールと更新の両方に対応できます。

### 3.3 デプロイ確認

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

### 3.4 Grafana アクセス情報の取得

```bash
# Grafana URL
kubectl get svc kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo

# パスワード
kubectl get secrets kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

**アクセス情報:**
- URL: `http://<EXTERNAL-IP>`
- ユーザー: `admin`
- パスワード: `SrePortfolio2024!`（values.yaml で設定）

---

## 4. Fluent Bit のデプロイ

### 4.1 Helm リポジトリの追加

```bash
helm repo add aws https://aws.github.io/eks-charts
helm repo update
```

### 4.2 Values ファイルの更新

Values ファイル: `k8s/monitoring/fluent-bit-values.yaml`

`<AWS_ACCOUNT_ID>` を実際の AWS アカウント ID に置き換えてください：

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i.bak "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" k8s/monitoring/fluent-bit-values.yaml
```

### 4.3 デプロイ

```bash
helm upgrade --install fluent-bit aws/aws-for-fluent-bit \
  --namespace monitoring \
  --values k8s/monitoring/fluent-bit-values.yaml \
  --wait --timeout 5m
```

### 4.4 デプロイ確認

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=aws-for-fluent-bit
```

---

## 5. デプロイ後の確認

### 5.1 全コンポーネントの確認

```bash
kubectl get pods -n monitoring
```

期待される出力:
```
NAME                                                        READY   STATUS    RESTARTS   AGE
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          Xm
fluent-bit-aws-for-fluent-bit-xxxxx                         1/1     Running   0          Xm
kube-prometheus-stack-grafana-xxxxx                         3/3     Running   0          Xm
kube-prometheus-stack-kube-state-metrics-xxxxx              1/1     Running   0          Xm
kube-prometheus-stack-operator-xxxxx                        1/1     Running   0          Xm
kube-prometheus-stack-prometheus-node-exporter-xxxxx        1/1     Running   0          Xm
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          Xm
```

### 5.2 ServiceMonitor の確認

```bash
kubectl get servicemonitors -n monitoring
```

### 5.3 Grafana ダッシュボードの確認

1. Grafana URL にブラウザでアクセス
2. admin / SrePortfolio2024! でログイン
3. 左メニュー → Dashboards → Browse
4. 以下のダッシュボードが利用可能:
   - Kubernetes / Compute Resources / Cluster
   - Kubernetes / Compute Resources / Namespace (Pods)
   - Node Exporter Full

---

## 6. トラブルシューティング

### 6.1 Prometheus Pod が Pending 状態

**症状:**
```bash
kubectl get pods -n monitoring
# prometheus-kube-prometheus-stack-prometheus-0   0/2   Pending
```

**原因:** EBS CSI Driver がインストールされていない

**解決方法（開発環境）:**
`prometheus-stack-values.yaml` の `storageSpec` を空にする:
```yaml
prometheus:
  prometheusSpec:
    storageSpec: {}
```

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml
```

### 6.2 Fluent Bit が CloudWatch Logs に書き込めない

**症状:**
```bash
kubectl logs -n monitoring <fluent-bit-pod>
# [error] PutLogEvents API responded with error='AccessDeniedException'
```

**解決方法:**
1. ServiceAccount のアノテーション確認:
   ```bash
   kubectl get sa fluent-bit -n monitoring -o yaml
   ```
2. IAM ロールの ARN が正しいか確認

### 6.3 Node Exporter が Pending 状態（ポート競合）

**症状:**
```bash
kubectl describe pod <node-exporter-pod> -n monitoring
# Warning  FailedScheduling  0/3 nodes are available: 1 node(s) didn't have free ports
```

**原因:** 複数の Prometheus スタックがインストールされている

**解決方法:**
```bash
# 既存のリリースを確認
helm list -n monitoring

# 古いリリースを削除
helm uninstall <old-release-name> -n monitoring

# 再インストール
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 5m
```

### 6.4 Grafana LoadBalancer に EXTERNAL-IP が割り当てられない

**症状:**
```bash
kubectl get svc kube-prometheus-stack-grafana -n monitoring
# EXTERNAL-IP が <pending> のまま
```

**解決方法:**
```bash
kubectl describe svc kube-prometheus-stack-grafana -n monitoring
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## 7. Helm リリースの管理

### 7.1 リリース一覧

```bash
helm list -n monitoring
```

### 7.2 設定の更新

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml
```

### 7.3 アンインストール

```bash
# kube-prometheus-stack の削除
helm uninstall kube-prometheus-stack -n monitoring

# Fluent Bit の削除
helm uninstall fluent-bit -n monitoring

# CRD の削除（必要に応じて）
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com
kubectl delete crd alertmanagers.monitoring.coreos.com
kubectl delete crd podmonitors.monitoring.coreos.com
kubectl delete crd probes.monitoring.coreos.com
kubectl delete crd prometheusagents.monitoring.coreos.com
kubectl delete crd prometheuses.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd scrapeconfigs.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd thanosrulers.monitoring.coreos.com
```

---

## 8. 収集されるメトリクス

### 8.1 Kubernetes メトリクス (kube-state-metrics)

| メトリクス | 説明 |
|-----------|------|
| `kube_pod_status_phase` | Pod のステータス |
| `kube_deployment_status_replicas` | Deployment のレプリカ数 |
| `kube_node_status_condition` | ノードの状態 |

### 8.2 ノードメトリクス (node-exporter)

| メトリクス | 説明 |
|-----------|------|
| `node_cpu_seconds_total` | CPU 使用時間 |
| `node_memory_MemAvailable_bytes` | 利用可能メモリ |
| `node_filesystem_avail_bytes` | ディスク空き容量 |

### 8.3 コンテナメトリクス (cAdvisor via kubelet)

| メトリクス | 説明 |
|-----------|------|
| `container_cpu_usage_seconds_total` | コンテナ CPU 使用量 |
| `container_memory_usage_bytes` | コンテナメモリ使用量 |

---

## 9. ログ転送先

| ログ種別 | CloudWatch Log Group |
|---------|---------------------|
| アプリケーション | `/aws/eks/sre-portfolio-cluster/app-production` |
| 監視系 | `/aws/eks/sre-portfolio-cluster/monitoring` |
| システム | `/aws/eks/sre-portfolio-cluster/kube-system` |

---

## 10. 次のステップ

- [ ] アプリケーション用 ServiceMonitor の作成
- [ ] Golden Signals ダッシュボードの作成
- [ ] Alertmanager のアラートルール設定
- [ ] SLI/SLO ダッシュボードの作成
