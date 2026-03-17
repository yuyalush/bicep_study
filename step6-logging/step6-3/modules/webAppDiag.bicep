// ============================================================
// Web App 診断設定
// Step 2 で作成した Web App にログ収集設定を追加する。
//
// ★ Function App も同じリソース型（Microsoft.Web/sites）だが
//   FunctionAppLogs カテゴリが存在しない点が異なる。
//   Function App 向けは functionsDiag.bicep を参照。
// ============================================================

@description('対象の Web App 名（Step 2 でデプロイ済み）')
param webAppName string

@description('ログ送信先の Log Analytics Workspace ID（Step 6-1 の出力）')
param logAnalyticsWorkspaceId string

// ------------------------------------------------------------
// 既存の Web App を参照（existing キーワード）
// このモジュールは scope: resourceGroup(webAppRgName) で呼ばれるため
// 呼び出し元の RG 内の Web App を参照できる。
// ------------------------------------------------------------
resource webApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: webAppName
}

// ------------------------------------------------------------
// Web App の診断設定
//
// 収集カテゴリ:
//   AppServiceHTTPLogs        ... HTTPリクエスト・レスポンスの詳細（ステータスコード等）
//   AppServiceConsoleLogs     ... console.log 等のアプリ標準出力
//   AppServiceAppLogs         ... アプリケーションログ（フレームワーク依存）
//   AppServiceAuditLogs       ... FTP / Kudu（SCM）へのログイン履歴
//   AppServiceIPSecAuditLogs  ... IP 制限ルールによる拒否ログ
//   AppServicePlatformLogs    ... スケールアウト・スロット切り替え等のプラットフォームイベント
// ------------------------------------------------------------
resource webAppDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'webapp-diag-to-law'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        // FTP / Kudu へのログイン追跡（セキュリティ監査に有用）
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
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
output diagnosticSettingsName string = webAppDiagSettings.name
