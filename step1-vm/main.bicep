// ============================================================
// Step 1: 仮想マシン (VM) の作成
// Bicep の基本構文を学ぶためのサンプルテンプレート
// ============================================================

// ------------------------------------------------------------
// パラメーター (param)
//   テンプレート外から値を受け取る。デプロイ時に上書き可能。
// ------------------------------------------------------------

@description('リソースを作成する Azure リージョン')
param location string = resourceGroup().location

@description('環境名 (dev / stg / prod)')
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@description('プロジェクト名 (リソース名のプレフィックスに使用)')
@minLength(2)
@maxLength(8)
param projectName string = 'bicep01'

@description('VM の管理者ユーザー名')
param adminUsername string = 'azureuser'

@description('VM の管理者パスワード')
@secure()
param adminPassword string

@description('VM のサイズ')
param vmSize string = 'Standard_B2s'

// ------------------------------------------------------------
// 変数 (var)
//   テンプレート内で計算・整形した値を再利用する。
// ------------------------------------------------------------

var prefix         = '${projectName}-${environment}'
var vnetName       = '${prefix}-vnet'
var subnetName     = 'default'
var nsgName        = '${prefix}-nsg'
var publicIpName   = '${prefix}-pip'
var nicName        = '${prefix}-nic'
var vmName         = '${prefix}-vm'
var osDiskName     = '${vmName}-osdisk'
var addressPrefix  = '10.0.0.0/16'
var subnetPrefix   = '10.0.0.0/24'

// ------------------------------------------------------------
// リソース定義 (resource)
//   各 Azure リソースを宣言する。
//   形式: resource <シンボル名> '<プロバイダー>@<APIバージョン>' = { ... }
// ------------------------------------------------------------

// ① ネットワーク セキュリティ グループ (NSG)
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// ② 仮想ネットワーク (VNet) — NSG を参照 (シンボル名.id)
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg.id  // 別リソースの id プロパティを参照 → 暗黙的な依存関係
          }
        }
      }
    ]
  }
}

// ③ パブリック IP アドレス
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ④ ネットワーク インターフェース (NIC)
//    既存リソースのサブネット ID を参照する書き方の例
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'  // 文字列補間で ID を組み立て
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

// ⑤ 仮想マシン (VM)
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id  // NIC の参照 → VM は NIC が作成された後にデプロイされる
        }
      ]
    }
  }
}

// ------------------------------------------------------------
// 出力 (output)
//   デプロイ後に参照できる値を定義する。
// ------------------------------------------------------------

@description('VM のパブリック IP アドレス')
output publicIpAddress string = publicIp.properties.ipAddress

@description('SSH 接続コマンド')
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.ipAddress}'

@description('VM のリソース ID')
output vmResourceId string = vm.id
