// ============================================================
// Key Vault 診断設定
// Step 4 で作成した Key Vault にログ収集設定を追加する。
//
// ★ 主な学習ポイント:
//   1. `existing` キーワードで既存リソースを参照する
//   2. `scope: keyVault` で診断設定を既存リソースに紐付ける
// ============================================================

@description('対象の Key Vault 名（Step 4 でデプロイ済み）')
param keyVaultName string

@description('ログ送信先の Log Analytics Workspace ID（Step 6-1 の出力）')
param logAnalyticsWorkspaceId string

// ------------------------------------------------------------
// ★ existing キーワード: 既存リソースへの参照
//
// 新しくリソースを作成するのではなく、Step 4 で作成済みの
// Key Vault を「参照」して診断設定の scope に使用する。
//
// このモジュールは scope: resourceGroup(keyVaultRgName) で呼ばれるため
// 呼び出し元の RG 内の Key Vault を参照できる。
// ------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// ------------------------------------------------------------
// Key Vault の診断設定
//
// ★ scope: keyVault と指定することで、この診断設定が
//   Key Vault のサブリソース（子リソース）として追加される。
//
// 収集カテゴリ:
//   audit    ... シークレット・キー・証明書への get/set/delete 操作
//               「誰がどのシークレットを取得したか」の追跡に必要不可欠
//   allLogs  ... audit に加えたすべての操作ログ（必要に応じて有効化）
// ------------------------------------------------------------
resource keyVaultDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'kv-diag-to-law'
  scope: keyVault  // ← 既存リソースをスコープに指定（サブリソースとして追加）
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        // audit: シークレット・キー・証明書の操作ログ（推奨: 常に有効）
        categoryGroup: 'audit'
        enabled: true
      }
      {
        // allLogs: audit を内包するすべての操作 (必要に応じて有効化)
        categoryGroup: 'allLogs'
        enabled: false
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
output diagnosticSettingsName string = keyVaultDiagSettings.name
