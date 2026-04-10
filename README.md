# cloudrun-hono-jobs-terraform

Google Cloud 上で Hono ベースの内部サービスを動かすためのテンプレートリポジトリ。以下を Terraform で一括管理します：

- **API Gateway + Cloud Run Service** — IAM認証 / APIキー認証 / 認証なし をパスごとに切り替え可能な API
- **Cloud Run Jobs + Cloud Scheduler** — 定期バッチ処理
- **IAP + Cloud Run Service** — Google認証で保護された Web ページ
- **Secret Manager** — シークレットを環境変数として自動マウント
- **Artifact Registry** — コンテナイメージ保管

## アーキテクチャ

```mermaid
graph TB
    Client[Client] -->|HTTPS| GW[API Gateway<br/>IAM認証/APIキー]
    User[Browser User] -->|HTTPS| IAP[IAP<br/>Google認証]
    GW -->|invoke| Service[Cloud Run Service<br/>Hono API]
    IAP -->|invoke| Pages[Cloud Run Service<br/>Pages]
    Scheduler[Cloud Scheduler<br/>Cron] -->|invoke| Job[Cloud Run Jobs<br/>Batch処理]

    subgraph "Artifact Registry"
        AppImage[hono-api image]
        JobImage[cloud-run-job image]
        PagesImage[pages image]
    end

    Service -.->|pull| AppImage
    Job -.->|pull| JobImage
    Pages -.->|pull| PagesImage
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
├── pages/                # Cloud Run Service (IAP保護ページ)
│   ├── src/
│   │   └── index.ts      # ページエントリポイント
│   ├── Dockerfile
│   └── package.json
├── terraform/            # インフラ定義
│   ├── main.tf           # コア（Cloud Run, Jobs, Scheduler, Registry, IAM）
│   ├── gateway.tf        # API Gateway（削除可能）
│   ├── secrets.tf        # Secret Manager（削除可能）
│   ├── pages.tf          # IAP保護Pages（削除可能）
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
# GCS を使わずローカルステートで試す場合は代わりに: make init-local

# 5. デプロイ用サービスアカウントを作成（GitHub Actions 用・初回のみ）
make setup-deploy-sa
# 出力された deploy-sa-key.json の内容を GitHub Actions の Secret (GCP_SA_KEY) に設定
# 設定後、ローカルのキーファイルを削除: rm deploy-sa-key.json

# 6. Terraform 初期化
make init

# 7. デプロイ（Registry作成 → 各イメージビルド → Terraform apply）
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

# Pages のみ更新
make deploy-pages

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
> | デプロイ用サービスアカウント | `gcloud iam service-accounts delete PREFIX-deploy-sa@PROJECT_ID.iam.gserviceaccount.com` | Terraform 実行元のため管理外 |
> | 有効化した GCP API | - | `disable_on_destroy = false` のため無効化されない（残っていても課金なし） |

## 開発

### ローカル開発

```bash
# API を起動（ホットリロード）
make local
# http://localhost:8080 でHono APIが起動

# Job を単発実行
make local-job

