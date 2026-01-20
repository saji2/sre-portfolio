# 運用設定ガイド

このドキュメントでは、SREポートフォリオプロジェクトの監視・ログ基盤の構築手順を記載します。

---

## Day 3: 監視・ログ基盤構築

### 概要

以下のコンポーネントをEKSクラスタにデプロイします：

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
- Terraform で monitoring モジュールがデプロイ済み（IAMロール、CloudWatch Log Groups）

### 1.2 クラスタ接続確認

```bash
# ノードの確認
kubectl get nodes

# 既存のPodの確認
kubectl get pods -n app-production
```

---

## 2. monitoring Namespace の作成

### 2.1 Namespaceマニフェスト作成

```bash
mkdir -p k8s/monitoring
```

`k8s/monitoring/namespace.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
    purpose: observability
```

### 2.2 Namespace適用

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

### 3.2 カスタム Values ファイルの作成

`k8s/monitoring/prometheus-stack-values.yaml`:
```yaml
# kube-prometheus-stack custom values
# For SRE Portfolio Project

# Grafana configuration
grafana:
  enabled: true
  adminPassword: "SrePortfolio2024!"
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  persistence:
    enabled: false
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6417
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 1860
        revision: 37
        datasource: Prometheus

# Prometheus configuration
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 1Gi
    # Disable persistent storage for dev environment
    # For production, enable EBS CSI Driver and use storageSpec
    storageSpec: {}
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

# Alertmanager configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 128Mi

# Node Exporter for node metrics
nodeExporter:
  enabled: true

# kube-state-metrics for Kubernetes object metrics
kubeStateMetrics:
  enabled: true

# Prometheus Operator
prometheusOperator:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Default scrape configs
defaultRules:
  create: true
  rules:
    alertmanager: true
    etcd: false
    configReloaders: true
    general: true
    k8s: true
    kubeApiserverAvailability: true
    kubeApiserverBurnrate: true
    kubeApiserverHistogram: true
    kubeApiserverSlos: true
    kubeControllerManager: false
    kubelet: true
    kubeProxy: false
    kubePrometheusGeneral: true
    kubePrometheusNodeRecording: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesStorage: true
    kubernetesSystem: true
    kubeSchedulerAlerting: false
    kubeSchedulerRecording: false
    kubeStateMetrics: true
    network: true
    node: true
    nodeExporterAlerting: true
    nodeExporterRecording: true
    prometheus: true
    prometheusOperator: true

# Disable components not available in EKS
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeEtcd:
  enabled: false
kubeProxy:
  enabled: false
```

### 3.3 Helm インストール

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 5m
```

> **注意:** `helm upgrade --install` を使用することで、新規インストールと更新の両方に対応できます。

### 3.4 デプロイ確認

```bash
# Podの確認
kubectl get pods -n monitoring

# Serviceの確認
kubectl get svc -n monitoring
```

### 3.5 Grafana アクセス情報の取得

```bash
# Grafana の外部 URL を取得
kubectl get svc kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# パスワードの確認
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
helm repo update aws
```

### 4.2 IAM ロール ARN の確認

```bash
cd environments/dev
terraform output fluent_bit_role_arn
```

### 4.3 カスタム Values ファイルの作成

`k8s/monitoring/fluent-bit-values.yaml`:
```yaml
# Fluent Bit configuration for CloudWatch Logs
# AWS for Fluent Bit Helm chart values

serviceAccount:
  create: true
  name: fluent-bit
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/sre-portfolio-fluent-bit-role

cloudWatchLogs:
  enabled: true
  region: ap-northeast-1
  logGroupName: "/aws/eks/sre-portfolio-cluster/application"
  logGroupTemplate: "/aws/eks/sre-portfolio-cluster/$kubernetes['namespace_name']"
  logStreamPrefix: "fb-"
  autoCreateGroup: true

firehose:
  enabled: false

kinesis:
  enabled: false

elasticsearch:
  enabled: false

input:
  tail:
    enabled: true
    tag: "kube.*"
    path: "/var/log/containers/*.log"
    parser: docker
    memBufLimit: 5MB
    skipLongLines: "On"
    refreshInterval: 10

filter:
  kubeURL: "https://kubernetes.default.svc:443"
  kubeCAFile: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  kubeTokenFile: "/var/run/secrets/kubernetes.io/serviceaccount/token"
  mergeLog: "On"
  mergeLogKey: "log_processed"
  keepLog: "On"
  k8sLoggingParser: "On"
  k8sLoggingExclude: "Off"

tolerations:
  - operator: Exists
    effect: NoSchedule

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 50m
    memory: 64Mi
```

> **注意:** `<AWS_ACCOUNT_ID>` を実際の AWS アカウント ID に置き換えてください。

### 4.4 Helm インストール

```bash
helm install fluent-bit aws/aws-for-fluent-bit \
  --namespace monitoring \
  -f k8s/monitoring/fluent-bit-values.yaml \
  --wait --timeout 5m
