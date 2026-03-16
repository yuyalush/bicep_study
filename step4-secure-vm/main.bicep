// ============================================================
// Step 4: セキュアな VM 構成（Bastion + Managed Identity）
// Step 1 の VM 構成を発展させ、以下を実現する:
//   - VM にパブリック IP を付与せず、外部からの直接接続を禁止
//   - Azure Bastion 経由でのみ VM にアクセス可能（Azure Portal から操作）
//   - System-assigned Managed Identity で VM に Azure サービスへのキーレスアクセスを付与
//   - Key Vault に VM の Managed Identity でアクセスできる構成
// ============================================================

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------

@description('リソースを作成する Azure リージョン')
param location string = resourceGroup().location

@description('環境名')
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@description('プロジェクト名 (リソース名のプレフィックス)')
@minLength(2)
@maxLength(8)
param projectName string = 'bicep04'

@description('VM の管理者ユーザー名')
param adminUsername string = 'azureuser'

@description('VM の管理者パスワード')
@secure()
param adminPassword string

@description('VM のサイズ')
param vmSize string = 'Standard_B2ats_v2'

@description('Azure Bastion の SKU')
@allowed(['Basic', 'Standard'])
param bastionSku string = 'Basic'

// ------------------------------------------------------------
// 変数
// ------------------------------------------------------------

var prefix = '${projectName}-${environment}'

// Key Vault 名: 3〜24 文字・英数字とハイフン・グローバル一意
var keyVaultName = 'kv-${take(uniqueString(resourceGroup().id), 16)}'

// ------------------------------------------------------------
// モジュール呼び出し
// ------------------------------------------------------------

// ① ネットワーク（VNet・2サブネット・NSG）
module networkModule 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    prefix:   prefix
  }
}

// ② Azure Bastion（パブリック IP + Bastion ホスト）
//    networkModule.outputs.bastionSubnetId を参照 → 暗黙的に network の後にデプロイ
module bastionModule 'modules/bastion.bicep' = {
  name: 'deploy-bastion'
  params: {
    location:        location
    prefix:          prefix
    bastionSubnetId: networkModule.outputs.bastionSubnetId
    bastionSku:      bastionSku
  }
}

// ③ VM（パブリック IP なし・System-assigned Managed Identity）
//    networkModule.outputs.vmSubnetId を参照 → 暗黙的に network の後にデプロイ
module vmModule 'modules/vm.bicep' = {
  name: 'deploy-vm'
  params: {
    location:      location
    prefix:        prefix
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize:        vmSize
    vmSubnetId:    networkModule.outputs.vmSubnetId
  }
}

// ④ Key Vault（RBAC 有効・VM の Managed Identity に Secrets User ロールを付与）
//    vmModule.outputs.vmPrincipalId を参照 → 暗黙的に VM の後にデプロイ
module keyVaultModule 'modules/keyVault.bicep' = {
  name: 'deploy-keyVault'
  params: {
    location:      location
    keyVaultName:  keyVaultName
    vmPrincipalId: vmModule.outputs.vmPrincipalId
  }
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------

@description('VM のリソース ID')
output vmId string = vmModule.outputs.vmId

@description('VM の名前（Azure Portal の Bastion 接続画面で使用）')
output vmName string = vmModule.outputs.vmName

@description('VM の Managed Identity プリンシパル ID')
output vmPrincipalId string = vmModule.outputs.vmPrincipalId

@description('Azure Bastion ホストの名前')
output bastionName string = bastionModule.outputs.bastionName

@description('Key Vault の URI（VM からシークレットを取得する際に使用）')
output keyVaultUri string = keyVaultModule.outputs.keyVaultUri

@description('Key Vault の名前')
output keyVaultName string = keyVaultModule.outputs.keyVaultName
