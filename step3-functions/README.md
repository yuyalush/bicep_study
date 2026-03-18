# Step 3 — Azure Functions

Step 2 のモジュールパターンを継承しながら、**サーバーレスアーキテクチャ** に固有の  
ストレージ依存関係・Consumption プラン・**Managed Identity によるキーレス認証** を学びます。

---

## 学習目標

- Azure Functions に必須のストレージアカウントの役割を理解する
- Consumption プラン（Y1/Dynamic）と App Service プランの違いを把握する
- **Managed Identity（マネージド ID）** でストレージキー不要のセキュアな接続を実装する
- `Microsoft.Authorization/roleAssignments` で RBAC ロールを Bicep から割り当てる
- Functions 固有の必須アプリ設定（`AzureWebJobsStorage__accountName` 等）を理解する
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
│   └── RBAC ロール割り当て ×3              ← Function App の Managed Identity に付与
│       ├── Storage Blob Data Owner
│       ├── Storage Queue Data Contributor
│       └── Storage Table Data Contributor
└── App Service Plan (Consumption / Y1)
    └── Function App  [System-assigned Managed Identity]
        └── アプリ設定
            ├── AzureWebJobsStorage__accountName  ← キーレス接続（ストレージ名のみ）
            ├── AzureWebJobsStorage__credential   ← "managedidentity"
            ├── FUNCTIONS_EXTENSION_VERSION
            ├── FUNCTIONS_WORKER_RUNTIME
            ├── WEBSITE_RUN_FROM_PACKAGE
            └── WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID
```

---

## 新しい Bicep の概念

### Managed Identity（マネージド ID）— キーレス認証

Azure リソースに **自動管理のサービスプリンシパル** を付与する仕組みです。  
パスワード・接続文字列・アクセスキーを一切管理せずに、Azure サービス間の認証を実現します。

```bicep
// identity ブロックを追加するだけで Managed Identity が有効になる
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  identity: {
    type: 'SystemAssigned'  // Entra ID にサービスプリンシパルが自動登録される
  }
  ...
}
```

| 種別 | 説明 |
|---|---|
| **SystemAssigned（システム割り当て）** | リソースのライフサイクルと連動。リソース削除で自動消去 |
| UserAssigned（ユーザー割り当て） | 独立したリソースとして管理。複数リソースで共有可能 |

---

### RBAC ロール割り当て — `Microsoft.Authorization/roleAssignments`

Managed Identity にストレージへのアクセス権限を付与します。  
`scope` プロパティで「どのリソースに対する権限か」を指定できます。

```bicep
// existing: 既存リソースの参照（デプロイは行わず、ID やプロパティだけ参照する）
resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// ループで複数ロールを一括割り当て
resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in storageRoleIds: {
  name: guid(storageAccountId, functionApp.id, roleId)  // 決定論的な一意 ID
  scope: storageAccountRef                              // ストレージ単位で権限を限定
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalId: functionApp.identity.principalId       // Function App の Managed Identity
    principalType: 'ServicePrincipal'
  }
}]
```

> **`guid()` 関数**: 引数から決定論的な UUID を生成します。同じ引数からは常に同じ ID が得られるため、  
> 再デプロイしても重複なくロール割り当てを冪等に管理できます。

---

### identity-based connection — `AzureWebJobsStorage__accountName`

接続文字列の代わりに **二重アンダースコア（`__`）区切り** でプロパティを個別に指定する方式です。  
アクセスキーが不要になり、キーローテーションの管理も不要です。

```bicep
// 従来（接続文字列方式）← アクセスキーが設定値に含まれる
{ name: 'AzureWebJobsStorage',              value: 'DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...' }

