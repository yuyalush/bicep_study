# Step 6-1 — Activity Log → Log Analytics Workspace

## 学習目標

サブスクリプションの Activity Log を Log Analytics Workspace に転送し、  
**「誰が・いつ・どのリソースを・どう操作したか」** を KQL で検索できる仕組みを Bicep で構築する。

---

## 前提条件

| ステップ | 状態 |
|---|---|
| Step 1〜5 | 完了済みであること |
| Azure CLI | ログイン済みであること (`az login`) |
| 権限 | サブスクリプションの `Owner` または `Contributor` + `Monitoring Contributor` ロール |

> Step 6-2〜6-3 は本ステップで作成する Log Analytics Workspace を前提とします。  
> **Step 6 全体の基盤となるため、最初に実施してください。**

---

## ファイル構成

```
step6-1/
├── main.bicep                  # targetScope = 'subscription' のエントリポイント
├── modules/
│   └── logAnalytics.bicep      # Log Analytics Workspace
└── README.md                   # このファイル
```

---

## 構成リソース

| リソース | 種類 | スコープ |
|---|---|---|
| リソースグループ | `Microsoft.Resources/resourceGroups` | サブスクリプション |
| Log Analytics Workspace | `Microsoft.OperationalInsights/workspaces` | リソースグループ |
| Activity Log 診断設定 | `microsoft.insights/diagnosticSettings` | **サブスクリプション** |

---

## デプロイ手順

```powershell
# サブスクリプションスコープでデプロイ（Step 5 と同じコマンド形式）
az deployment sub create `
  --location japaneast `
  --template-file main.bicep `
  --parameters location=japaneast

# 環境・プロジェクト名を変更する場合
az deployment sub create `
  --location japaneast `
  --template-file main.bicep `
  --parameters location=japaneast environment=prod projectName=myproj retentionDays=180
```

デプロイ後、**Workspace ID** を出力から控えておくと Step 6-2〜6-3 で使用できます。

```powershell
# Workspace ID を変数に格納する例
# ★ --name には az deployment sub create 実行時のデプロイ名を指定する
#   --name を省略した場合はテンプレートファイル名（main）が自動的に使われる
$WORKSPACE_ID = $(az deployment sub show `
  --name main `
  --query properties.outputs.workspaceId.value `
  -o tsv)
```

---

## 新しく学ぶ Bicep の概念

### 1. サブスクリプションスコープの diagnosticSettings

Step 5 では `Microsoft.Consumption/budgets` 等のサブスクリプションリソースを扱いました。  
本ステップでは **診断設定** もサブスクリプションスコープに配置できることを学びます。

```bicep
// main.bicep (targetScope = 'subscription') 内での定義例
resource activityLogDiag 'microsoft.insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'activity-log-to-law'
  // scope を省略 → targetScope = 'subscription' がそのまま適用
  properties: {
    workspaceId: '...'
    logs: [
      { category: 'Administrative', enabled: true }  // ★ 区切りはカンマ（セミコロン不可）
      ...
    ]
  }
}
```

### 2. モジュール間の output 参照

```bicep
// モジュールの出力を後続リソースで参照する
module logAnalytics 'modules/logAnalytics.bicep' = { ... }

resource activityLogDiag '...' = {
  properties: {
    workspaceId: logAnalytics.outputs.workspaceId  // ← モジュールの output を直接参照
  }
}
```

---

## デプロイ後に試す KQL クエリ

Azure Portal → Log Analytics Workspace → **ログ** から以下を実行してみましょう。

```kql
// 過去 24 時間の全 Activity Log
AzureActivity
| where TimeGenerated > ago(24h)
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, ActivityStatusValue
| order by TimeGenerated desc
```

```kql
// リソースの削除操作のみ抽出
AzureActivity
| where OperationNameValue endswith "/delete"
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, ResourceGroup, Resource, OperationNameValue
```

```kql
// RBAC ロールの変更履歴（誰が誰に権限を付与したか）
AzureActivity
| where OperationNameValue == "Microsoft.Authorization/roleAssignments/write"
| project TimeGenerated, Caller, Properties
```

```kql
// 操作者ごとの操作回数ランキング
AzureActivity
| where TimeGenerated > ago(7d)
| summarize OperationCount = count() by Caller
| order by OperationCount desc
| take 10
```

---

## 収集されるログカテゴリ

| カテゴリ | 内容 | 監査用途 |
|---|---|---|
| `Administrative` | リソースの作成・変更・削除 | **最重要**: 誰が何をしたか |
| `Security` | RBAC 変更・セキュリティアラート | 権限変更の追跡 |
| `ServiceHealth` | Azure サービスの障害・メンテナンス | 障害発生時の原因調査 |
| `Alert` | Azure Monitor アラートの発火 | アラート履歴の確認 |
| `Recommendation` | Azure Advisor の推奨事項 | コスト・セキュリティ改善 |
| `Policy` | Policy の準拠・非準拠 | コンプライアンス確認 |
| `Autoscale` | オートスケールイベント | スケール動作の確認 |
| `ResourceHealth` | リソース正常性の変化 | 障害影響範囲の把握 |
