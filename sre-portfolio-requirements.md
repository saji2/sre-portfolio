# SREポートフォリオプロジェクト - 要件定義

## プロジェクト概要

**目的**: AWS EKSを活用したSRE業務のスキルを実証するポートフォリオ作成  
**期間**: 28日間（開発3日 + 運用演習25日）  
**対象**: SRE案件獲得のための実績作り

---

## プロジェクトスケジュール

### フェーズ1: 開発期間（3日間）
- Day 1: インフラ構築（Terraform + EKS）
- Day 2: アプリケーションデプロイ + CI/CD構築
- Day 3: 監視・ログ基盤構築

### フェーズ2: 運用演習期間（25日間）
- Week 1 (Day 4-10): 監視・アラート設定の最適化
- Week 2 (Day 11-17): 障害シナリオテスト（Chaos Engineering）
- Week 3 (Day 18-24): パフォーマンスチューニング・スケーリング演習
- Week 4 (Day 25-28): ドキュメント整備・ポートフォリオまとめ

---

## アプリケーション要件

### 選定サービス: タスク管理Webアプリケーション

**理由**:
- 3日で実装可能なシンプルさ
- マイクロサービス化しやすい構造
- 負荷テスト・障害対応の演習に適している
- CRUD操作で様々なSREシナリオを再現可能

### 機能要件

#### 最小限の機能（3日で実装）
1. **ユーザー認証**
   - ログイン/ログアウト
   - JWT認証

2. **タスク管理**
   - タスク作成・読み取り・更新・削除（CRUD）
   - タスクのステータス管理（TODO/IN_PROGRESS/DONE）
   - タスクの優先度設定

3. **API機能**
   - RESTful API
   - ヘルスチェックエンドポイント

### 非機能要件（SRE観点）

#### 可用性
- **目標**: 99.9% uptime
- Multi-AZ構成
- Auto Scaling設定
- ヘルスチェック・自動復旧

#### パフォーマンス
- **レスポンスタイム**: 95パーセンタイルで500ms以下
- **スループット**: 100 req/sec以上
- Redis キャッシング

#### 監視・可観測性
- **メトリクス**: Prometheus + Grafana
- **ログ**: Fluent Bit → CloudWatch Logs
- **トレーシング**: AWS X-Ray（オプション）
- **アラート**: CloudWatch Alarms + SNS

#### セキュリティ
- VPC内プライベートサブネット配置
- Security Group による最小権限
- Secrets Manager でシークレット管理
- IAM Roles for Service Accounts (IRSA)

---

## 技術スタック

### インフラストラクチャ

#### AWS サービス
- **EKS**: Kubernetes クラスタ（1.28以降）
- **VPC**: Multi-AZ構成（3 AZ）
- **RDS**: PostgreSQL（Multi-AZ）
- **ElastiCache**: Redis
- **ALB**: Application Load Balancer
- **ECR**: コンテナレジストリ
- **CloudWatch**: ログ・メトリクス・アラート
- **Secrets Manager**: シークレット管理
- **SNS**: アラート通知

#### IaC
- **Terraform**: インフラ構築
- **Helm**: Kubernetesアプリケーション管理

### アプリケーション

#### マイクロサービス構成
1. **API Service** (Go or Python FastAPI)
   - RESTful API
   - ビジネスロジック
   - 認証・認可

2. **Frontend Service** (React or Vue.js)
   - SPA
   - タスク管理UI

3. **Worker Service** (オプション)
   - 非同期タスク処理
   - メール送信など

#### データベース
- **PostgreSQL**: メインデータストア
- **Redis**: セッション・キャッシュ

### 監視・運用ツール

#### Kubernetes ネイティブ
- **Prometheus**: メトリクス収集
- **Grafana**: ダッシュボード
- **Kube-state-metrics**: Kubernetesメトリクス
- **Metrics Server**: HPA用メトリクス

#### CI/CD
- **GitHub Actions**: CI/CDパイプライン
- **ArgoCD** (オプション): GitOps デプロイ

#### Chaos Engineering
- **Chaos Mesh**: 障害注入ツール
- **k6** or **Locust**: 負荷テストツール

---

## SRE演習シナリオ（25日間）

### Week 1: 監視基盤の構築と最適化

#### Day 4-5: メトリクス・ダッシュボード構築
- [ ] Prometheus + Grafana セットアップ
- [ ] Golden Signals ダッシュボード作成
  - Latency（レイテンシ）
  - Traffic（トラフィック）
  - Errors（エラー率）
  - Saturation（飽和度）
- [ ] カスタムメトリクス実装

#### Day 6-7: ログ集約・分析
- [ ] Fluent Bit デプロイ
- [ ] CloudWatch Logs Insights クエリ作成
- [ ] エラーログアラート設定

