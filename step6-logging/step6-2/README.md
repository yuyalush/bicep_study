# Step 6-2 — Entra ID サインインログ → Log Analytics

## 学習目標

**テナントスコープ** (`targetScope = 'tenant'`) の Bicep を使って、  
Entra ID のサインインログ・監査ログを Step 6-1 の Log Analytics Workspace に転送し、  
**「誰が・いつ・どの IP から Azure ポータルにログインしたか」** を KQL で追跡できるようにする。

---

## 前提条件

| ステップ | 状態 |
|---|---|
| Step 6-1 | **完了済みであること**（Log Analytics Workspace が必要） |
| Entra ID ロール | **Global Administrator**（elevateAccess の実行に必要） |
| Azure RBAC | ルートスコープ（`/`）の **Owner**（デプロイ前に昇格手順が必要、後述） |
| ライセンス | Entra ID P1/P2（一部カテゴリで必要） |

> ⚠️ **本ステップは Step 6-1 の完了が必須です。**  
> Step 6-1 の出力 `workspaceId` を `logAnalyticsWorkspaceId` パラメーターに指定します。

---

## ファイル構成

```
step6-2/
├── main.bicep   # targetScope = 'tenant' のエントリポイント
└── README.md    # このファイル
```

---

## デプロイ手順

### Step 6-1 の Workspace ID を取得

```powershell
# Step 6-1 のデプロイ出力から Workspace ID を取得
# ★ --name には az deployment sub create 実行時のデプロイ名を指定する
#   --name を省略した場合はテンプレートファイル名（main）が自動的に使われる
$WORKSPACE_ID = $(az deployment sub show `
  --name main `
  --query properties.outputs.workspaceId.value `
  -o tsv)

Write-Host $WORKSPACE_ID
```

### テナントスコープでのデプロイに必要な権限昇格

`az deployment tenant create` は通常の `Owner` / `Contributor` ロールでは実行できません。  
以下の手順でテナントルートスコープへのアクセスを昇格させる必要があります。

#### Step A: elevateAccess でアクセスを昇格させる

```powershell
# Global Administrator として Azure リソース管理へのアクセスを昇格させる
# → ルートスコープ（/）の "User Access Administrator" が一時的に付与される
az rest --method post `
  --url "https://management.azure.com/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"
```

#### Step B: ルートスコープの Owner を自分自身に付与する

`elevateAccess` で得られる権限は `User Access Administrator`（ロール割り当て権限）のみで、  
デプロイ権限（`Microsoft.Resources/deployments/validate/action`）は含まれていません。  
自身に `Owner` を付与する追加手順が必要です。

```powershell
# 自分のオブジェクト ID を確認する
$USER_OBJECT_ID = $(az ad signed-in-user show --query id -o tsv)

# ルートスコープ（"/"）に Owner ロールを付与する
az role assignment create `
  --role "Owner" `
  --assignee-object-id $USER_OBJECT_ID `
  --assignee-principal-type User `
  --scope "/"
```

#### Step C: 再ログインしてトークンを更新する

```powershell
az logout
az login
```

#### Step D: テナントスコープでデプロイ

```powershell
$WORKSPACE_ID = $(az deployment sub show `
  --name main `
  --query properties.outputs.workspaceId.value `
  -o tsv)

az deployment tenant create `
  --location japaneast `
  --template-file main.bicep `
  --parameters logAnalyticsWorkspaceId="$WORKSPACE_ID"
```

#### Step E: デプロイ完了後は昇格した権限を削除する（必須）

> ⚠️ ルートスコープの `Owner` はサブスクリプション・全リソースへの完全な制御権限です。  
> デプロイ完了後は必ず削除してください。

```powershell
# ルートスコープの Owner を削除
az role assignment delete `
  --role "Owner" `
  --assignee $USER_OBJECT_ID `
  --scope "/"
```

Azure Portal で「Microsoft Entra ID」→「プロパティ」→「Azure リソースのアクセス管理」を `いいえ` に戻すことも推奨されます。

---

## 新しく学ぶ Bicep の概念

### テナントスコープ (`targetScope = 'tenant'`)

Bicep が対応するデプロイスコープはリソース範囲が広い順に以下の通りです:

| スコープ | Bicep の宣言 | デプロイコマンド | 主な用途 |
|---|---|---|---|
| **テナント** | `targetScope = 'tenant'` | `az deployment tenant create` | Entra ID 設定・管理グループ |
| サブスクリプション | `targetScope = 'subscription'` | `az deployment sub create` | 予算・コスト管理（Step 5, 6-1） |
| リソースグループ | 省略可（デフォルト） | `az deployment group create` | 一般的なリソース（Step 1〜4） |

```bicep
// テナントスコープの宣言
targetScope = 'tenant'

