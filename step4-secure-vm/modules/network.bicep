// ============================================================
// モジュール: ネットワーク（VNet / サブネット / NSG）
// Step 1 との最大の違い:
//   - VM サブネット: インターネットからの直接 SSH を拒否
//   - AzureBastionSubnet を追加（Bastion に必須の名前・/26 以上）
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

// VNet / サブネット アドレス空間
var addressPrefix     = '10.0.0.0/16'
var vmSubnetPrefix    = '10.0.0.0/24'
var bastionSubnetPrefix = '10.0.1.0/26'  // /26 以上が Bastion の最小要件

// ------------------------------------------------------------
// ① VM サブネット用 NSG
//    インターネットからの直接接続（SSH/RDP）を禁止し、
//    Azure Bastion からの接続のみ許可する。
// ------------------------------------------------------------
resource vmNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-vm-nsg'
  location: location
  properties: {
    securityRules: [
      {
        // Bastion → VM のポート 22 (SSH) を許可
        // 送信元を VirtualNetwork サービスタグに限定する（インターネットから直接は不可）
        name: 'allow-ssh-from-bastion'
        properties: {
          priority:                 1000
          protocol:                 'Tcp'
          access:                   'Allow'
          direction:                'Inbound'
          sourceAddressPrefix:      'VirtualNetwork'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '22'
        }
      }
      {
        // インターネットからの全インバウンドを明示的に拒否
        // （デフォルトの DenyAllInBound より高い優先度で設定）
        name: 'deny-internet-inbound'
        properties: {
          priority:                 4000
          protocol:                 '*'
          access:                   'Deny'
          direction:                'Inbound'
          sourceAddressPrefix:      'Internet'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
        }
      }
    ]
  }
}

// ------------------------------------------------------------
// ② AzureBastionSubnet 用 NSG
//    Azure Bastion が正常に動作するために必要なルールを定義する。
//    この NSG が不完全だと Bastion が機能しないため注意。
//    参考: https://learn.microsoft.com/azure/bastion/bastion-nsg
// ------------------------------------------------------------
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-bastion-nsg'
  location: location
  properties: {
    securityRules: [
      // ── Inbound ──────────────────────────────────────────
      {
        // クライアントからの HTTPS (443) を許可（ポータル経由のアクセス）
        name: 'allow-https-inbound'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        // Azure Gateway Manager からのヘルスプローブを許可（必須）
        name: 'allow-gateway-manager'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        // Azure Load Balancer のヘルスプローブを許可（必須）
        name: 'allow-azure-load-balancer'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        // Bastion ホスト間の内部通信ポートを許可
        name: 'allow-bastion-host-communication'
        properties: {
          priority: 130
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      // ── Outbound ─────────────────────────────────────────
      {
        // Bastion → VM の SSH/RDP を許可（ターゲット VM への接続）
        name: 'allow-ssh-rdp-outbound'
        properties: {
          priority: 100
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['22', '3389']
        }
      }
      {
        // Bastion → Azure Cloud の HTTPS を許可（診断・管理通信）
        name: 'allow-azure-cloud-outbound'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        // Bastion ホスト間の内部通信ポートを許可
        name: 'allow-bastion-comms-outbound'
        properties: {
          priority: 120
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        // セッション情報取得のための HTTP を許可
        name: 'allow-http-outbound'
        properties: {
          priority: 130
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

// ------------------------------------------------------------
// ③ 仮想ネットワーク（2 サブネット構成）
// ------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        // VM を配置するサブネット
        name: 'default'
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: { id: vmNsg.id }
        }
      }
      {
        // Azure Bastion 専用サブネット
        // 名前は必ず "AzureBastionSubnet" でなければならない
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: { id: bastionNsg.id }
        }
      }
    ]
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('VM サブネットのリソース ID')
output vmSubnetId string = '${vnet.id}/subnets/default'

@description('Bastion サブネットのリソース ID')
output bastionSubnetId string = '${vnet.id}/subnets/AzureBastionSubnet'

@description('VNet のリソース ID')
output vnetId string = vnet.id
