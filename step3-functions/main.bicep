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
  }
}

// listKeys(): デプロイ済みリソースのアクセスキーを取得する組み込み関数
// ① az.environment(): Bicep の組み込みネームスペース関数でエンドポイントを取得
// ② resourceId(): モジュール output ではなく var を使い、デプロイ開始時点で解決できる ID を組み立てる
//    → listKeys の第1引数はデプロイ開始時に確定できる値が必要なため
// ※ 本番環境では Managed Identity + Key Vault の利用を推奨
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2023-01-01').keys[0].value}'

// ② Function App（Consumption プラン）
module functionAppModule 'modules/functionApp.bicep' = {
  name: 'deploy-functionApp'
  params: {
    location: location
    functionAppName: functionAppName
    storageConnectionString: storageConnectionString  // @secure() パラメーターへ渡す
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
