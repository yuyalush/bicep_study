// ============================================================
// モジュール: Function App (Consumption プラン)
// Consumption プラン (Y1/Dynamic) と Function App を作成する。
// ストレージへのアクセスには Managed Identity (RBAC) を使用する。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('Function App の名前（グローバルに一意）')
param functionAppName string

@description('接続先ストレージアカウント名')
param storageAccountName string

@description('接続先ストレージアカウントのリソース ID（RBAC ロール割り当てに使用）')
param storageAccountId string

@description('Functions ランタイム')
@allowed(['node', 'python', 'dotnet-isolated', 'java'])
param functionsWorkerRuntime string = 'node'

@description('Node.js のバージョン（ランタイムが node の場合）')
param nodeVersion string = '20'

@description('Functions 拡張バンドルのバージョン')
param functionsExtensionVersion string = '~4'

// ------------------------------------------------------------
// ストレージへの RBAC ロール ID 定義
// Managed Identity にこれら 3 つのロールを付与する
// ------------------------------------------------------------
var storageRoleIds = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'  // Storage Blob Data Owner
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88'  // Storage Queue Data Contributor
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'  // Storage Table Data Contributor
]

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
// ② Function App (System-assigned Managed Identity)
//    identity ブロックで SystemAssigned を指定すると
//    Entra ID にサービスプリンシパルが自動登録される。
//    このプリンシパル ID を使って RBAC ロールを割り当てる。
// ------------------------------------------------------------
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'  // システム割り当てマネージド ID を有効化
  }
  properties: {
    serverFarmId: consumptionPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|${nodeVersion}'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          // Managed Identity 接続方式（identity-based connection）:
          //   "AzureWebJobsStorage" の代わりに
          //   "AzureWebJobsStorage__<プロパティ>" 形式（二重アンダースコア区切り）を使う。
          //   接続文字列・アクセスキーが不要になりセキュリティが向上する。
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          // credential=managedidentity を指定すると
          //   Functions SDK が DefaultAzureCredential でストレージに認証する
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
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
          // Run-From-Package: Blob URL 指定形式（Linux Consumption プランの要件）
          // Managed Identity（Storage Blob Data Owner）で Blob を読み取る。
          // デプロイ後に func.zip を deployments コンテナーにアップロードすることで機能する。
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: 'https://${storageAccountName}.blob.${az.environment().suffixes.storage}/deployments/func.zip'
        }
      ]
    }
  }
}

// ------------------------------------------------------------
// ③ ストレージアカウントへの RBAC ロール割り当て
//    Function App の Managed Identity にストレージ操作権限を付与する。
//    Functions ランタイムは Blob・Queue・Table の 3 サービスを使用する。
//
//    ロール                          | 用途
//    -------------------------------|--------------------------------
//    Storage Blob Data Owner        | トリガー管理・ZIP パッケージ読み込み
//    Storage Queue Data Contributor | Queue トリガー・バインド
//    Storage Table Data Contributor | Table バインド・チェックポイント管理
// ------------------------------------------------------------

// ロール割り当て対象のストレージアカウントを既存リソースとして参照する
resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in storageRoleIds: {
  // guid() で決定論的な一意 ID を生成（再デプロイしても同じ ID が使われる）
  // storageAccountId パラメーターを使うことで main.bicep からの暗黙的な依存関係も維持される
  name: guid(storageAccountId, functionApp.id, roleId)
  scope: storageAccountRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('Function App のリソース ID')
output functionAppId string = functionApp.id

@description('Function App のホスト名')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('Function App の名前')
output functionAppName string = functionApp.name

@description('システム割り当てマネージド ID のプリンシパル ID')
output functionAppPrincipalId string = functionApp.identity.principalId