// テナントスコープ固有のリソース型
resource entraDiag 'microsoft.aadiam/diagnosticSettings@2017-04-01' = {
  name: 'entra-signin-to-law'
  properties: { ... }
}
```

### なぜ Bicep だけでは完結しないのか

Entra ID の診断設定は**テナント全体**に関わる設定のため:
- デプロイに **Global Administrator** ロールが必要（通常の Azure RBAC とは別系統）
- **Entra ID P1/P2 ライセンス**が一部カテゴリで必要
- テナントスコープの Bicep デプロイは企業環境では制限されていることが多い

このような「Bicep で定義できるが環境・権限の制約がある」ケースを理解することも重要な学習です。

---

## 代替手段: Azure CLI によるログ設定

権限や環境の制限により Bicep デプロイが難しい場合、Azure CLI でも同等の設定ができます。

```powershell
# Azure CLI で Entra ID 診断設定を構成する例
$logs = '[{"category":"SignInLogs","enabled":true},{"category":"AuditLogs","enabled":true}]'
az monitor diagnostic-settings create `
  --name "entra-signin-to-law" `
  --resource "/providers/microsoft.aadiam" `
  --workspace $WORKSPACE_ID `
  --logs $logs
```

> CLI でも Global Administrator 権限は必要です。

---

## デプロイ後に試す KQL クエリ

Azure Portal → Log Analytics Workspace → **ログ** から以下を実行してみましょう。

```kql
// ポータルへのサインイン履歴（直近 24 時間）
SigninLogs
| where TimeGenerated > ago(24h)
| project TimeGenerated, UserDisplayName, UserPrincipalName,
          IPAddress, AppDisplayName, ResultType, ResultDescription
| order by TimeGenerated desc
```

```kql
// サインイン失敗の一覧（不正アクセス検知に有用）
SigninLogs
| where ResultType != 0  // 0 = 成功
| project TimeGenerated, UserPrincipalName, IPAddress,
          ResultType, ResultDescription, AppDisplayName
| order by TimeGenerated desc
```

```kql
// 普段と異なる国からのサインイン検出
SigninLogs
| where TimeGenerated > ago(7d)
| summarize Locations = make_set(Location) by UserPrincipalName
| where array_length(Locations) > 1  // 複数の場所からサインインしているユーザー
```

```kql
// ユーザー・グループの変更履歴（監査ログ）
AuditLogs
| where TimeGenerated > ago(24h)
| project TimeGenerated, InitiatedBy, OperationName, Result, TargetResources
| order by TimeGenerated desc
```

```kql
// マネージドID（Step 3・4）のサインイン確認
// ★ Log Analytics のテーブル名は AAD プレフィックス付き
AADManagedIdentitySignInLogs
| where TimeGenerated > ago(24h)
| project TimeGenerated, ServicePrincipalName, ResourceDisplayName, IPAddress
```

---

## 収集されるログカテゴリ

診断設定の**カテゴリ名**（Bicep で指定する値）と Log Analytics の**テーブル名**（KQL で使う名前）は異なります。

| 診断設定カテゴリ名（Bicep） | Log Analytics テーブル名（KQL） | 内容 | ライセンス要件 |
|---|---|---|---|
| `SignInLogs` | `SigninLogs` | ユーザーの対話型サインイン（ポータルへのログイン） | 基本ライセンスで可 |
| `AuditLogs` | `AuditLogs` | ユーザー・グループ・アプリの作成・変更・削除 | 基本ライセンスで可 |
| `NonInteractiveUserSignInLogs` | `AADNonInteractiveUserSignInLogs` | バックグラウンドトークン更新 | **Entra ID P1/P2 必要** |
| `ServicePrincipalSignInLogs` | `AADServicePrincipalSignInLogs` | サービスプリンシパルのサインイン | **Entra ID P1/P2 必要** |
| `ManagedIdentitySignInLogs` | `AADManagedIdentitySignInLogs` | マネージドIDのサインイン（Step 3・4 で設定したもの） | **Entra ID P1/P2 必要** |

> **`SigninLogs` / `AuditLogs` が見つからない場合**  
> これらのテーブルはデータが届いて初めて作成されます。  
> ユーザーがポータルにサインインするか、ディレクトリ変更が発生するまで現れません。  
> `AADManagedIdentitySignInLogs` 等の AAD プレフィックス付きテーブルが先に作成されるのは、  
> Step 3・4 のマネージドIDが Azure サービスへのアクセスを自動的に行っているためです。
