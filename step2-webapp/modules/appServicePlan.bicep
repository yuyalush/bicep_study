// ============================================================
// モジュール: App Service Plan
// 呼び出し元 (main.bicep) から param を受け取り、
// リソースを作成して output を返す。
// ============================================================

@description('リソースを作成する Azure リージョン')
param location string

@description('App Service Plan の名前')
param planName string

@description('App Service Plan の SKU 名')
@allowed(['F1', 'B1', 'B2', 'S1', 'S2', 'P1v3', 'P2v3'])
param skuName string = 'B1'

// Linux ベースの App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true  // Linux プランでは必須
  }
}

// ------------------------------------------------------------
// output: 呼び出し元が参照できる値を公開する
// ------------------------------------------------------------
@description('App Service Plan のリソース ID')
output planId string = appServicePlan.id

@description('App Service Plan の名前')
output planName string = appServicePlan.name