#### Day 8-10: アラート設定
- [ ] SLI/SLO定義
- [ ] CloudWatch Alarms 設定
- [ ] PagerDuty/Slack 通知連携
- [ ] Runbook 作成

### Week 2: 障害対応演習（Chaos Engineering）

#### Day 11-12: Pod障害シナリオ
- [ ] Pod Kill テスト
- [ ] Pod の自動復旧確認
- [ ] ログ・メトリクス分析
- [ ] インシデントレポート作成

#### Day 13-14: ネットワーク障害シナリオ
- [ ] Network Latency 注入
- [ ] Network Partition テスト
- [ ] タイムアウト設定の検証
- [ ] リトライロジックの確認

#### Day 15-16: リソース枯渇シナリオ
- [ ] CPU/Memory Stress テスト
- [ ] OOMKiller 動作確認
- [ ] Resource Limits 調整
- [ ] HPA 動作検証

#### Day 17: データベース障害シナリオ
- [ ] RDS フェイルオーバーテスト
- [ ] 接続プール設定の最適化
- [ ] バックアップ・リストア演習

### Week 3: パフォーマンスチューニング

#### Day 18-19: 負荷テスト
- [ ] k6/Locust でシナリオ作成
- [ ] ベースライン測定
- [ ] ボトルネック特定
- [ ] パフォーマンスレポート作成

#### Day 20-21: スケーリング最適化
- [ ] HPA設定チューニング
- [ ] Cluster Autoscaler 設定
- [ ] スケールアウト/インテスト
- [ ] コスト最適化分析

#### Day 22-23: キャッシング戦略
- [ ] Redis キャッシュ実装
- [ ] キャッシュヒット率測定
- [ ] キャッシュ無効化戦略
- [ ] パフォーマンス改善測定

#### Day 24: セキュリティ強化
- [ ] Pod Security Standards 適用
- [ ] Network Policy 設定
- [ ] Secrets ローテーション
- [ ] 脆弱性スキャン（Trivy）

### Week 4: ドキュメント整備

#### Day 25-26: 運用ドキュメント作成
- [ ] アーキテクチャ図作成
- [ ] Runbook 整備
- [ ] インシデント対応手順書
- [ ] 監視ダッシュボード説明

#### Day 27-28: ポートフォリオまとめ
- [ ] README.md 作成
- [ ] 実施した演習のまとめ
- [ ] スクリーンショット・グラフ収集
- [ ] GitHub リポジトリ公開準備

---

## 成果物

### コードリポジトリ
1. **Infrastructure Repository**
   - Terraform コード
   - Kubernetes マニフェスト
   - Helm Charts

2. **Application Repository**
   - アプリケーションコード
   - Dockerfile
   - CI/CD設定

### ドキュメント
1. **アーキテクチャドキュメント**
   - システム構成図
   - ネットワーク図
   - データフロー図

2. **運用ドキュメント**
   - Runbook
   - インシデント対応手順
   - 監視・アラート設定

3. **演習レポート**
   - 各週の実施内容
   - 障害シナリオと対応
   - パフォーマンスチューニング結果
   - 学んだこと・改善点

### ダッシュボード・メトリクス
- Grafana ダッシュボード（スクリーンショット）
- SLI/SLO達成状況
- パフォーマンステスト結果

---

## コスト見積もり（月額）

### AWS リソース
- **EKS クラスタ**: $73/月
- **EC2 (ワーカーノード)**: t3.medium × 3 = $100/月
- **RDS**: db.t3.micro = $15/月
- **ElastiCache**: cache.t3.micro = $12/月
- **ALB**: $20/月
- **その他**: $30/月

**合計**: 約 $250/月（28日間で約$230）

### コスト削減策
- スポットインスタンス活用
- 夜間・週末のリソース停止
- 演習終了後のリソース削除

---

## 差別化ポイント（SRE案件獲得のため）

### 1. 実践的な障害対応経験
- Chaos Engineering による実際の障害シナリオ
- インシデントレポートで対応プロセスを明示

### 2. データドリブンな改善
- メトリクスに基づくチューニング
- Before/After のパフォーマンス比較

### 3. 自動化・IaC
- Terraform によるインフラコード化
- CI/CD パイプライン構築

### 4. 包括的な監視
- Golden Signals 実装
- SLI/SLO 定義と測定

### 5. ドキュメント品質
- 詳細な Runbook
- 再現可能な手順書

---

## 次のステップ

1. **技術スタック確定**
   - アプリケーション言語の選択（Go推奨）
   - フロントエンド技術の選択

2. **リポジトリ作成**
   - GitHub リポジトリ作成
   - ディレクトリ構造設計

3. **Day 1 開始**
   - Terraform でVPC/EKS構築
   - 基本的なネットワーク設定
