// ============================================================
// モジュール: エクスポート RBAC
// コストエクスポートの Managed Identity に対して
// Storage Blob Data Contributor ロールをコンテナスコープで付与する。
//
// スコープ: リソースグループ
// （costExport.bicep から scope: resourceGroup(exportRgName) で呼び出される）
// ============================================================

@description('ロールを付与する対象のプリンシパル ID（エクスポートの MI）')
param exportPrincipalId string

@description('エクスポート先ストレージアカウント名')
param storageAccountName string

@description('エクスポート先コンテナ名')
param exportContainerName string

// Storage Blob Data Contributor ロール ID
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ------------------------------------------------------------
// 既存リソースの参照（RBAC scope に使用）
// `existing` キーワードで作成済みのリソースを参照する
// ------------------------------------------------------------
resource existingStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource existingBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: existingStorage
  name: 'default'
}

resource existingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: existingBlobService
  name: exportContainerName
}

// ------------------------------------------------------------
// RBAC ロール割り当て
//    scope: existingContainer = コンテナスコープで最小権限
// ------------------------------------------------------------
resource exportRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingContainer.id, exportPrincipalId, storageBlobDataContributorRoleId)
  scope: existingContainer
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataContributorRoleId
    )
    principalId:   exportPrincipalId
    principalType: 'ServicePrincipal'
  }
}
