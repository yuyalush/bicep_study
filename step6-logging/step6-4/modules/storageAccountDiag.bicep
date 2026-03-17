// ============================================================
// ストレージアカウント（Activity Log 長期アーカイブ用）
//
// Activity Log をコスト効率よく長期保存するためのストレージ。
// Log Analytics（Step 6-1）と比較して保存コストが低いため
// コンプライアンス要件による長期保存に適している。
// ============================================================

@description('リソースを作成するリージョン')
param location string

@description('ストレージアカウント名（3〜24文字、小文字英数字のみ）')
@minLength(3)
@maxLength(24)
param storageAccountName string

// ------------------------------------------------------------
// ストレージアカウント
//
// ★ Activity Log の長期アーカイブ向け設定ポイント:
//   accessTier: 'Cool'              ... アクセス頻度が低い長期保存に最適（Hot より低コスト）
//   allowBlobPublicAccess: false    ... ログデータの公開アクセスを禁止（セキュリティ必須）
//   supportsHttpsTrafficOnly: true  ... HTTPS のみ許可
//   minimumTlsVersion: 'TLS1_2'    ... TLS 1.2 以上を強制
// ------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'  // ローカル冗長: コスト重視のアーカイブ用途に適切
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Cool'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// ------------------------------------------------------------
// Blob サービス（デフォルト設定の明示）
// Activity Log の出力先 Blob コンテナは Azure が自動生成するが
// Blob サービスの親リソースを定義しておくことで構成が明確になる
// ------------------------------------------------------------
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
