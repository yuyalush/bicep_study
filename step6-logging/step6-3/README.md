# Step 6-3 — リソース別 Diagnostic Settings（Step 2〜4 との統合）

## 学習目標

`existing` キーワードと **クロス RG スコープ** を活用して、  
Step 2〜4 で構築した既存リソースに診断設定を後付けし、  
Step 6-1 の Log Analytics Workspace にログを集約する。

---

## 前提条件

| ステップ | 状態 |
|---|---|
| **Step 2**（Web Apps） | 完了済みであること |
| **Step 3**（Azure Functions） | 完了済みであること |
| **Step 4**（Secure VM + Key Vault） | 完了済みであること |
| **Step 6-1**（Log Analytics Workspace） | **完了済みであること**（Workspace ID が必要） |

---

## ファイル構成

```
step6-3/
├── main.bicep                   # targetScope = 'resourceGroup'
├── modules/
│   ├── keyVaultDiag.bicep       # Key Vault 診断設定（Step 4 のリソース）
│   ├── webAppDiag.bicep         # Web App 診断設定（Step 2 のリソース）
│   └── functionsDiag.bicep      # Function App 診断設定（Step 3 のリソース）
└── README.md                    # このファイル
```

---

## デプロイ手順

### 事前確認: パラメーターに渡すリソース名の調べ方

デプロイ前に以下のコマンドで各リソースの実際の名前を確認できます。

```powershell
# Step 6-1 の Workspace ID
az deployment sub show `
  --name main `
  --query properties.outputs.workspaceId.value `
  -o tsv

# bicep を含むリソースグループ一覧（Step 1〜6 の RG を確認）
az group list -o tsv --query "[].name" | Select-String "bicep"

# Step 2: Web App 名
az webapp list --resource-group rg-bicep-step2 --query "[].name" -o tsv

# Step 3: Function App 名
az functionapp list --resource-group rg-bicep-step3 --query "[].name" -o tsv

# Step 4: Key Vault 名
az keyvault list --resource-group rg-bicep-step4 --query "[].name" -o tsv
```

### デプロイ実行

```powershell
# Step 6-1 の Workspace ID を取得
# ★ --name には az deployment sub create 実行時のデプロイ名を指定する
#   --name を省略した場合はテンプレートファイル名（main）が自動的に使われる
$WORKSPACE_ID=$(az deployment sub show `
  --name main `
  --query properties.outputs.workspaceId.value `
  -o tsv)

# Step 6-3 をデプロイ（Step 6-1 の logging RG をデプロイ先として使用）
az deployment group create `
  --resource-group rg-bicep-logging-dev `
  --template-file main.bicep `
  --parameters `
    logAnalyticsWorkspaceId="$WORKSPACE_ID" `
    keyVaultName="kv-sbnaw64zprgk6" `
    keyVaultRgName="rg-bicep-step4" `
    webAppName="bicep02-dev-app-2sf5vadn4z7aa" `
    webAppRgName="rg-bicep-step2" `
    functionAppName="bicep03-dev-func-k7fuz2zfsrnuw" `
    functionAppRgName="rg-bicep-step3"
```

---

## 新しく学ぶ Bicep の概念

### 1. `existing` キーワード

`existing` は**すでにデプロイ済みのリソースを参照**するためのキーワードです。  
新しいリソースを作成せず、既存リソースのプロパティ参照や  
サブリソースのスコープとして使用します。

```bicep
// 既存の Key Vault を参照（作成しない）
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName  // パラメーターで受け取った名前
}

// 診断設定を Key Vault のサブリソースとして追加
resource diagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'kv-diag'
  scope: keyVault   // ← existing リソースをスコープに指定
  properties: { ... }
}
```

| `existing` の用途 | 例 |
|---|---|
| プロパティの参照 | `keyVault.properties.vaultUri` |
| サブリソースのスコープ指定 | `scope: keyVault` |
| RBAC ロール割り当ての対象 | Step 3・4 で使用済み |

### 2. クロス RG デプロイ（`scope: resourceGroup(rgName)`）

1 回のデプロイで**複数のリソースグループをまたいで**設定を適用できます。

```bicep
// Step 2 の RG にある Web App を対象として
module webAppDiag 'modules/webAppDiag.bicep' = {
  name: 'deploy-webAppDiag'
  scope: resourceGroup('rg-bicep-webapp-dev')  // ← 別の RG を指定
  params: { ... }
}

// Step 4 の RG にある Key Vault を対象として（同じデプロイ内で）
module keyVaultDiag 'modules/keyVaultDiag.bicep' = {
  name: 'deploy-keyVaultDiag'
  scope: resourceGroup('rg-bicep-secure-dev')   // ← さらに別の RG
  params: { ... }
}
```

### 3. `scope` の使い方まとめ

| 使う場面 | 構文 | 意味 |
|---|---|---|
| 診断設定を既存リソースに付ける | `scope: existingResource` | サブリソースとして追加 |
| モジュールを別 RG でデプロイ | `scope: resourceGroup('rg名')` | 別 RG をターゲットに |
| モジュールをサブスクリプションスコープで | `scope: subscription()` | サブスクリプション全体に適用 |

---

## デプロイ後に試す KQL クエリ

### Key Vault（誰がシークレットにアクセスしたか）

```kql
// Key Vault への操作ログ（AKVAuditLogs テーブル）
AZKVAuditLogs
| where TimeGenerated > ago(24h)
| project TimeGenerated, CallerIpAddress, Identity, OperationName,
          ResultType, Properties
| order by TimeGenerated desc
```

```kql
// シークレットへの get 操作のみ（誰が何のシークレットを取得したか）
AZKVAuditLogs
| where OperationName == "SecretGet"
| project TimeGenerated, Identity, Properties.requestUri, ResultType
```

### Web App（HTTP アクセスログ）

```kql
// HTTP アクセスログ（AppServiceHTTPLogs テーブル）
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, CsMethod, CsUriStem, ScStatus,
          TimeTaken, CIp
| order by TimeGenerated desc
```

```kql
// エラーレスポンス（5xx）の一覧
AppServiceHTTPLogs
| where ScStatus >= 500
| project TimeGenerated, CsMethod, CsUriStem, ScStatus, CIp
```

### Function App（実行ログ）

```kql
// 関数の実行ログ（FunctionAppLogs テーブル）
FunctionAppLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, FunctionName, Level, Message, ExceptionMessage
| order by TimeGenerated desc
```

```kql
// 関数のエラーのみ抽出
FunctionAppLogs
| where Level == "Error" or Level == "Critical"
| project TimeGenerated, FunctionName, Message, ExceptionMessage
```

---

## 収集されるログ一覧

| リソース | Log Analytics テーブル | 内容 |
|---|---|---|
| Key Vault | `AZKVAuditLogs` | シークレット・キー・証明書の操作履歴 |
| Web App | `AppServiceHTTPLogs` | HTTP リクエスト詳細 |
| Web App | `AppServiceAuditLogs` | FTP/Kudu ログイン履歴 |
| Web App | `AppServiceConsoleLogs` | アプリの標準出力 |
| Function App | `FunctionAppLogs` | 関数の実行結果・エラー |
| Function App | `AppServiceHTTPLogs` | HTTP トリガーのアクセスログ |
