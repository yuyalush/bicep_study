// ============================================================
// モジュール: Action Group（通知先グループ）
// 予算アラートが発火したときの通知先をまとめて管理する。
// ここでは「メール通知」のみを設定する（SMS・Webhook も追加可能）。
//
// スコープ: リソースグループ（main.bicep から scope を指定して呼び出す）
// ============================================================

// Action Group は location: 'global' が必須（japaneast 等の地域は非対応）

@description('リソース名のプレフィックス')
param prefix string

@description('予算超過アラートを受け取るメールアドレス')
param notificationEmail string

// ------------------------------------------------------------
// ① Action Group
//    groupShortName: ポータル通知に表示される短縮名（12 文字以内）
//    emailReceivers: メール通知先の配列
// ------------------------------------------------------------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-budget-ag'
  location: 'global'  // Action Group はグローバルリソース。'global' 以外は使用不可
  properties: {
    // 12 文字以内の短縮名（ポータル・通知メールの件名などに表示）
    groupShortName: 'BudgetAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'BudgetNotification'
        emailAddress: notificationEmail
        // useCommonAlertSchema: true にすると通知フォーマットが統一され
        // 複数アラートを同じ Action Group に束ねやすくなる
        useCommonAlertSchema: true
      }
    ]
  }
}

// ------------------------------------------------------------
// output
// ------------------------------------------------------------

@description('Action Group のリソース ID（budget.bicep に渡す）')
output actionGroupId string = actionGroup.id

@description('Action Group の名前')
output actionGroupName string = actionGroup.name
