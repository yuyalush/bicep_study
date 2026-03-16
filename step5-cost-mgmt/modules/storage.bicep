// ============================================================
// モジュール: ストレージアカウント（コストエクスポート先）
// コストエクスポートの CSV 出力先となるストレージアカウントとコンテナを作成する。
//
// スコープ: リソースグループ
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('ストレージアカウント名（3〜24 文字・英数字のみ）')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('エクスポート CSV を格納するコンテナ名')
param exportContainerName string

// ------------------------------------------------------------
// ① ストレージアカウント
//    accessTier: 'Cool' = アクセス頻度が低い分析データに適したコスト効率の高い設定
//    allowSharedKeyAccess の設定は Azure Policy に委ねる
//    （環境によって Policy が false を強制する場合がある）
// ------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'  // ローカル冗長・最小コスト
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Cool'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// ------------------------------------------------------------
// ② Blob サービス
// ------------------------------------------------------------
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

// ------------------------------------------------------------
// ③ エクスポート先コンテナ
// ------------------------------------------------------------
resource exportContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: exportContainerName
  properties: {
    publicAccess: 'None'  // パブリックアクセス禁止
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('ストレージアカウントのリソース ID')
output storageAccountId string = storageAccount.id

@description('ストレージアカウント名')
output storageAccountName string = storageAccount.name

@description('エクスポート先コンテナ名')
output exportContainerName string = exportContainer.name
