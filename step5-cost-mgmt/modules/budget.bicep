// ============================================================
// モジュール: 予算アラート（Microsoft.Consumption/budgets）
// サブスクリプション全体の月次コストを監視し、
// 設定したしきい値（例: 80% / 100%）を超えたときに
// Action Group 経由でアラートを送信する。
//
// スコープ: サブスクリプション
// （main.bicep で targetScope = 'subscription' が宣言済みのため
//   このモジュールの targetScope 宣言は不要）
// ============================================================

targetScope = 'subscription'

@description('リソース名のプレフィックス')
param prefix string

@description('月次予算の上限額（USD）')
@minValue(1)
param budgetAmountUSD int

@description('アラートしきい値 1 段階目（%）')
@minValue(1)
@maxValue(100)
param alertThreshold1Pct int

@description('アラートしきい値 2 段階目（%）')
@minValue(1)
@maxValue(100)
param alertThreshold2Pct int

@description('通知先 Action Group のリソース ID')
param actionGroupId string

// ------------------------------------------------------------
// utcNow() は param のデフォルト値としてのみ使用可能
// ------------------------------------------------------------

// デプロイ時の年月を自動取得（例: "2026-03"）
// デプロイ実行時に自動でセットされるため、通常は上書き不要
@description('予算開始月（yyyy-MM 形式）。省略するとデプロイ時の年月が使われる')
param startYearMonth string = utcNow('yyyy-MM')

// 月初の ISO 8601 形式の日時文字列（例: "2026-03-01T00:00:00Z"）
var startDate = '${startYearMonth}-01T00:00:00Z'

// ------------------------------------------------------------
// ① 月次予算
//    timeGrain: 'Monthly' = 毎月リセットされる予算
//    notifications: しきい値ごとに個別に設定（最大 5 件）
//
//    【通知タイプの違い】
//    - Actual   : 実際に発生したコストがしきい値を超えたとき（確定コスト）
//    - Forecasted: 予測コストがしきい値を超えそうなとき（早期警告）
// ------------------------------------------------------------
resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: '${prefix}-monthly-budget'
  properties: {
    category: 'Cost'             // 'Cost' のみ（'Usage' は非推奨）
    amount: budgetAmountUSD
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
      // endDate を省略すると無期限。設定する場合は最大 10 年先まで指定可
    }
    notifications: {
      // ---- しきい値 1 段階目（Actual） ----
      Threshold1Actual: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: alertThreshold1Pct  // 例: 80（%）
        thresholdType: 'Actual'
        // contactEmails はスキーマ上必須（空配列も可）
        // 実際の通知は contactGroups（Action Group）経由で行う
        contactEmails: []
        contactGroups: [
          actionGroupId  // Action Group の resourceId を渡す
        ]
      }
      // ---- しきい値 2 段階目（Actual） ----
      Threshold2Actual: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: alertThreshold2Pct  // 例: 100（%）
        thresholdType: 'Actual'
        contactEmails: []
        contactGroups: [
          actionGroupId
        ]
      }
      // ---- 予測超過アラート（Forecasted） ----
      // 月の途中で予測コストが 100% を超えそうな場合に早期警告を送る
      Threshold2Forecasted: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: alertThreshold2Pct
        thresholdType: 'Forecasted'
        contactEmails: []
        contactGroups: [
          actionGroupId
        ]
      }
    }
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('作成した予算のリソース ID')
output budgetId string = budget.id

@description('予算名')
output budgetName string = budget.name
