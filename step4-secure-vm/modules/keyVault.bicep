// ============================================================
// モジュール: Key Vault
// VM の Managed Identity に対し Key Vault Secrets User ロールを付与し、
// VM がアクセスキー不要でシークレットを取得できる構成を実現する。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('Key Vault の名前（3〜24 文字の英数字とハイフン、グローバル一意）')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('VM の Managed Identity プリンシパル ID（ロール付与対象）')
param vmPrincipalId string

// ------------------------------------------------------------
// ① Key Vault
//    enableRbacAuthorization: true を指定するとアクセスポリシー方式が無効化され、
//    RBAC（ロール割り当て）のみでアクセス制御するセキュアな構成になる。
// ------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'  // standard / premium（HSM 保護が必要な場合は premium）
    }
    tenantId: tenant().tenantId  // 現在のテナント ID を自動取得
    // アクセスポリシー方式ではなく RBAC で制御する（推奨方式）
    enableRbacAuthorization: true
    // ソフト削除を有効化（誤削除からの復旧用）
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // パブリックアクセスを許可（学習用途）
    // 本番環境では publicNetworkAccess: 'Disabled' + Private Endpoint が推奨
    publicNetworkAccess: 'Enabled'
  }
}

// ------------------------------------------------------------
// ② RBAC ロール割り当て: Key Vault Secrets User
//    VM の Managed Identity がシークレットを「読み取る」のに必要な最小権限。
//    シークレットの書き込みは不要のため、より権限の強い
//    Key Vault Secrets Officer は使わない（最小権限の原則）。
//
//    ロール ID 一覧（参考）:
//      Key Vault Secrets User     : 4633458b-17de-408a-b874-0445c86b69e6（読み取りのみ）
//      Key Vault Secrets Officer  : b86a8fe4-44ce-4948-aee5-eccb2c155cd7（読み書き）
//      Key Vault Administrator    : 00482a5a-887f-4fb3-b363-3b7fe8e74483（全操作）
// ------------------------------------------------------------
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // guid() で決定論的な一意 ID を生成（冪等デプロイに対応）
  name: guid(keyVault.id, vmPrincipalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault  // Key Vault スコープで権限を限定
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'  // Key Vault Secrets User
    )
    principalId:   vmPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('Key Vault のリソース ID')
output keyVaultId string = keyVault.id

@description('Key Vault の URI（シークレット取得に使用）')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault の名前')
output keyVaultName string = keyVault.name
