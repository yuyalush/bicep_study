// ============================================================
// モジュール: Azure Bastion
// VM へのセキュアなアクセスを提供する。
// パブリック IP は Bastion にのみ付与し、VM には付与しない。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('AzureBastionSubnet のリソース ID')
param bastionSubnetId string

@description('Bastion SKU。Basic は最小コスト、Standard は追加機能あり')
@allowed(['Basic', 'Standard'])
param bastionSku string = 'Basic'

// ------------------------------------------------------------
// ① Bastion 用パブリック IP
//    Standard SKU・Static 割り当てが必須要件
// ------------------------------------------------------------
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-bastion-pip'
  location: location
  sku: {
    name: 'Standard'  // Bastion には Standard SKU が必須
  }
  properties: {
    publicIPAllocationMethod: 'Static'  // Static が必須
  }
}

// ------------------------------------------------------------
// ② Azure Bastion ホスト
//    Azure Portal のブラウザーから VM に RDP/SSH できるサービス。
//    VM にパブリック IP がなくても、Bastion 経由でアクセス可能。
// ------------------------------------------------------------
resource bastionHost 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: '${prefix}-bastion'
  location: location
  sku: {
    name: bastionSku
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: bastionSubnetId  // AzureBastionSubnet を指定
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('Azure Bastion ホストのリソース ID')
output bastionId string = bastionHost.id

@description('Azure Bastion ホストの名前')
output bastionName string = bastionHost.name

@description('Bastion パブリック IP アドレス')
output bastionPublicIpAddress string = bastionPublicIp.properties.ipAddress
