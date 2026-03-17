// ============================================================
// Step 6-2: Entra ID サインインログ → Log Analytics Workspace
//
// テナントスコープでデプロイし、以下を実現する:
//   - Entra ID（旧 Azure AD）の SignInLogs（ポータルへのログイン）を転送
//   - AuditLogs（ユーザー・グループ・アプリの変更）を転送
//   - その他のサインインカテゴリ（非対話型・サービスプリンシパル・マネージドID）
//
// 前提条件:
//   Step 6-1 が完了し、Log Analytics Workspace が存在すること
//
// デプロイコマンド:
//   az deployment tenant create \
//     --location japaneast \
//     --template-file main.bicep \
//     --parameters logAnalyticsWorkspaceId="<Step6-1の出力workspaceId>"
//
// ★ 必要な権限:
//   - Global Administrator または Security Administrator ロール
//   - az login でテナント管理者アカウントを使用すること
//
// ★ ライセンス要件:
//   - SignInLogs（非対話型・サービスプリンシパル）は Entra ID P1/P2 が必要な場合あり
//   - Microsoft 365 E3/E5 を利用している場合は含まれていることが多い
// ============================================================

// ------------------------------------------------------------
// ★ テナントスコープ
//
// スコープの階層:
//   tenant (最上位)
//     └─ subscription (Step 5, 6-1)
//           └─ resourceGroup (Step 1〜4, 6-3)
//
// Entra ID の診断設定はテナント全体に対して適用されるため
// 'tenant' スコープが必要。 'subscription' より上位のスコープ。
//
// デプロイコマンドも変わる:
//   resourceGroup → az deployment group create
//   subscription  → az deployment sub create
//   tenant        → az deployment tenant create  ← ここ
// ------------------------------------------------------------
targetScope = 'tenant'

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------
@description('Step 6-1 で作成した Log Analytics Workspace のリソース ID（必須）')
param logAnalyticsWorkspaceId string

// ------------------------------------------------------------
// Entra ID 診断設定（テナントスコープ）
//
// ★ microsoft.aadiam/diagnosticSettings はテナントスコープ固有のリソース型
//   resourceGroup・subscription スコープでは使用できない
//
// 収集カテゴリ:
//   SignInLogs                    ... ユーザーの対話型サインイン（ポータルへのログイン）
//   AuditLogs                     ... ユーザー・グループ・アプリの作成・変更・削除
//   NonInteractiveUserSignInLogs  ... MSAL 等がバックグラウンドで行うトークン更新
//   ServicePrincipalSignInLogs    ... アプリやサービスプリンシパルのサインイン
//   ManagedIdentitySignInLogs     ... Step 3・4 で設定したマネージドIDのサインイン
// ------------------------------------------------------------
resource entraDiagSettings 'microsoft.aadiam/diagnosticSettings@2017-04-01' = {
  name: 'entra-signin-to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'SignInLogs'
        enabled: true
      }
      {
        category: 'AuditLogs'
        enabled: true
      }
      {
        // 非対話型サインイン: アプリがユーザーに代わって行うトークン更新等
        // ★ Entra ID P1/P2 ライセンスが必要
        category: 'NonInteractiveUserSignInLogs'
        enabled: true
      }
      {
        // サービスプリンシパルのサインイン: CI/CD パイプライン等の認証
        // ★ Entra ID P1/P2 ライセンスが必要
        category: 'ServicePrincipalSignInLogs'
        enabled: true
      }
      {
        // マネージドIDのサインイン: Step 3・4 で設定した Managed Identity の動作確認に有用
        // ★ Entra ID P1/P2 ライセンスが必要
        category: 'ManagedIdentitySignInLogs'
        enabled: true
      }
    ]
  }
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------
output diagnosticSettingsName string = entraDiagSettings.name
