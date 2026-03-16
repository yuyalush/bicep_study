# Step 5 — コスト分析・予算管理

## 学習目標

Azure Cost Management のリソースを Bicep でデプロイし、サブスクリプションのコストを継続的に把握・制御する仕組みを構築する。

---

## ファイル構成

```
step5-cost-mgmt/
├── main.bicep                  # targetScope = 'subscription' のエントリポイント
├── modules/
│   ├── actionGroup.bicep       # 通知先グループ（location: 'global' 固定）
│   ├── budget.bicep            # 月次予算・アラートしきい値（subscription スコープ）
│   ├── storage.bicep           # ストレージアカウント + コンテナ（RG スコープ）
│   ├── costExport.bicep        # コストエクスポート定義（subscription スコープ）
│   └── exportRbac.bicep        # エクスポート MI へのロール付与（RG スコープ）
└── README.md                   # このファイル
```

> **注意**: `exportRbac.bicep` は現時点では `main.bicep` から呼び出されていません。  
> Azure Policy により `allowSharedKeyAccess: true` が禁止されている環境では  
> `Microsoft.CostManagement/exports` の Bicep デプロイ自体が不可のため、  
> **エクスポート定義は Azure Portal から手動で作成**してください（[手順は後述](#コストエクスポートのポータル作成手順)）。

---

## 構成リソース

| リソース | 種類 | スコープ | Bicep デプロイ |
|---|---|---|---|
| リソースグループ | `Microsoft.Resources/resourceGroups` | サブスクリプション | ✅ |
| Action Group | `Microsoft.Insights/actionGroups` | リソースグループ | ✅ |
| ストレージアカウント | `Microsoft.Storage/storageAccounts` | リソースグループ | ✅ |
| Blob コンテナ | `…/blobServices/containers` | リソースグループ | ✅ |
| 予算アラート | `Microsoft.Consumption/budgets` | サブスクリプション | ✅ |
| コストエクスポート | `Microsoft.CostManagement/exports` | サブスクリプション | ⚠️ 手動 |

---

## 新しく学ぶ Bicep の概念

### 1. `targetScope = 'subscription'`

Step 1〜4 の `main.bicep` は `targetScope` を省略していました（デフォルトは `'resourceGroup'`）。  
コスト管理リソースはサブスクリプション全体に適用するため `'subscription'` を明示します。

| スコープ | コマンド |
|---|---|
| リソースグループ（Step 1〜4） | `az deployment group create --resource-group <RG名>` |
| **サブスクリプション（Step 5）** | **`az deployment sub create --location <リージョン>`** |

> **`--location` はデプロイメタデータの保存先リージョン**（リソースの配置先ではない）。  
> リソースの実際の配置先は `--parameters location=<リージョン>` で別途指定する。

---

### 2. サブスクリプションスコープからのリソースグループ作成

`targetScope = 'subscription'` のとき、リソースグループ自体も Bicep で定義できます。  
Step 1〜4 では `az group create` でリソースグループを事前作成する必要がありましたが、  
Step 5 ではリソースグループの作成もデプロイに含まれます。

```bicep
resource exportResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-bicep-step5'
  location: location
}
```

---

### 3. モジュールへの `scope` の指定

サブスクリプションスコープの `main.bicep` からリソースグループスコープのモジュールを呼び出すには `scope` プロパティが必要です：

```bicep
module actionGroupModule 'modules/actionGroup.bicep' = {
  name: 'deploy-actionGroup'
  scope: exportResourceGroup    // ← このリソースグループに配置
  params: { ... }
}
```

Step 1〜4 では同一スコープのため `scope` を省略していましたが、Step 5 では明示が必要です。

---

### 4. モジュール側の `targetScope`

サブスクリプションスコープのリソース（`Microsoft.Consumption/budgets` 等）を定義するモジュールには `targetScope = 'subscription'` の宣言が必要です：

```bicep
// modules/budget.bicep
targetScope = 'subscription'
```

リソースグループスコープのモジュール（`actionGroup.bicep`・`storage.bicep`）は `targetScope` を省略します（呼び出し元で `scope:` を指定するため）。

---

### 5. `utcNow()` 関数

デプロイ実行日時を動的に取得するために `utcNow()` を使います。  
`utcNow()` は **`param` のデフォルト値としてのみ使用可能**（`var` への代入はコンパイルエラー）：

```bicep
// ✅ 正しい使い方
param exportStartDate string = utcNow('yyyy-MM-dd')

// ❌ エラーになる
var now = utcNow('yyyy-MM-dd')
```

---

### 6. Action Group は `location: 'global'`

`Microsoft.Insights/actionGroups` はグローバルリソースのため、`location` に地域名（`japaneast` 等）を指定するとエラーになります：

```bicep
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-budget-ag'
  location: 'global'  // ← 地域名は不可。'global' 固定
  ...
}
```

---

### 7. Azure Policy との衝突

このサブスクリプションでは Azure Policy により **`allowSharedKeyAccess: true` が禁止**されています。  
`Microsoft.CostManagement/exports` はデプロイ時にキーベース認証でストレージへの疎通確認を行うため、  
Bicep / ARM テンプレートから直接作成できません（`400: Key-based authentication is currently disabled`）。

**解決策**: エクスポート定義は Azure Portal から手動で作成する（[手順は後述](#コストエクスポートのポータル作成手順)）。

---

## Step 4 との比較

| 項目 | Step 4 | Step 5 |
|---|---|---|
| `targetScope` | `'resourceGroup'`（省略） | **`'subscription'`** |
| デプロイコマンド | `az deployment group create` | **`az deployment sub create`** |
| RG の作成 | `az group create` で事前作成 | **Bicep 内で `Microsoft.Resources/resourceGroups` として定義** |
| `module` の `scope` | 不要（同一スコープ） | **必要**（RG スコープのモジュールに指定） |
| `location` パラメーター | デプロイ先 RG と同じ | **`--location`（メタデータ）と `--parameters location=`（リソース配置先）が別** |

---

## デプロイ手順

### 1. 前提確認

```powershell
# サブスクリプションの確認
az account show --query "{name:name, id:id}" --output table

# Cost Management プロバイダーの登録確認（未登録の場合は登録）
az provider show --namespace Microsoft.Consumption --query "registrationState"
az provider show --namespace Microsoft.CostManagement --query "registrationState"

az provider register --namespace Microsoft.Consumption
az provider register --namespace Microsoft.CostManagement
```

### 2. デプロイ

```powershell
cd step5-cost-mgmt

az deployment sub create `
  --location canadacentral `
  --template-file .\main.bicep `
  --parameters location=canadacentral `
               notificationEmail="your@email.com" `
               budgetAmountUSD=50
```

> `--location` はデプロイメタデータの保存先。`--parameters location=` がリソースの配置先。両方指定する。

### 3. デプロイ結果の確認

```powershell
# 予算の確認
az consumption budget list `
  --query "[].{name:name, amount:amount, currentSpend:currentSpend.amount}" `
  --output table

# ストレージアカウントの確認
az storage account list --resource-group rg-bicep-step5 `
  --query "[].{name:name, location:location}" --output table

# Action Group の確認
az monitor action-group list --resource-group rg-bicep-step5 `
  --query "[].{name:name, email:emailReceivers[0].emailAddress}" --output table
```

---

## コストエクスポートのポータル作成手順

コストのエクスポートについては、最新のドキュメントを参照の上、ポータルから操作してください。

[チュートリアル: Cost Management エクスポートの作成と管理](https://learn.microsoft.com/ja-jp/azure/cost-management-billing/costs/tutorial-improved-exports)

以下の記述は当プロジェクト作成時にAPIを元に作成されましたが、内容が不正確です。

---

`Microsoft.CostManagement/exports` は Azure Policy（`allowSharedKeyAccess` 禁止）の影響で  
Bicep / ARM テンプレートからのデプロイができないため、ポータルから手動作成します。

1. Azure Portal で **「コスト管理」** → **「エクスポート」** を開く
2. **「追加」** をクリック
3. 以下を設定：
   - **エクスポートの種類**: 月次コスト（先月）
   - **ストレージアカウント**: デプロイした `stbicepdevcost`（RG: `rg-bicep-step5`）
   - **コンテナ**: `cost-exports`
   - **ディレクトリ**: `cost-data`
   - **マネージド ID を有効にする**: ✅ チェック ← ここが重要（キーレスアクセス）
4. 「作成」をクリック

> **「マネージド ID を有効にする」にチェックを入れると**、ポータルが自動的に  
> ストレージアカウントへ Storage Blob Data Contributor ロールを付与します。  
> Bicep の `exportRbac.bicep` は、このロール付与を Bicep で管理したい場合の参考用です。

---

## Tips: リソースの削除

```powershell
# 予算の削除
az consumption budget delete --budget-name "bicep-dev-monthly-budget"

# エクスポートの削除（ポータルで作成した場合）
az costmanagement export delete `
  --name "<エクスポート名>" `
  --scope "/subscriptions/$(az account show --query id -o tsv)"

# リソースグループごと削除（ストレージアカウント・Action Group）
az group delete --name rg-bicep-step5 --yes --no-wait
```

---

## 参考リンク

- [Microsoft.Consumption/budgets - Bicep リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.consumption/budgets)
- [Microsoft.CostManagement/exports - Bicep リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.costmanagement/exports)
- [Microsoft.Insights/actionGroups - Bicep リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.insights/actiongroups)
- [サブスクリプションスコープへのデプロイ](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/deploy-to-subscription)
- [Azure Cost Management のドキュメント](https://learn.microsoft.com/ja-jp/azure/cost-management-billing/)
