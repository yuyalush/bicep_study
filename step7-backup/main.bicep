// ============================================================
// Step 7: VM バックアップの設定
// Step 1 で作成した VM に対して Azure Backup を構成する:
//   - Recovery Services Vault の作成
//   - バックアップポリシーの定義（日次バックアップ・保持期間）
//   - VM へのバックアップ適用（Protection Item の登録）
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group rg-bicep-step1 \
//     --template-file main.bicep \
//     --parameters adminPassword="YourP@ssw0rd123"
//
// ★ Step 1 と同じリソースグループにデプロイすることで
//    既存の VM に対してバックアップを設定できる
// ============================================================

// ------------------------------------------------------------
// パラメーター
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

@description('VM の管理者パスワード（Step 1 と同じ値を指定）')
@secure()
param adminPassword string

@description('日次バックアップを実行する時刻（UTC）例: "23:00"')
param backupTime string = '23:00'

@description('日次バックアップの保持日数')
@minValue(7)
@maxValue(9999)
param dailyRetentionDays int = 30

@description('週次バックアップの保持週数')
@minValue(1)
@maxValue(5163)
param weeklyRetentionWeeks int = 12

@description('月次バックアップの保持月数')
@minValue(1)
@maxValue(1188)
param monthlyRetentionMonths int = 12

// ------------------------------------------------------------
// 変数
// ------------------------------------------------------------

var prefix       = '${projectName}-${environment}'
var vaultName    = '${prefix}-rsv'
var policyName   = '${prefix}-backup-policy'
var vmName       = '${prefix}-vm'

// Recovery Services Vault の保護コンテナー名・保護アイテム名
// 形式は固定: iaasvmcontainer;iaasvmcontainerv2;<RG名>;<VM名>
var protectionContainerName = 'iaasvmcontainer;iaasvmcontainerv2;${resourceGroup().name};${vmName}'
// 形式は固定: vm;iaasvmcontainerv2;<RG名>;<VM名>
var protectedItemName       = 'vm;iaasvmcontainerv2;${resourceGroup().name};${vmName}'

// バックアップ実行時刻（ISO 8601 形式）。日付部分は任意の固定値でよい
var backupScheduleTime = '2024-01-01T${backupTime}:00Z'

// ------------------------------------------------------------
// 既存 VM への参照（Step 1 で作成済み）
// ★ existing キーワード: 新規作成せず既存リソースを参照する
// ------------------------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

// ------------------------------------------------------------
// ① Recovery Services Vault（回復サービス コンテナー）
// Azure Backup と Azure Site Recovery の保管庫
// ------------------------------------------------------------
resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  sku: {
    name: 'RS0'   // Recovery Services sku (Standard)
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// ------------------------------------------------------------
// ② バックアップポリシー（日次スケジュール）
// schedulePolicy: バックアップ実行スケジュール
// retentionPolicy: バックアップデータの保持期間
// ------------------------------------------------------------
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: vault
  name: policyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        backupScheduleTime
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          backupScheduleTime
        ]
        retentionDuration: {
          count: dailyRetentionDays
          durationType: 'Days'
        }
      }
      weeklySchedule: {
        daysOfTheWeek: ['Sunday']
        retentionTimes: [
          backupScheduleTime
        ]
        retentionDuration: {
          count: weeklyRetentionWeeks
          durationType: 'Weeks'
        }
      }
      monthlySchedule: {
        retentionScheduleFormatType: 'Weekly'
        retentionScheduleWeekly: {
          daysOfTheWeek: ['Sunday']
          weeksOfTheMonth: ['First']
        }
        retentionTimes: [
          backupScheduleTime
        ]
        retentionDuration: {
          count: monthlyRetentionMonths
          durationType: 'Months'
        }
      }
    }
    timeZone: 'Tokyo Standard Time'
  }
}

// ------------------------------------------------------------
// ③ バックアップ保護コンテナー（Protection Container）
// Vault 配下に VM ホスト情報を登録する
// ------------------------------------------------------------
resource protectionContainer 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers@2024-04-01' = {
  name: '${vaultName}/Azure/${protectionContainerName}'
  location: location
  properties: {
    containerType: 'IaasVMContainer'
  }
  dependsOn: [vault]
}

// ------------------------------------------------------------
// ④ 保護アイテム（Protected Item）
// VM のバックアップを有効化し、ポリシーを適用する
// ★ このリソースを作成することで VM のバックアップが開始される
// ------------------------------------------------------------
resource protectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = {
  name: '${vaultName}/Azure/${protectionContainerName}/${protectedItemName}'
  location: location
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: backupPolicy.id
    sourceResourceId: vm.id
  }
  dependsOn: [protectionContainer]
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------

@description('Recovery Services Vault のリソース ID')
output vaultId string = vault.id

@description('Recovery Services Vault の名前')
output vaultName string = vault.name

@description('バックアップポリシーのリソース ID')
output backupPolicyId string = backupPolicy.id

@description('バックアップポリシーの名前')
output backupPolicyName string = backupPolicy.name
