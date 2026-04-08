# cloudrun-hono-jobs-terraform

Cloud Run Service (Hono API) + Cloud Run Jobs + Cloud Scheduler を Terraform で管理するテンプレートリポジトリ。

## アーキテクチャ

```mermaid
graph TB
    Client[Client] -->|HTTPS| GW[API Gateway<br/>IAM認証]
    GW -->|invoke| Service[Cloud Run Service<br/>Hono API]
    Scheduler[Cloud Scheduler<br/>Cron] -->|invoke| Job[Cloud Run Jobs<br/>Batch処理]

    subgraph "Artifact Registry"
        AppImage[hono-api image]
        JobImage[cloud-run-job image]
    end

    Service -.->|pull| AppImage
    Job -.->|pull| JobImage
```

## ディレクトリ構成

```
.
├── app/                  # Cloud Run Service (Hono API)
│   ├── src/
│   │   ├── index.ts      # エントリポイント
│   │   └── routes/       # APIルート
│   ├── Dockerfile
│   └── package.json
├── jobs/                 # Cloud Run Jobs (バッチ処理)
│   ├── src/
│   │   └── index.ts      # ジョブエントリポイント
│   ├── Dockerfile
│   └── package.json
├── terraform/            # インフラ定義
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── openapi.yaml.tpl
├── docker-compose.yml
└── Makefile
```

## セットアップ

### 前提条件

- Node.js 24+
- Google Cloud SDK (`gcloud`)
- Terraform
- direnv（推奨）

### 手順

```bash
# 1. 環境ファイルの作成
make setup
# .env を編集して PREFIX と PROJECT_ID を設定

# 2. direnv を有効化
direnv allow

# 3. ローカル依存関係のインストール
make local-install

# 4. Terraform ステート用 GCS バケットを作成（初回のみ）
make setup-backend

# 5. Terraform 初期化
make init

# 6. デプロイ（Registry作成 → ビルド → Terraform apply）
make deploy
```

### 更新

```bash
# コード変更後、再デプロイ
make deploy

# API のみ更新
make deploy-app

# Job のみ更新
make deploy-job

# Terraform の変更内容を事前確認
make plan
```

### 削除

```bash
# Terraform 管理リソースを削除
make destroy
```

> **注意:** `make destroy` は Cloud Run Service / Job / API Gateway / Scheduler / Service Account など Terraform で管理しているリソースをすべて削除します。以下は Terraform 管理外のため手動削除が必要です：
>
> | リソース | 削除コマンド | 備考 |
> |---|---|---|
> | Terraform ステート用 GCS バケット | `gcloud storage rm -r gs://PREFIX-tfstate` | ステート保存先のため Terraform 管理外 |
> | 有効化した GCP API | - | `disable_on_destroy = false` のため無効化されない（残っていても課金なし） |

## 開発

### ローカル開発（API）

```bash
make local
# http://localhost:8080 でHono APIが起動
```

### Docker Compose

```bash
docker compose up
```

## Makefile コマンド

| コマンド | 説明 |
|---|---|
| `make setup` | 環境ファイルの初期生成 |
| `make setup-backend` | Terraform ステート用 GCS バケット作成（初回のみ） |
| `make init` | Terraform 初期化 |
| `make deploy` | 全体デプロイ（API + Job） |
| `make deploy-app` | API のみデプロイ |
| `make deploy-job` | Job のみデプロイ |
| `make build-app` | API イメージのビルド |
| `make build-job` | Job イメージのビルド |
| `make plan` | Terraform plan |
| `make apply` | Terraform apply |
| `make destroy` | 全リソース削除 |
| `make local` | ローカルAPI起動 |
| `make run-job` | Cloud Run Job を手動実行 |
| `make test-health` | ヘルスチェック |
| `make test-hello` | hello エンドポイントテスト |
| `make test-webhook` | webhook エンドポイントテスト |
| `make outputs` | Terraform outputs 表示 |

## Secret Manager

`terraform.tfvars` または環境変数でシークレットを定義すると、Cloud Run Service / Job の両方に環境変数として自動マウントされます。

```hcl
# terraform.tfvars
secret_names = ["DATABASE_URL", "API_KEY"]

secret_values = {
  DATABASE_URL = "postgresql://user:pass@host:5432/db"
  API_KEY      = "sk-xxxx"
}
```

アプリからは通常の環境変数としてアクセスできます。

```typescript
const dbUrl = process.env.DATABASE_URL;
```

> **注意:** `terraform.tfvars` にはシークレットの初期値が平文で含まれます。`.gitignore` に追加してリポジトリにコミットしないでください。

## ルーティングと認証

全トラフィックは API Gateway 経由。Cloud Run への直接アクセスは遮断されています。

| パス | Gateway認証 | アプリ認証 | 用途 |
|---|---|---|---|
| `/health` | なし | なし | ヘルスチェック |
| `/api/*` | IAM認証 | なし | 内部API（社内ツール等） |
| `/webhook/*` | なし | APIキー（`x-api-key`） | 外部連携（Slack, GAS等） |

### Webhook の呼び出し方

```bash
curl -X POST \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event": "test"}' \
  https://GATEWAY_URL/webhook/example
```

`WEBHOOK_API_KEY` は Secret Manager で管理されます（`terraform.tfvars` で設定）。

## API エンドポイント追加

[app/src/routes/](app/src/routes/) にルートファイルを追加し、[app/src/index.ts](app/src/index.ts) で `app.route()` に登録。API Gateway 経由で公開する場合は [terraform/openapi.yaml.tpl](terraform/openapi.yaml.tpl) にもパスを追加。

認証なしパスは OpenAPI 定義で `security: []` を指定し、アプリ側でミドルウェアによる検証を行ってください。

## GitHub Actions デプロイ

Actions タブから手動で実行できます。デプロイ対象を選択可能：

| 選択肢 | 動作 |
|---|---|
| `all` | API + Job の全体デプロイ |
| `app` | API のみビルド＆デプロイ |
| `job` | Job のみビルド＆デプロイ |

### 事前設定

リポジトリの Settings > Secrets and variables > Actions で以下を設定：

**Secrets:**

| 名前 | 値 |
|---|---|
| `GCP_SA_KEY` | デプロイ用サービスアカウントキー（JSON） |

**Variables:**

| 名前 | 値 |
|---|---|
| `PREFIX` | リソース名プレフィックス |

> `PROJECT_ID` は `GCP_SA_KEY` から自動取得されます。その他の設定値（リージョン、イメージ名等）はワークフロー内のデフォルト値を使用します。

## Job 追加

[jobs/src/index.ts](jobs/src/index.ts) の `switch` 文に新しいケースを追加。Terraform で新しい `google_cloud_run_v2_job` リソースと `google_cloud_scheduler_job` を定義してスケジュール設定。