```

### 4.5 デプロイ確認

```bash
# Fluent Bit Podの確認（各ノードで1つずつ動作）
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
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-stack-kube-prom-alertmanager-0   2/2     Running   0          Xm
fluent-bit-aws-for-fluent-bit-xxxxx                      1/1     Running   0          Xm
fluent-bit-aws-for-fluent-bit-xxxxx                      1/1     Running   0          Xm
fluent-bit-aws-for-fluent-bit-xxxxx                      1/1     Running   0          Xm
prometheus-prometheus-stack-kube-prom-prometheus-0       2/2     Running   0          Xm
prometheus-stack-grafana-xxxxxxxxx-xxxxx                 3/3     Running   0          Xm
prometheus-stack-kube-prom-operator-xxxxxxxxx-xxxxx      1/1     Running   0          Xm
prometheus-stack-kube-state-metrics-xxxxxxxxx-xxxxx      1/1     Running   0          Xm
prometheus-stack-prometheus-node-exporter-xxxxx          1/1     Running   0          Xm
prometheus-stack-prometheus-node-exporter-xxxxx          1/1     Running   0          Xm
prometheus-stack-prometheus-node-exporter-xxxxx          1/1     Running   0          Xm
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

### 6.1 Prometheus Pod が Pending 状態になる

**症状:**
```bash
kubectl get pods -n monitoring
# prometheus-prometheus-stack-kube-prom-prometheus-0   0/2   Pending
```

**原因:**
EBS CSI Driver がインストールされていない、または StorageClass の設定が不正。

**確認方法:**
```bash
# PVC の状態確認
kubectl get pvc -n monitoring

# PVC のイベント確認
kubectl describe pvc -n monitoring
```

エラーメッセージ例:
```
Waiting for a volume to be created either by the external provisioner 'ebs.csi.aws.com'
or manually by the system administrator.
```

**解決方法:**

**オプション1: 永続化を無効にする（開発環境向け）**

`prometheus-stack-values.yaml` の `storageSpec` を空にする:
```yaml
prometheus:
  prometheusSpec:
    storageSpec: {}
```

その後、Helm upgrade を実行:
```bash
# Pending の PVC を削除
kubectl delete pvc -n monitoring <pvc-name>

# Helm upgrade
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/monitoring/prometheus-stack-values.yaml \
  --wait
```

**オプション2: EBS CSI Driver をインストールする（本番環境向け）**

```bash
# EKS アドオンとして EBS CSI Driver をインストール
aws eks create-addon \
  --cluster-name sre-portfolio-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn <EBS_CSI_DRIVER_ROLE_ARN>
```

### 6.2 Fluent Bit が CloudWatch Logs に書き込めない

**症状:**
```bash
kubectl logs -n monitoring <fluent-bit-pod>
# [error] [output:cloudwatch_logs:cloudwatch_logs.0] PutLogEvents API responded with error='AccessDeniedException'
```

**原因:**
IRSA (IAM Roles for Service Accounts) の設定が不正。

**確認方法:**
```bash
# ServiceAccount のアノテーション確認
kubectl get sa fluent-bit -n monitoring -o yaml

# IAM ロールの信頼ポリシー確認
aws iam get-role --role-name sre-portfolio-fluent-bit-role
```

**解決方法:**
1. Terraform の monitoring モジュールで OIDC プロバイダー URL が正しいか確認
2. IAM ロールの信頼ポリシーが正しい Namespace と ServiceAccount を指定しているか確認

### 6.3 Node Exporter が Pending 状態（ポート競合）

**症状:**
```bash
kubectl get pods -n monitoring
# kube-prometheus-stack-prometheus-node-exporter-xxxxx   0/1   Pending
```

**イベントログ:**
```bash
kubectl describe pod <node-exporter-pod> -n monitoring
# Warning  FailedScheduling  0/3 nodes are available: 1 node(s) didn't have free ports for the requested pod ports
```

**原因:**
複数の Prometheus スタックがインストールされており、既存の node-exporter がポート 9100 を使用している。

**確認方法:**
```bash
# Helm リリースの確認
helm list -n monitoring

# 出力例（複数のリリースがある場合）:
# NAME                  NAMESPACE   REVISION  STATUS
# kube-prometheus-stack monitoring  1         failed
# prometheus-stack      monitoring  2         deployed
```

**解決方法:**
古いリリースを削除して、新しいリリースを再インストール。

```bash
# 既存のリリースを全て削除
helm uninstall prometheus-stack -n monitoring
helm uninstall kube-prometheus-stack -n monitoring

# Pod が削除されるまで待機
sleep 10
kubectl get pods -n monitoring

# 新しいリリースをインストール
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 5m
```

### 6.4 Grafana LoadBalancer に EXTERNAL-IP が割り当てられない

**症状:**
```bash
kubectl get svc prometheus-stack-grafana -n monitoring
# EXTERNAL-IP が <pending> のまま
```

**原因:**
- AWS Load Balancer Controller がインストールされていない
- サブネットに適切なタグがない

