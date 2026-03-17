// ============================================================
// Step 6-1: Activity Log → Log Analytics Workspace
//
// サブスクリプションスコープでデプロイし、以下を実現する:
//   1. Log Analytics Workspace の作成
//   2. サブスクリプションの Activity Log を Workspace に転送
//      → Azure ポータル上での操作（誰が・いつ・何を）を KQL で検索可能にする
//
// 前提条件:
//   Step 1〜5 が完了していること
//
// デプロイコマンド:
//   az deployment sub create \
//     --location japaneast \
//     --template-file main.bicep \
//     --parameters location=japaneast
//
// ★ --location はデプロイメタデータの保存先（Step 5 と同様）
//    リソースの実際の作成先は --parameters location=xxx で指定する
// ============================================================

// ------------------------------------------------------------
// ★ サブスクリプションスコープ（Step 5 と同様）
// Activity Log の診断設定はサブスクリプション全体に適用するため
// targetScope = 'subscription' が必要
// ------------------------------------------------------------
targetScope = 'subscription'

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------
@description('Log Analytics Workspace を作成する Azure リージョン（必須）')
param location string

@description('環境名')
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@description('プロジェクト名（リソース名のプレフィックス）')
@minLength(2)
@maxLength(8)
param projectName string = 'bicep'

@description('ログの保持期間（日）: 30〜730')
@minValue(30)
@maxValue(730)
param retentionDays int = 90

// ------------------------------------------------------------
// リソースグループ
// サブスクリプションスコープのため RG を Bicep 内で作成できる（Step 5 と同様）
// ------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${projectName}-logging-${environment}'
  location: location
}

// ------------------------------------------------------------
// Log Analytics Workspace（モジュール）
// RG スコープのリソースはモジュールに分割し scope: rg で呼び出す
// ------------------------------------------------------------
module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'deploy-logAnalytics'
  scope: rg  // ← RG スコープのリソースを RG スコープのモジュールで定義
  params: {
    location: location
    workspaceName: 'log-${projectName}-${environment}'
    retentionDays: retentionDays
  }
}

// ------------------------------------------------------------
// Activity Log の診断設定（サブスクリプションスコープ）
//
// ★ ポイント: scope を指定しない = main.bicep の targetScope (subscription) に従う
//   リソースグループに属さないサブスクリプション全体に適用される設定
//
// 収集カテゴリ:
//   Administrative  ... リソースの作成・変更・削除（最重要: 誰が何をしたか）
//   Security        ... RBAC ロールの変更、Policy 違反検出
//   ServiceHealth   ... Azureサービスの障害・メンテナンス通知
//   Alert           ... Azure Monitor アラートの発火履歴
//   Recommendation  ... Azure Advisor の推奨事項
//   Policy          ... Policy の準拠・非準拠イベント
//   Autoscale       ... オートスケールイベント（スケールアウト・イン）
//   ResourceHealth  ... 個々のリソースの正常性変化
// ------------------------------------------------------------
resource activityLogDiag 'microsoft.insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'activity-log-to-law'
  properties: {
    workspaceId: logAnalytics.outputs.workspaceId
    logs: [
      { category: 'Administrative', enabled: true }
      { category: 'Security', enabled: true }
      { category: 'ServiceHealth', enabled: true }
      { category: 'Alert', enabled: true }
      { category: 'Recommendation', enabled: true }
      { category: 'Policy', enabled: true }
      { category: 'Autoscale', enabled: true }
      { category: 'ResourceHealth', enabled: true }
    ]
  }
}

// ------------------------------------------------------------
// 出力
// Step 6-2〜6-3 でこの Workspace を参照するためにIDを出力する
// ------------------------------------------------------------
output workspaceId string = logAnalytics.outputs.workspaceId
output workspaceName string = logAnalytics.outputs.workspaceName
output resourceGroupName string = rg.name
