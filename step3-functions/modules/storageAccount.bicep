// ============================================================
// モジュール: ストレージアカウント
// Azure Functions が内部処理（トリガー管理・ログ等）に使う
// ストレージアカウントを作成する。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('ストレージアカウント名（3〜24 文字の英数字小文字、グローバル一意）')
@minLength(3)
@maxLength(24)
param storageAccountName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'  // ローカル冗長ストレージ（Functions 用途では十分）
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true    // HTTPS 通信のみ許可
    minimumTlsVersion: 'TLS1_2'      // TLS 1.2 以上を必須化
    allowBlobPublicAccess: false      // パブリックアクセスを無効化
    accessTier: 'Hot'
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('ストレージアカウントのリソース ID')
output storageAccountId string = storageAccount.id

@description('ストレージアカウント名')
output storageAccountName string = storageAccount.name
