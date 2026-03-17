// ============================================================
// Function App 診断設定
// Step 3 で作成した Function App にログ収集設定を追加する。
//
// ★ Function App は Microsoft.Web/sites と同じリソース型だが
//   FunctionAppLogs カテゴリが追加で使用できる（Web App にはない）。
// ============================================================

@description('対象の Function App 名（Step 3 でデプロイ済み）')
param functionAppName string

@description('ログ送信先の Log Analytics Workspace ID（Step 6-1 の出力）')
param logAnalyticsWorkspaceId string

// ------------------------------------------------------------
// 既存の Function App を参照（existing キーワード）
// ★ Function App は Web App と同じ Microsoft.Web/sites 型
//   kind プロパティで Function App と Web App が区別される
// ------------------------------------------------------------
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

// ------------------------------------------------------------
// Function App の診断設定
//
// ★ プランによるカテゴリ対応の違い:
//   Consumption プラン ... FunctionAppLogs のみサポート
//   Dedicated / Premium プラン ... App Service 系カテゴリも追加可能
//     （AppServiceHTTPLogs, AppServiceConsoleLogs, AppServiceAuditLogs 等）
//
// 収集カテゴリ:
//   FunctionAppLogs  ... ★ 関数の実行結果・エラーログ（全プランで対応）
// ------------------------------------------------------------
resource functionsDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'func-diag-to-law'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        // ★ Function App 固有のカテゴリ: 全プランで対応
        category: 'FunctionAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------
output diagnosticSettingsName string = functionsDiagSettings.name
