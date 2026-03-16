# Step 3 — Azure Functions

Step 2 のモジュールパターンを継承しながら、**サーバーレスアーキテクチャ** に固有の  
ストレージ依存関係・Consumption プラン・`listKeys()` 関数を学びます。

---

## 学習目標

- Azure Functions に必須のストレージアカウントの役割を理解する
- Consumption プラン（Y1/Dynamic）と App Service プランの違いを把握する
- `listKeys()` でアクセスキーを取得して接続文字列を組み立てる方法を理解する
- Functions 固有の必須アプリ設定（`AzureWebJobsStorage` 等）を理解する
- Step 2 (Web Apps) との共通点・差分を整理する

---

## ファイル構成

```
step3-functions/
├── main.bicep                    # エントリポイント
├── modules/
│   ├── storageAccount.bicep      # ストレージアカウントの定義
│   └── functionApp.bicep         # Consumption プラン + Function App の定義
└── README.md
```

---

## 作成されるリソース構成

```
リソースグループ
├── ストレージアカウント (Standard_LRS)      ← Functions の必須依存
└── App Service Plan (Consumption / Y1)
    └── Function App
        └── アプリ設定
            ├── AzureWebJobsStorage          ← ストレージ接続文字列
            ├── FUNCTIONS_EXTENSION_VERSION
            ├── FUNCTIONS_WORKER_RUNTIME
            └── WEBSITE_RUN_FROM_PACKAGE
```

---

## 新しい Bicep の概念

### `listKeys()` — リソースのアクセスキーを取得

デプロイ済みリソース（ここではストレージアカウント）のアクセスキーを動的に取得する  
組み込み関数です。接続文字列を手動管理せずに Bicep 内で完結できます。

```bicep
// 書式: listKeys(<リソースID>, <APIバージョン>)
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageModule.outputs.storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageModule.outputs.storageAccountId, '2023-01-01').keys[0].value}'
```

> **セキュリティ注意**: 接続文字列はアクセスキーを含む機密情報です。  
> 本番環境では **Managed Identity + Key Vault** の利用を推奨します。  
> モジュールに渡す際は `@secure()` パラメーターを使い、デプロイログへの露出を防いでいます。

---

### `environment()` — デプロイ先クラウドの情報

Azure Commercial / Government / China 等の地域ごとに変わるエンドポイントを  
ハードコーディングせずに取得できます。

```bicep
environment().suffixes.storage  // 例: "core.windows.net"
```

---

### `take()` / `toLower()` — 文字列操作関数

ストレージアカウント名には「3〜24 文字の英数字小文字」という制約があります。

```bicep
var storageAccountName = toLower('st${take(uniqueString(resourceGroup().id), 10)}')
// "st" (2文字) + uniqueString の先頭10文字 = 12文字
```

| 関数 | 用途 |
|---|---|
| `toLower(str)` | 文字列を小文字に変換 |
| `take(str, n)` | 先頭 n 文字を取り出す |
| `uniqueString(seed)` | 決定論的な 13 文字ハッシュを生成 |

---

## Consumption プランとは

App Service の通常プランとの最大の違いは **従量課金（使った分だけ課金）** と  
**自動スケーリング** です。

| 項目 | App Service プラン (B1 等) | Consumption プラン (Y1) |
|---|---|---|
| 課金 | 時間単位の固定料金 | 実行時間 × 実行数での従量課金 |
| スケーリング | 手動またはスケールルール設定 | Azure が自動でスケールアウト/インゼロ |
| SKU 名 | `B1`, `S1`, `P1v3` など | `Y1` |
| tier | `Basic`, `Standard` など | `Dynamic` |
| コールドスタート | なし | あり（スケールゼロ後の初回呼び出し） |

Bicep での宣言:

```bicep
sku: {
  name: 'Y1'      // Consumption プランの識別子
  tier: 'Dynamic' // 動的スケーリングを意味する
}
```

---

## Functions 必須アプリ設定

| 設定名 | 内容 |
|---|---|
| `AzureWebJobsStorage` | Functions ランタイムが使うストレージ接続文字列（必須） |
| `FUNCTIONS_EXTENSION_VERSION` | ランタイムのバージョン（`~4` = メジャーバージョン 4 の最新） |
| `FUNCTIONS_WORKER_RUNTIME` | 言語ランタイム（`node`, `python`, `dotnet-isolated` 等） |
| `WEBSITE_RUN_FROM_PACKAGE` | Run-From-Package モード（`1` で有効、Step 2 と同様） |

---

## 前提条件

- Azure CLI インストール済み
- Azure Functions Core Tools（ローカル開発・デプロイに使用）

```bash
npm install -g azure-functions-core-tools@4
```

---

## デプロイ手順

### 1. リソースグループを作成

```bash
az group create \
  --name rg-bicep-step3 \
  --location japaneast
```

### 2. インフラをデプロイ

```bash
az deployment group create \
  --resource-group rg-bicep-step3 \
  --template-file main.bicep
```

### 3. Functions プロジェクトを作成（未作成の場合）

```bash
# Node.js + HTTP トリガーの例
func init MyFuncApp --worker-runtime node --language typescript
cd MyFuncApp
func new --name HttpTrigger --template "HTTP trigger"
```

### 4. ソースコードをデプロイ（Functions Core Tools）

```bash
cd MyFuncApp
func azure functionapp publish <functionAppName>
```

または ZIP デプロイ:

```bash
Compress-Archive -Path ./MyFuncApp/* -DestinationPath ./func.zip

az functionapp deployment source config-zip \
  --resource-group rg-bicep-step3 \
  --name <functionAppName> \
  --src ./func.zip
```

### 5. 動作確認

```bash
# HTTP トリガーの場合
curl "https://<functionAppHostName>/api/HttpTrigger?name=Bicep"
```

---

## リソースの削除

```bash
az group delete --name rg-bicep-step3 --yes --no-wait
```

---

## Step 2 との比較まとめ

| 項目 | Step 2 (Web Apps) | Step 3 (Functions) |
|---|---|---|
| プラン | App Service (B1 等) | Consumption (Y1 / Dynamic) |
| ストレージ | 不要 | **必須**（AzureWebJobsStorage） |
| `kind` | `app,linux` | `functionapp,linux` |
| スケーリング | 手動/ルール | 自動（コールドスタートあり） |
| 課金 | 時間固定 | 実行回数 × 実行時間 |
| 適したユースケース | 常時稼働の Web サービス | イベント駆動・バッチ・API の補完 |

---

## 次のステップ（発展的な内容）

学習を深めるためのトピック:

- **Premium プラン**: コールドスタートなし＋VNet 統合
- **Managed Identity**: `AzureWebJobsStorage` をキーレス認証に置き換え
- **Key Vault 参照**: `@Microsoft.KeyVault(...)` 構文でシークレットを安全に管理
- **Durable Functions**: ステートフルなワークフローの実装

---

## 参考

- [Azure Functions のホスティング オプション](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-scale)
- [Microsoft.Web/sites (functionapp) リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.web/sites)
- [Microsoft.Storage/storageAccounts リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.storage/storageaccounts)
- [Bicep listKeys 関数](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/bicep-functions-resource#listkeys)
- [Azure Functions Core Tools](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-run-local)
