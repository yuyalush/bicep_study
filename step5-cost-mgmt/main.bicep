// ============================================================
// Step 5: コスト分析・予算管理
// サブスクリプションスコープでデプロイし、以下を実現する:
//   - 月次予算とアラートしきい値の定義（Microsoft.Consumption/budgets）
//   - 通知先グループの管理（Microsoft.Insights/actionGroups）
//   - コストデータの定期エクスポート（Microsoft.CostManagement/exports）
//
// デプロイコマンド:
//   az deployment sub create \
//     --location canadacentral \
//     --template-file main.bicep \
//     --parameters location=canadacentral notificationEmail="your@email.com"
//
// ★ --location はデプロイメタデータの保存先リージョン（リソースの作成先ではない）
//    リソースの作成先は --parameters location=xxx で明示的に指定する
// ============================================================

// ------------------------------------------------------------
// ★ サブスクリプション スコープ
// Step 1〜4 では省略していた（デフォルトは 'resourceGroup'）
// コスト管理リソースはサブスクリプション全体に適用するため 'subscription' を指定する
// ------------------------------------------------------------
targetScope = 'subscription'

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------

@description('エクスポート先リソースを作成する Azure リージョン（必須）')
param location string  // デフォルト値なし: az deployment sub create の --location とは別物のため明示必須

@description('環境名')
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@description('プロジェクト名 (リソース名のプレフィックス)')
@minLength(2)
@maxLength(8)
param projectName string = 'bicep'

@description('予算・アラートの通知先メールアドレス')
param notificationEmail string

@description('月次予算の上限額（USD）')
@minValue(1)
param budgetAmountUSD int = 50

@description('予算アラートのしきい値（%）: 1 段階目')
@minValue(1)
@maxValue(100)
param alertThreshold1Pct int = 80

@description('予算アラートのしきい値（%）: 2 段階目')
@minValue(1)
@maxValue(100)
param alertThreshold2Pct int = 100

@description('エクスポートデータを格納するストレージアカウント名（空の場合は新規作成）')
param exportStorageAccountName string = ''

// ------------------------------------------------------------
// 変数
// ------------------------------------------------------------

var prefix = '${projectName}-${environment}'

// リソースグループ名: Step 1〜4 と同じ rg-bicep-stepN の命名規則に合わせる
var exportRgName = 'rg-${projectName}-step5'

// ストレージアカウント名: 指定がなければ自動生成（3〜24 文字・英数字のみ）
var storageAccountName = empty(exportStorageAccountName)
  ? 'st${take(replace(prefix, '-', ''), 8)}cost'
  : exportStorageAccountName

// コストエクスポートのコンテナ名
var exportContainerName = 'cost-exports'

// ------------------------------------------------------------
// ① リソースグループ
// サブスクリプション スコープからは resourceGroup() が使えないため
// リソースグループ自体も Bicep で定義できる
// ------------------------------------------------------------
resource exportResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: exportRgName
  location: location
}

// ------------------------------------------------------------
// ② Action Group（通知先グループ）モジュール
// リソースグループ スコープのリソースのため module で切り出し
// ------------------------------------------------------------
module actionGroupModule 'modules/actionGroup.bicep' = {
  name: 'deploy-actionGroup'
  // scope にリソースグループを指定（サブスクリプション スコープからの呼び出し）
  scope: exportResourceGroup
  params: {
    prefix:            prefix
    notificationEmail: notificationEmail
  }
}

// ------------------------------------------------------------
// ③ ストレージアカウント + コンテナ モジュール（RG スコープ）
// コストエクスポートの CSV 出力先
// ※ Microsoft.CostManagement/exports はデプロイ時にキーベース認証で
//    ストレージアカウントを確認する仕様のため、allowSharedKeyAccess を
//    Policy で無効化している環境では ARM/Bicep からのデプロイが不可。
//    エクスポート定義は Azure Portal から手動で作成する（マネージド ID オプション選択）。
// ------------------------------------------------------------
module storageModule 'modules/storage.bicep' = {
  name: 'deploy-storage'
  scope: exportResourceGroup
  params: {
    location:            location
    storageAccountName:  storageAccountName
    exportContainerName: exportContainerName
  }
}

// ------------------------------------------------------------
// ④ 予算アラート モジュール
// サブスクリプション スコープのリソースのため scope の指定なし
// ------------------------------------------------------------
module budgetModule 'modules/budget.bicep' = {
  name: 'deploy-budget'
  params: {
    prefix:             prefix
    budgetAmountUSD:    budgetAmountUSD
    alertThreshold1Pct: alertThreshold1Pct
    alertThreshold2Pct: alertThreshold2Pct
    actionGroupId:      actionGroupModule.outputs.actionGroupId
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('エクスポート用リソースグループ名')
output exportResourceGroupName string = exportResourceGroup.name

@description('コストエクスポート先ストレージアカウント名')
output storageAccountName string = storageModule.outputs.storageAccountName

@description('コストエクスポート先コンテナ名')
output exportContainerName string = storageModule.outputs.exportContainerName

@description('Action Group のリソース ID')
output actionGroupId string = actionGroupModule.outputs.actionGroupId

@description('予算名')
output budgetName string = budgetModule.outputs.budgetName