# Pages を起動（ホットリロード）
make local-pages
# http://localhost:8080 で Pages が起動
```

### Docker Compose（API + Job + Pages をまとめて実行）

```bash
docker compose up
# API:   http://localhost:8080
# Pages: http://localhost:8081
# Job は起動時に一度だけ実行されて終了
```

## Makefile コマンド

| コマンド | 説明 |
|---|---|
| `make setup` | 環境ファイルの初期生成 |
| `make setup-backend` | Terraform ステート用 GCS バケット作成（初回のみ） |
| `make setup-deploy-sa` | デプロイ用 SA 作成＆キー出力（初回のみ） |
| `make init` | Terraform 初期化（GCS バックエンド） |
| `make init-local` | Terraform 初期化（ローカルステート・GCS バケット不要） |
| `make deploy` | 全体デプロイ（API + Job + Pages） |
| `make deploy-app` | API のみデプロイ |
| `make deploy-job` | Job のみデプロイ |
| `make deploy-pages` | Pages のみデプロイ |
| `make build-app` | API イメージのビルド |
| `make build-job` | Job イメージのビルド |
| `make build-pages` | Pages イメージのビルド |
| `make plan` | Terraform plan |
| `make apply` | Terraform apply |
| `make destroy` | 全リソース削除 |
| `make local` | ローカルAPI起動 |
| `make local-job` | ローカルJob実行 |
| `make local-pages` | ローカルPages起動 |
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

サービスごとに認証方式が異なります。

### API サービス（`app/`）

API Gateway 経由でのみアクセス可能。Cloud Run は `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` で直接アクセスを遮断しています。

| パス | Gateway認証 | アプリ認証 | 用途 |
|---|---|---|---|
| `/health` | なし | なし | ヘルスチェック |
| `/api/*` | IAM認証 | なし | 内部API（社内ツール等） |
| `/webhook/*` | なし | APIキー（`x-api-key`） | 外部連携（Slack, GAS等） |

### Pages サービス（`pages/`）

別の Cloud Run サービスとして独立し、IAP (Identity-Aware Proxy) で保護されます。詳細は後述の「Pages (IAP 保護)」を参照。

### Webhook の呼び出し方

```bash
curl -X POST \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event": "test"}' \
  https://GATEWAY_URL/webhook/example
```

`WEBHOOK_API_KEY` は Secret Manager で管理されます（`terraform.tfvars` で設定）。

## Pages (IAP 保護)

API / Webhook とは別の Cloud Run サービスとして、Identity-Aware Proxy で保護された Web ページを配信します。Google アカウントでログインしたユーザーのうち、許可されたプリンシパルのみアクセス可能です。

### アクセス許可

`terraform.tfvars` で IAP アクセスを許可するプリンシパルを指定します。

```hcl
# terraform.tfvars
iap_members = [
  "user:alice@example.com",
  "group:team@example.com",
  "domain:example.com",
]
```

各プリンシパルに `roles/iap.httpsResourceAccessor`（IAP-secured Web App User）が付与されます。

### 動作

- Cloud Run URL（`terraform output pages_url` で確認）にブラウザでアクセス
- Google のログイン画面にリダイレクト
- 許可されたユーザーのみログイン後にページが表示される
- IAP が認証済みユーザーの情報を `x-goog-authenticated-user-email` ヘッダーで渡す
- [pages/src/index.ts](pages/src/index.ts) はそのヘッダーを読み取って画面に表示

### 初回セットアップ（OAuth 同意画面 / クライアント）

IAP を使うには、プロジェクトに **OAuth 同意画面（Brand）** と **OAuth クライアント** が必要です。アカウント種別に応じて手順が異なります。

#### ケース1: Google Workspace ユーザー（Internal 公開）

Workspace 組織内のみでの利用なら Terraform で自動化できます。

`terraform.tfvars` に以下を追加：

```hcl
iap_support_email = "your-email@your-workspace-domain.com"
```

`make apply` を実行すると以下が自動作成されます：

- `google_iap_brand` — OAuth 同意画面（Internal タイプ）
- `google_iap_client` — OAuth クライアント
- IAP サービスエージェントへの Cloud Run invoker 権限

> **注意:** `iap_support_email` に指定するメールアドレスは、**プロジェクトのオーナー** または **Workspace ドメイン内のユーザー** である必要があります。

#### ケース2: 個人 Google アカウント（External 公開）

Terraform では External タイプの Brand を作成できないため、**GCP コンソールで手動設定** します。`iap_support_email` は指定不要です。

**手順:**

1. **OAuth 同意画面を作成**
   1. [APIs & Services > OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent) を開く
   2. **User Type: External** を選択して「Create」
   3. 入力項目：
      - **App name**: 任意（例: `My Pages`）
      - **User support email**: 自分のメールアドレス
      - **Developer contact information**: 自分のメールアドレス
   4. **Scopes** 画面 → 何も追加せず「Save and Continue」
   5. **Test users** 画面 → アクセスさせたいアカウントのメールを追加（自分も含む）
   6. **Publishing status** は `Testing` のまま（Test users のみログイン可能）

2. **OAuth クライアント ID を作成**
   1. [APIs & Services > Credentials](https://console.cloud.google.com/apis/credentials) を開く
   2. **Create Credentials > OAuth client ID** をクリック
   3. 入力項目：
      - **Application type**: `Web application`
      - **Name**: 任意（例: `IAP Pages Client`）
   4. いったん作成 → Client ID をコピー
   5. 作成したクライアントを編集し、**Authorized redirect URIs** に以下を追加して保存：
      ```
      https://iap.googleapis.com/v1/oauth/clientIds/CLIENT_ID:handleRedirect
      ```
      `CLIENT_ID` は先ほどコピーした値に置き換える
   6. **Client ID** と **Client secret** を控える

3. **IAP に OAuth クライアントを設定**
   1. [Security > Identity-Aware Proxy](https://console.cloud.google.com/security/iap) を開く
   2. 対象の Cloud Run サービス（Pages）の行の右側 **⋮** メニュー → **Edit OAuth client**
   3. 控えた **Client ID** と **Client secret** を入力して保存

**アクセスできるユーザー:**

- OAuth 同意画面の **Test users** に追加されたアカウント、かつ
- `iap_members` で `roles/iap.httpsResourceAccessor` を付与されたプリンシパル

両方を満たすユーザーのみがページにアクセスできます。

## API エンドポイント追加

[app/src/routes/](app/src/routes/) にルートファイルを追加し、[app/src/index.ts](app/src/index.ts) で `app.route()` に登録。API Gateway 経由で公開する場合は [terraform/openapi.yaml.tpl](terraform/openapi.yaml.tpl) にもパスを追加。

認証なしパスは OpenAPI 定義で `security: []` を指定し、アプリ側でミドルウェアによる検証を行ってください。

## GitHub Actions デプロイ

Actions タブから手動で実行できます。デプロイ対象を選択可能：

| 選択肢 | 動作 |
|---|---|
| `all` | API + Job + Pages の全体デプロイ |
| `app` | API のみビルド＆デプロイ |
| `job` | Job のみビルド＆デプロイ |
| `pages` | Pages のみビルド＆デプロイ |

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
