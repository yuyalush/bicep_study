// ============================================================
// Step 6-3: リソース別 Diagnostic Settings（Step 2〜4 との統合）
//
// Step 2〜4 で作成した既存リソースに診断設定を追加し、
// Step 6-1 で作成した Log Analytics Workspace にログを集約する。
//
// 前提条件:
//   Step 2（Web Apps）・Step 3（Functions）・Step 4（Secure VM / Key Vault）
//   および Step 6-1（Log Analytics Workspace）が完了していること
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group rg-bicep-logging-dev \
//     --template-file main.bicep \
//     --parameters \
//       logAnalyticsWorkspaceId="<Step6-1のworkspaceId>" \
//       keyVaultName="<Step4のKeyVault名>" \
//       keyVaultRgName="<Step4のRG名>" \
//       webAppName="<Step2のWebApp名>" \
//       webAppRgName="<Step2のRG名>" \
//       functionAppName="<Step3のFunctionApp名>" \
//       functionAppRgName="<Step3のRG名>"
// ============================================================

// ------------------------------------------------------------
// ★ リソースグループスコープ（Step 1〜4 と同じデフォルトスコープ）
// ただし各モジュールを scope: resourceGroup(...) で異なる RG に向けることで
// クロス RG デプロイを実現する（下記「新しく学ぶ概念」参照）
// ------------------------------------------------------------
targetScope = 'resourceGroup'

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------
@description('Step 6-1 で作成した Log Analytics Workspace のリソース ID（必須）')
param logAnalyticsWorkspaceId string

@description('Step 4 で作成した Key Vault の名前')
param keyVaultName string

@description('Step 4 の Key Vault があるリソースグループ名')
param keyVaultRgName string

@description('Step 2 で作成した Web App の名前')
param webAppName string

@description('Step 2 の Web App があるリソースグループ名')
param webAppRgName string

@description('Step 3 で作成した Function App の名前')
param functionAppName string

@description('Step 3 の Function App があるリソースグループ名')
param functionAppRgName string

// ------------------------------------------------------------
// Key Vault 診断設定（モジュール）
//
// ★ scope: resourceGroup(keyVaultRgName)
//   Step 4 の RG（デプロイ先 RG とは別）に向けてモジュールを実行する
//   これが「クロス RG デプロイ」: 1 回のデプロイで複数 RG をまたいで設定できる
// ------------------------------------------------------------
module keyVaultDiag 'modules/keyVaultDiag.bicep' = {
  name: 'deploy-keyVaultDiag'
  scope: resourceGroup(keyVaultRgName)  // ← Step 4 の RG を指定
  params: {
    keyVaultName: keyVaultName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

// ------------------------------------------------------------
// Web App 診断設定（モジュール）
// ------------------------------------------------------------
module webAppDiag 'modules/webAppDiag.bicep' = {
  name: 'deploy-webAppDiag'
  scope: resourceGroup(webAppRgName)  // ← Step 2 の RG を指定
  params: {
    webAppName: webAppName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

// ------------------------------------------------------------
// Function App 診断設定（モジュール）
// ------------------------------------------------------------
module functionsDiag 'modules/functionsDiag.bicep' = {
  name: 'deploy-functionsDiag'
  scope: resourceGroup(functionAppRgName)  // ← Step 3 の RG を指定
  params: {
    functionAppName: functionAppName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}
