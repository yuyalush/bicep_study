// ============================================================
// モジュール: コストエクスポート定義
// コストデータを定期的にストレージアカウントへ CSV 出力する。
//
// ★ targetScope = 'subscription' にする理由
//    Microsoft.CostManagement/exports はサブスクリプション以上のスコープで
//    管理することが推奨されている（コスト集計の対象がサブスクリプション全体のため）
//
// ★ エクスポートの書き込み権限について
//    このテンプレートはエクスポートの「定義」のみ作成する。
//    実際にデータを書き込むには、エクスポートサービスに対して
//    Storage Blob Data Contributor ロールを付与する必要がある。
//    Azure Portal から Export 作成時に「マネージド ID を有効にする」を選択するか、
//    Azure Portal > Cost Management > Export でエクスポート実行時に権限付与できる。
//
// スコープ: サブスクリプション
// ============================================================
targetScope = 'subscription'

@description('リソース名のプレフィックス')
param prefix string

@description('エクスポート先ストレージアカウントのリソース ID')
param storageAccountId string

@description('エクスポート CSV を格納するコンテナ名')
param exportContainerName string

// utcNow() は param のデフォルト値としてのみ使用可能
@description('エクスポート開始日（yyyy-MM-dd 形式）。省略するとデプロイ日時を使用')
param exportStartDate string = utcNow('yyyy-MM-dd')

// ------------------------------------------------------------
// ① コストエクスポート（サブスクリプションスコープ）
//    エクスポート「定義」のみ作成する。
//    実際の書き込みにはストレージアカウントへの RBAC 付与が別途必要。
// ------------------------------------------------------------
resource costExport 'Microsoft.CostManagement/exports@2023-11-01' = {
  name: '${prefix}-monthly-export'
  properties: {
    schedule: {
      status: 'Active'
      recurrence: 'Monthly'
      recurrencePeriod: {
        from: '${exportStartDate}T00:00:00Z'
        to:   '2035-12-31T00:00:00Z'
      }
    }
    format: 'Csv'
    deliveryInfo: {
      destination: {
        resourceId:     storageAccountId
        container:      exportContainerName
        rootFolderPath: 'cost-data'
      }
    }
    definition: {
      type:      'ActualCost'
      timeframe: 'BillingMonthToDate'
      dataSet: {
        granularity: 'Daily'
        configuration: {
          columns: [
            'Date'
            'ResourceId'
            'ResourceGroup'
            'MeterCategory'
            'MeterSubcategory'
            'Quantity'
            'UnitPrice'
            'CostInBillingCurrency'
            'Tags'
          ]
        }
      }
    }
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('コストエクスポート名')
output costExportName string = costExport.name
