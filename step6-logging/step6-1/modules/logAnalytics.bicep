// ============================================================
// Log Analytics Workspace
// サブスクリプションの Activity Log および各リソースのログを
// 一元的に収集・保存するワークスペースを定義する。
// ============================================================

@description('リソースを作成するリージョン')
param location string

@description('Log Analytics Workspace の名前')
param workspaceName string

@description('ログの保持期間（日）: 30〜730')
@minValue(30)
@maxValue(730)
param retentionDays int = 90

// --------------------------------------------------------
// Log Analytics Workspace
// --------------------------------------------------------
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'  // 従量課金（GB 単位）: 最もシンプルで学習・検証向き
    }
    retentionInDays: retentionDays
    features: {
      // リソース権限モード: 各リソースのデータへのアクセスをリソース権限で制御する
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// --------------------------------------------------------
// 出力
// --------------------------------------------------------
output workspaceId string = workspace.id
output workspaceName string = workspace.name

// customerId: KQL クエリや外部ツールから Workspace を識別する GUID
output customerId string = workspace.properties.customerId
