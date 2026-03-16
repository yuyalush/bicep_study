// ============================================================
// Step 2: ローカルソースコードを使った Web Apps
// module を使ったリソースの分割・再利用を学ぶ
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
param projectName string = 'bicep02'

@description('App Service Plan の SKU')
@allowed(['F1', 'B1', 'B2', 'S1', 'S2', 'P1v3', 'P2v3'])
param skuName string = 'B1'

@description('Linux ランタイムスタック')
param linuxFxVersion string = 'NODE|20-lts'

// ------------------------------------------------------------
// 変数
// ------------------------------------------------------------

var prefix = '${projectName}-${environment}'
var planName = '${prefix}-plan'

// uniqueString(): リソースグループ ID を基にした決定論的な一意文字列(13文字)を生成する
// グローバルに一意な名前が必要なリソース（Web App, Storage Account 等）に使う
var webAppName = '${prefix}-app-${uniqueString(resourceGroup().id)}'

// ------------------------------------------------------------
// モジュール呼び出し (module)
//   形式: module <シンボル名> '<モジュールファイルのパス>' = {
//           name: '<デプロイ操作の名前>'
//           params: { ... }
//         }
// ------------------------------------------------------------

// ① App Service Plan モジュール
module appServicePlanModule 'modules/appServicePlan.bicep' = {
  name: 'deploy-appServicePlan'  // Azure の「デプロイ履歴」に表示される名前
  params: {
    location: location
    planName: planName
    skuName: skuName
  }
}

// ② Web App モジュール
//    appServicePlanModule.outputs.planId でモジュールの output を参照できる
//    → appServicePlanModule が完了するまで webAppModule はデプロイされない（暗黙依存）
module webAppModule 'modules/webApp.bicep' = {
  name: 'deploy-webApp'
  params: {
    location: location
    webAppName: webAppName
    appServicePlanId: appServicePlanModule.outputs.planId   // モジュール出力を参照
    linuxFxVersion: linuxFxVersion
    appSettings: [
      {
        name: 'ENVIRONMENT'
        value: environment
      }
      {
        // Run-From-Package: ZIP ファイルをパッケージとして直接実行するモード
        // ソースコードのデプロイ後に Azure が自動で解凍・実行する
        name: 'WEBSITE_RUN_FROM_PACKAGE'
        value: '1'
      }
      {
        name: 'NODE_ENV'
        value: environment == 'prod' ? 'production' : 'development'  // 三項演算子も使える
      }
    ]
  }
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------

@description('Web App の URL')
output webAppUrl string = 'https://${webAppModule.outputs.webAppHostName}'

@description('Web App のホスト名')
output webAppHostName string = webAppModule.outputs.webAppHostName

@description('App Service Plan の名前')
output appServicePlanName string = appServicePlanModule.outputs.planName
