// ============================================================
// Step 6-4: Activity Log → Storage Account（長期アーカイブ）
//
// サブスクリプションの Activity Log をストレージアカウントに
// 直接エクスポートし、低コストで長期保存する。
//
// Step 6-1（Log Analytics）との使い分け:
//   Log Analytics ... リアルタイム検索・アラート向き（コスト高め）
//   Storage       ... 長期保存・コンプライアンス向き（コスト低め）
//
// 前提条件:
//   Step 1〜5 が完了していること
//   ※ Step 5 のストレージアカウントを再利用する場合は
//     existingStorageAccountId パラメーターを指定する
//
// デプロイコマンド（新規ストレージ作成）:
//   az deployment sub create \
//     --location japaneast \
//     --template-file main.bicep \
//     --parameters location=japaneast
//
// デプロイコマンド（Step 5 のストレージを再利用）:
//   az deployment sub create \
//     --location japaneast \
//     --template-file main.bicep \
//     --parameters \
//       location=japaneast \
//       existingStorageAccountId="<Step5のストレージID>"
// ============================================================

targetScope = 'subscription'

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------
@description('ストレージアカウントを作成するリージョン（新規作成時に使用）')
param location string

@description('環境名')
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@description('プロジェクト名（リソース名のプレフィックス）')
@minLength(2)
@maxLength(8)
param projectName string = 'bicep'

@description('既存ストレージアカウントの ID（省略時は新規作成）')
param existingStorageAccountId string = ''

// ------------------------------------------------------------
// 変数: 既存ストレージを使うか新規作成するかのフラグ
// ------------------------------------------------------------
var useExistingStorage = !empty(existingStorageAccountId)

// ★ 新規作成時のリソース名（モジュール呼び出しと ID 算出の両方で使用）
var newRgName = 'rg-${projectName}-actlog-${environment}'
var newStorageAccountName = 'st${take(replace(projectName, '-', ''), 8)}actlog${environment}'

// ★ any(storage).outputs.storageAccountId を直接参照すると ARM で
//   Object 型として解釈されるエラーが発生するため、
//   既知のパラメーターからリソース ID を文字列として算出する
var resolvedStorageAccountId = useExistingStorage
  ? existingStorageAccountId
  : '/subscriptions/${subscription().subscriptionId}/resourceGroups/${newRgName}/providers/Microsoft.Storage/storageAccounts/${newStorageAccountName}'

// ------------------------------------------------------------
// リソースグループ（新規ストレージ作成時のみ）
// ★ `if (!useExistingStorage)` による条件付きリソース作成
//   Bicep の条件デプロイ: リソース定義に if 条件を付けると
//   条件が false の場合はそのリソースをスキップする
// ------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = if (!useExistingStorage) {
  name: newRgName
  location: location
}

// ------------------------------------------------------------
// ストレージアカウント（モジュール: 新規作成時のみ）
// ★ モジュールにも if 条件を付けられる
// ------------------------------------------------------------
module storage 'modules/storageAccountDiag.bicep' = if (!useExistingStorage) {
  name: 'deploy-storageForActivityLog'
  scope: rg
  params: {
    location: location
    // ストレージアカウント名: 小文字英数字のみ・24文字以内（制約が厳しいため注意）
    storageAccountName: newStorageAccountName
  }
}

// ------------------------------------------------------------
// Activity Log の診断設定（ストレージ出力）
//
// ★ Step 6-1 との違い: workspaceId の代わりに storageAccountId を指定する
//
// retentionPolicy:
//   enabled: true  ... Azure が自動削除を管理する
//   days: 365      ... 365 日後に自動削除（0 = 無期限保持）
//   ★ 長期コンプライアンス要件の場合は days: 0 で無期限 or
//     Storage ライフサイクル管理と組み合わせて tier 移行を設定する
// ------------------------------------------------------------
resource activityLogStorageDiag 'microsoft.insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'activity-log-to-storage'
  properties: {
    storageAccountId: resolvedStorageAccountId
    logs: [
      {
        category: 'Administrative'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'Security'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'ServiceHealth'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'Alert'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'Recommendation'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'Policy'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'Autoscale'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
      {
        category: 'ResourceHealth'
        enabled: true
        retentionPolicy: { enabled: true, days: 365 }
      }
    ]
  }
  // ★ 条件付きモジュール(storage)との依存順序を明示する
  //   resolvedStorageAccountId は文字列計算なので implicit dependency がない
  //   dependsOn で「ストレージ作成後に診断設定を適用」を保証する
  dependsOn: [storage]
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------
output storageAccountId string = resolvedStorageAccountId
output resourceGroupName string = useExistingStorage ? '(既存のRGを使用)' : newRgName
