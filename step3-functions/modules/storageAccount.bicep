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

@description('ソースコードをデプロイするユーザーの Object ID（Storage Blob Data Contributor ロールを付与）')
param deployingUserObjectId string = ''

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

// Blob サービスリソース（コンテナー作成の親）
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Function App のデプロイパッケージを格納するコンテナー
// WEBSITE_RUN_FROM_PACKAGE がここにアップロードした ZIP を指定する
resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'deployments'
  properties: {
    publicAccess: 'None'  // パブリックアクセス無効（Managed Identity で読み取る）
  }
}

// デプロイ担当ユーザーへの Blob 操作権限付与（指定時のみ）
// Managed Identity によるキーレス認証環境では、デプロイ用の
// az storage blob upload も AAD 認証（--auth-mode login）を使う。
// そのため、デプロイユーザーにも Storage Blob Data Contributor が必要。
resource deployingUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployingUserObjectId)) {
  name: guid(storageAccount.id, deployingUserObjectId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    // Storage Blob Data Contributor
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: deployingUserObjectId
    principalType: 'User'
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('ストレージアカウントのリソース ID')
output storageAccountId string = storageAccount.id

@description('ストレージアカウント名')
output storageAccountName string = storageAccount.name

@description('デプロイパッケージコンテナー名')
output deploymentContainerName string = deploymentContainer.name