// Managed Identity 方式（identity-based connection）← キー不要
{ name: 'AzureWebJobsStorage__accountName', value: storageAccountName }
{ name: 'AzureWebJobsStorage__credential',  value: 'managedidentity' }
```

---

### 暗黙的な依存関係の活用

`main.bicep` で `storageModule.outputs.storageAccountId` を参照して渡しています。  
モジュールの **output を params で参照するだけで Bicep が依存関係を自動検知** するため、  
`dependsOn` の明示的な記述が不要になります。

```bicep
module functionAppModule 'modules/functionApp.bicep' = {
  name: 'deploy-functionApp'
  // dependsOn 不要: storageModule.outputs を params で参照しているため自動的に順序が決まる
  params: {
    storageAccountId: storageModule.outputs.storageAccountId  // ← これが暗黙的な依存関係を作る
    storageAccountName: storageAccountName
  }
}
```

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

| 設定名 | 値 | 内容 |
|---|---|---|
| `AzureWebJobsStorage__accountName` | ストレージ名 | Managed Identity 接続先のストレージアカウント名 |
| `AzureWebJobsStorage__credential` | `managedidentity` | DefaultAzureCredential によるキーレス認証を指示 |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` | ランタイムのメジャーバージョン 4 の最新を使用 |
| `FUNCTIONS_WORKER_RUNTIME` | `node` 等 | 言語ランタイム（`node`, `python`, `dotnet-isolated` 等） |
| `WEBSITE_RUN_FROM_PACKAGE` | Blob URL | Run-From-Package モード。Blob URL 形式で ZIP パッケージの場所を指定 |
| `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID` | `SystemAssigned` | Blob URL の取得に Managed Identity を使用する指定。**省略すると ZIP をダウンロードできず 404 になる** |

> **`AzureWebJobsStorage` との違い**: 従来の単一キー（接続文字列）は `AzureWebJobsStorage__accountName` と  
> `AzureWebJobsStorage__credential` という 2 つのキーに分割されます。`__` 区切りで指定することで  
> Functions SDK が Managed Identity 認証を使用するようになります。

---

## 前提条件

- Azure CLI インストール済み
- Azure Functions Core Tools（ローカル開発・デプロイに使用）

```powershell
npm install -g azure-functions-core-tools@4
```

---

## デプロイ手順

### 1. リソースグループを作成

```powershell
az group create --name rg-bicep-step3 --location japaneast
```

### 2. インフラをデプロイ（自分の Object ID を渡す）

`deployingUserObjectId` を渡すと、Bicep がストレージへの Blob アップロード権限（Step 4 で必要）を自動付与します。

```powershell
# 自分の Object ID を取得
$userId = az ad signed-in-user show --query id -o tsv

az deployment group create `
  --resource-group rg-bicep-step3 `
  --template-file main.bicep `
  --parameters deployingUserObjectId=$userId
```

### 3. Functions プロジェクトを作成（未作成の場合）

```powershell
func init MyFuncApp --worker-runtime node --language typescript
cd MyFuncApp
func new --name HttpTrigger --template "HTTP trigger"
npm install
```

### 4. ソースコードをデプロイ（Blob Upload → Run-From-Package）

Managed Identity 環境では `func azure functionapp publish` や  
`az functionapp deployment source config-zip` はストレージキーが不要の代わりに  
Blob URL 方式の Run-From-Package を使います。

```powershell
# ① ビルド
cd MyFuncApp
npm run build

