// ============================================================
// Step 3: Azure Functions
// Step 2 のモジュールパターンを継承しながら、
// Functions に固有のリソース（ストレージ）と設定を学ぶ
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
param projectName string = 'bicep03'

@description('Functions ランタイム')
@allowed(['node', 'python', 'dotnet-isolated', 'java'])
param functionsWorkerRuntime string = 'node'

@description('ソースコードをデプロイするユーザーの Object ID。指定すると Storage Blob Data Contributor ロールが自動付与される。az ad signed-in-user show --query id -o tsv で取得。')
param deployingUserObjectId string = ''

// ------------------------------------------------------------
// 変数
// ------------------------------------------------------------

var prefix = '${projectName}-${environment}'

// ストレージアカウント名: 3〜24文字・英数字小文字のみ
// uniqueString で一意性を確保しつつ文字数制限内に収める
var storageAccountName = toLower('st${take(uniqueString(resourceGroup().id), 10)}')

var functionAppName = '${prefix}-func-${uniqueString(resourceGroup().id)}'

// ------------------------------------------------------------
// モジュール呼び出し
// ------------------------------------------------------------

// ① ストレージアカウント（Functions の必須依存）
module storageModule 'modules/storageAccount.bicep' = {
  name: 'deploy-storageAccount'
  params: {
    location: location
    storageAccountName: storageAccountName
    deployingUserObjectId: deployingUserObjectId
  }
}

// ② Function App（Consumption プラン）
// storageModule.outputs.storageAccountId を params で参照しているため、
// Bicep が暗黙的な依存関係を自動設定する（dependsOn 不要）。
//
// Managed Identity 方式では listKeys() / 接続文字列が不要。
// Function App の System-assigned Managed Identity が RBAC 経由でストレージに直接アクセスする。
module functionAppModule 'modules/functionApp.bicep' = {
  name: 'deploy-functionApp'
  params: {
    location: location
    functionAppName: functionAppName
    storageAccountName: storageAccountName                   // Managed Identity 接続用
    storageAccountId: storageModule.outputs.storageAccountId // RBAC ロール割り当て用
    functionsWorkerRuntime: functionsWorkerRuntime
  }
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------

@description('Function App の URL')
output functionAppUrl string = 'https://${functionAppModule.outputs.functionAppHostName}'

@description('Function App の名前')
output functionAppName string = functionAppModule.outputs.functionAppName

@description('ストレージアカウント名')
output storageAccountName string = storageModule.outputs.storageAccountName