**解決方法:**
```bash
# Service のイベント確認
kubectl describe svc prometheus-stack-grafana -n monitoring

# AWS Load Balancer Controller の確認
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
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f k8s/monitoring/prometheus-stack-values.yaml
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

- `kube_pod_status_phase` - Pod のステータス
- `kube_deployment_status_replicas` - Deployment のレプリカ数
- `kube_node_status_condition` - ノードの状態

### 8.2 ノードメトリクス (node-exporter)

- `node_cpu_seconds_total` - CPU 使用時間
- `node_memory_MemAvailable_bytes` - 利用可能メモリ
- `node_filesystem_avail_bytes` - ディスク空き容量

### 8.3 コンテナメトリクス (cAdvisor via kubelet)

- `container_cpu_usage_seconds_total` - コンテナ CPU 使用量
- `container_memory_usage_bytes` - コンテナメモリ使用量

---

## 9. ログ転送先

| ログ種別 | CloudWatch Log Group |
|---------|---------------------|
| アプリケーション (app-production) | `/aws/eks/sre-portfolio-cluster/app-production` |
| 監視系 (monitoring) | `/aws/eks/sre-portfolio-cluster/monitoring` |
| システム (kube-system) | `/aws/eks/sre-portfolio-cluster/kube-system` |

---

## 10. 実行記録

### 10.1 デプロイ日時

**実行日:** 2026-01-20

### 10.2 実行手順

#### Step 1: EKSクラスタ接続確認

```bash
kubectl cluster-info
# Kubernetes control plane is running at https://xxxxx.gr7.ap-northeast-1.eks.amazonaws.com
```

#### Step 2: monitoring Namespace 確認

```bash
kubectl get ns monitoring
# NAME         STATUS   AGE
# monitoring   Active   23h
```

> Namespace は既に存在していたため、作成をスキップ。

#### Step 3: Helm リポジトリの追加・更新

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

#### Step 4: kube-prometheus-stack のデプロイ

**初回デプロイ時にタイムアウトが発生:**
```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 10m

# Error: resource not ready, name: kube-prometheus-stack-prometheus-node-exporter, kind: DaemonSet
```

**原因調査:**
```bash
kubectl describe pod kube-prometheus-stack-prometheus-node-exporter-xxxxx -n monitoring
# Warning  FailedScheduling  0/3 nodes are available: 1 node(s) didn't have free ports for the requested pod ports
```

古い `prometheus-stack` リリースの node-exporter がポート 9100 を使用していた。

**解決:**
```bash
# 既存リリースを削除
helm uninstall prometheus-stack -n monitoring
helm uninstall kube-prometheus-stack -n monitoring

# 待機
sleep 10

# 再インストール
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/prometheus-stack-values.yaml \
  --wait --timeout 5m

# 成功
# NAME: kube-prometheus-stack
# LAST DEPLOYED: Tue Jan 20 17:26:31 2026
# STATUS: deployed
```

#### Step 5: デプロイ確認

```bash
kubectl get pods -n monitoring

# NAME                                                        READY   STATUS    RESTARTS   AGE
# alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          46s
# fluent-bit-aws-for-fluent-bit-766cd                         1/1     Running   0          26h
# fluent-bit-aws-for-fluent-bit-8mkfs                         1/1     Running   0          26h
# fluent-bit-aws-for-fluent-bit-gnww7                         1/1     Running   0          26h
# kube-prometheus-stack-grafana-848fc4f7cf-xmmz6              3/3     Running   0          52s
# kube-prometheus-stack-kube-state-metrics-6f7cc7689c-gm9zj   1/1     Running   0          52s
# kube-prometheus-stack-operator-74c9dd77c8-wt72j             1/1     Running   0          52s
# kube-prometheus-stack-prometheus-node-exporter-jd5dl        1/1     Running   0          52s
# kube-prometheus-stack-prometheus-node-exporter-phwqj        1/1     Running   0          52s
# kube-prometheus-stack-prometheus-node-exporter-t4zzv        1/1     Running   0          52s
# prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          45s
```

### 10.3 最終確認結果

| コンポーネント | 状態 | Pod数 |
|--------------|------|-------|
| Prometheus | Running | 1 |
| Grafana | Running | 1 |
| Alertmanager | Running | 1 |
| Node Exporter | Running | 3 (各ノード) |
| kube-state-metrics | Running | 1 |
| Prometheus Operator | Running | 1 |
| Fluent Bit | Running | 3 (各ノード) |

### 10.4 Grafana アクセス情報

| 項目 | 値 |
|------|---|
| URL | http://k8s-monitori-kubeprom-90e861fc74-f29b4147cd4a1bc8.elb.ap-northeast-1.amazonaws.com |
| ユーザー | admin |
| パスワード | SrePortfolio2024! |

---

## 11. 次のステップ

- [ ] アプリケーション用 ServiceMonitor の作成
- [ ] Golden Signals ダッシュボードの作成
- [ ] Alertmanager のアラートルール設定
- [ ] SLI/SLO ダッシュボードの作成
