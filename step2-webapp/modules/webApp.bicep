// ============================================================
// モジュール: Web App
// App Service Plan の ID を受け取って Web App を作成する。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('Web App の名前（Azure 全体でグローバルに一意）')
param webAppName string

@description('App Service Plan のリソース ID')
param appServicePlanId string

@description('Linux ランタイムスタック (例: NODE|20-lts, PYTHON|3.12, DOTNETCORE|8.0)')
param linuxFxVersion string = 'NODE|20-lts'

// アプリケーション設定を配列で受け取る
// 型: { name: string, value: string }[] の構造体配列
@description('アプリケーション設定 (環境変数)')
param appSettings array = []

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlanId       // App Service Plan と関連付け
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      ftpsState: 'Disabled'              // FTP は無効化（セキュリティベストプラクティス）
      minTlsVersion: '1.2'
      appSettings: appSettings
    }
  }
}

@description('Web App のデフォルトホスト名 (例: myapp.azurewebsites.net)')
output webAppHostName string = webApp.properties.defaultHostName

@description('Web App のリソース ID')
output webAppId string = webApp.id