# ② production 依存物のみの軽量 ZIP を作成
$deployPkg = "../deploy_pkg"
Remove-Item -Recurse -Force $deployPkg -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $deployPkg | Out-Null
Copy-Item host.json, package.json, package-lock.json $deployPkg
Copy-Item dist $deployPkg -Recurse
cd $deployPkg
npm ci --omit=dev
Compress-Archive -Path ./* -DestinationPath ../func.zip -Force

# ③ ストレージアカウント名を取得
$storageName = az deployment group show `
  --resource-group rg-bicep-step3 `
  --name main `
  --query "properties.outputs.storageAccountName.value" -o tsv

# ④ Blob にアップロード（AAD 認証・キー不要）
az storage container create --name deployments --account-name $storageName --auth-mode login
az storage blob upload `
  --container-name deployments --name func.zip `
  --file ../func.zip `
  --account-name $storageName --auth-mode login --overwrite

# ⑤ Function App 名を取得して再起動（パッケージを読み込む）
$funcApp = az deployment group show `
  --resource-group rg-bicep-step3 `
  --name main `
  --query "properties.outputs.functionAppName.value" -o tsv

az functionapp restart --resource-group rg-bicep-step3 --name $funcApp
```

> **`func azure functionapp publish` が使えない理由**  
> このコマンドはストレージ接続文字列（アクセスキー）を使って Blob にパッケージをアップロードします。  
> Managed Identity 環境ではアクセスキーが無効（`KeyBasedAuthenticationNotPermitted`）なため、  
> Blob URL + `az storage blob upload --auth-mode login` の組み合わせを使います。

### 5. 動作確認

```powershell
$hostName = az functionapp show `
  --resource-group rg-bicep-step3 --name $funcApp `
  --query defaultHostName -o tsv

Invoke-RestMethod "https://$hostName/api/HttpTrigger?name=Bicep"
# → "Hello, Bicep!"
```

---

## リソースの削除

```powershell
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

## Tips: ストレージのネットワーク制限とプラン選択

Function App は `WEBSITE_RUN_FROM_PACKAGE` で指定した Blob URL からデプロイパッケージ（ZIP）をダウンロードします。  
ストレージのネットワーク制限によっては、このダウンロードがブロックされ **関数コードがロードされない（HTTP 404）** 場合があります。

### ストレージのネットワーク設定と動作

| 設定 | Consumption プラン | Premium / Dedicated プラン |
|---|---|---|
| `publicNetworkAccess: Enabled` + `defaultAction: Allow` | ✅ 動作する | ✅ 動作する |
| `publicNetworkAccess: Enabled` + `defaultAction: Deny` + `bypass: AzureServices` | ❌ **動作しない**（※1） | ❌ **動作しない**（※1） |
| `publicNetworkAccess: Enabled` + `defaultAction: Deny` + IP ルール | ⚠️ 不安定（※2） | ⚠️ 条件付き |
| `publicNetworkAccess: Disabled` + Private Endpoint | ❌ VNet 統合不可 | ✅ 推奨構成 |

> **※1** `bypass: AzureServices`（信頼された Azure サービスのバイパス）は Azure Backup や Event Grid 等が対象であり、  
> Function App ランタイムの Blob ダウンロードは**対象外**です。
>
> **※2** Consumption プランはアウトバウンド IP が動的に変わるため、IP ルールでの許可は安定しません。

### プラン別の推奨構成

| 要件 | 推奨プラン | ストレージ構成 |
|---|---|---|
| 低コスト・開発/検証用 | **Consumption (Y1)** | `publicNetworkAccess: Enabled`, `defaultAction: Allow` |
| ストレージへのパブリックアクセスを完全遮断 | **Premium (EP1〜)** または **Dedicated (B1〜)** | VNet 統合 + Private Endpoint + `publicNetworkAccess: Disabled` |
| コスト重視だがある程度の制限が必要 | **Consumption (Y1)** | `allowSharedKeyAccess: false` + `allowBlobPublicAccess: false`（※キーレス認証で保護） |

### よくあるトラブル: 関数の 404 エラー

Function App の URL にアクセスすると **ルート（`/`）は 200 を返すのに `/api/<関数名>` が 404** になる場合、  
関数コードがロードされていない可能性があります。以下を確認してください:

1. **`WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID`** が設定されているか  
   → 未設定だと Managed Identity で Blob をダウンロードできない
2. **ストレージの `publicNetworkAccess`** が `Enabled` か  
   → `Disabled` だと Consumption プランからはアクセス不可
3. **ストレージの `defaultAction`** が `Allow` か  
   → `Deny` の場合、`bypass: AzureServices` だけでは不足

確認コマンド:
```powershell
# ランタイムにロードされた関数を確認（空なら ZIP 読み込み失敗）
$masterKey = az functionapp keys list -n <func-app-name> -g <rg-name> --query masterKey -o tsv
Invoke-RestMethod "https://<func-app-name>.azurewebsites.net/admin/functions" -Headers @{"x-functions-key"=$masterKey}

# ストレージのネットワーク設定を確認
az storage account show -n <storage-name> --query "{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction, bypass:networkRuleSet.bypass}" -o json
```

---

## 次のステップ（発展的な内容）

学習を深めるためのトピック:

- **Premium プラン**: コールドスタートなし＋VNet 統合
- **UserAssigned Managed Identity**: 複数リソースで同一 ID を共有する構成
- **Key Vault 参照**: `@Microsoft.KeyVault(...)` 構文でシークレットを安全に管理
- **Durable Functions**: ステートフルなワークフローの実装
- **Private Endpoint**: ストレージへのパブリックアクセスを完全に遮断する構成

---

## 参考

- [Azure Functions のホスティング オプション](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-scale)
- [Microsoft.Web/sites (functionapp) リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.web/sites)
- [Microsoft.Storage/storageAccounts リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.storage/storageaccounts)
- [Azure Functions でのマネージド ID の使用](https://learn.microsoft.com/ja-jp/azure/azure-functions/security-concepts#managed-identities)
- [Functions の ID ベース接続（identity-based connection）](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-reference#connecting-to-host-storage-with-an-identity)
- [Microsoft.Authorization/roleAssignments リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.authorization/roleassignments)
- [Azure RBAC 組み込みロール一覧](https://learn.microsoft.com/ja-jp/azure/role-based-access-control/built-in-roles)
- [Azure Functions Core Tools](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-run-local)
