// ============================================================
// モジュール: Function App (Consumption プラン)
// Consumption プラン (Y1/Dynamic) と Function App を作成する。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('Function App の名前（グローバルに一意）')
param functionAppName string

@description('ストレージアカウントの接続文字列（@secure で保護）')
@secure()
param storageConnectionString string

@description('Functions ランタイム')
@allowed(['node', 'python', 'dotnet-isolated', 'java'])
param functionsWorkerRuntime string = 'node'

@description('Node.js のバージョン（ランタイムが node の場合）')
param nodeVersion string = '20'

@description('Functions 拡張バンドルのバージョン')
param functionsExtensionVersion string = '~4'

// ------------------------------------------------------------
// ① Consumption プラン (Y1 / Dynamic)
//    Web Apps の Step 2 との違い:
//      - SKU名: 'Y1', tier: 'Dynamic' → 使った分だけ課金
//      - kind: 'linux' + reserved: true → Linux ベース
// ------------------------------------------------------------
resource consumptionPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'Y1'      // Consumption プランの識別子
    tier: 'Dynamic' // 動的スケーリング
  }
  properties: {
    reserved: true  // Linux では必須
  }
}

// ------------------------------------------------------------
// ② Function App
//    Web App との主な違い:
//      - kind: 'functionapp,linux'
//      - 必須アプリ設定: AzureWebJobsStorage / FUNCTIONS_EXTENSION_VERSION
//                        FUNCTIONS_WORKER_RUNTIME
// ------------------------------------------------------------
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: consumptionPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|${nodeVersion}'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          // Functions の内部処理（トリガー/バインド管理）に使うストレージ
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          // Functions ランタイムのバージョン固定
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: functionsExtensionVersion
        }
        {
          // 使用するランタイム言語を指定
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionsWorkerRuntime
        }
        {
          // Run-From-Package: デプロイした ZIP をマウントして実行
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('Function App のリソース ID')
output functionAppId string = functionApp.id

@description('Function App のホスト名')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('Function App の名前')
output functionAppName string = functionApp.name
