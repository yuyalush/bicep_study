// ============================================================
// モジュール: 仮想マシン（パブリック IP なし・Managed Identity あり）
// Step 1 との主な違い:
//   - NIC にパブリック IP を付与しない（Bastion 経由のみでアクセス）
//   - identity ブロックで System-assigned Managed Identity を有効化
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('VM の管理者ユーザー名')
param adminUsername string = 'azureuser'

@description('VM の管理者パスワード')
@secure()
param adminPassword string

@description('VM のサイズ')
param vmSize string = 'Standard_B2ats_v2'

@description('VM を配置するサブネットのリソース ID')
param vmSubnetId string

// ------------------------------------------------------------
// ① NIC（パブリック IP なし）
//    Step 1 では publicIPAddress を ipConfigurations に含めていたが、
//    ここでは省略することで VM をプライベートネットワーク専用にする。
// ------------------------------------------------------------
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vmSubnetId
          }
          // publicIPAddress を指定しない → VM はプライベート IP のみ
        }
      }
    ]
  }
}

// ------------------------------------------------------------
// ② 仮想マシン（System-assigned Managed Identity）
//    identity ブロックを追加することで、Entra ID に
//    サービスプリンシパルが自動登録され、RBAC によって
//    Key Vault 等の Azure サービスへキーレスでアクセスできる。
// ------------------------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${prefix}-vm'
  location: location
  // ── Managed Identity の有効化 ──────────────────────────────
  // type: 'SystemAssigned' で VM に自動的にサービスプリンシパルが付与される。
  // vm.identity.principalId で、そのプリンシパル ID を参照できる。
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        name: '${prefix}-vm-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer:     '0001-com-ubuntu-server-jammy'
        sku:       '22_04-lts-gen2'
        version:   'latest'
      }
    }
    osProfile: {
      computerName:  '${prefix}-vm'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('VM のリソース ID')
output vmId string = vm.id

@description('VM の名前')
output vmName string = vm.name

@description('System-assigned Managed Identity のプリンシパル ID（RBAC ロール付与に使用）')
output vmPrincipalId string = vm.identity.principalId
