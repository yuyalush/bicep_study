# Bicep 学習プロジェクト — コンセプト

## 概要

このプロジェクトは、Azure のインフラストラクチャをコードで管理する **Azure Bicep** の基礎を、段階的なハンズオンを通じて学ぶことを目的としています。  
シンプルな例から始め、実践的なアプリケーション構成へと徐々にステップアップしていきます。

---

## 学習ステップ

### Step 1 — 仮想マシン（VM）の作成

**目標**: Bicep の基本構文を理解し、Azure に VM をデプロイする。

学習内容:
- `resource` 宣言の書き方
- `param` / `var` / `output` の使い方
- 依存リソース（VNet、サブネット、NIC、パブリック IP 等）の定義
- `az deployment group create` によるデプロイ手順

---

### Step 2 — ローカルソースコードを使った Web Apps

**目標**: ローカルのアプリケーションコードを App Service（Web Apps）にデプロイする構成を Bicep で定義する。

学習内容:
- App Service Plan と Web App リソースの定義
- アプリ設定（`appSettings`）の管理
- ZIP デプロイや Run-From-Package を使ったコードのデプロイ
- モジュール（`module`）を使ったリソースの分割・再利用

---

### Step 3 — Azure Functions

**目標**: サーバーレスアーキテクチャを Bicep で構成する。

学習内容:
- Function App と対応するストレージアカウント・App Service Plan の定義
- Consumption プランと Premium プランの違い
- Managed Identity（マネージド ID）を用いたキーレス認証
- identity-based connection（`AzureWebJobsStorage__accountName` 等）の設定
- RBAC ロール割り当て（`Microsoft.Authorization/roleAssignments`）を Bicep で管理する
- 既存の Web Apps 構成との差分・共通点の整理

---

### Step 4 — セキュアな VM 構成（Bastion + Managed Identity）

**目標**: Step 1 で作成した VM 構成を発展させ、パブリック IP を持たないセキュアなアーキテクチャを Bicep で定義する。

学習内容:
- **Azure Bastion**: VM へのパブリックインターネット経由の直接接続を排除し、Azure Portal から安全にアクセスする
- Bastion 専用サブネット（`AzureBastionSubnet`）の要件と NSG ルールの設計
- VM からパブリック IP を除去し、NIC をプライベート接続のみに限定する
- **System-assigned Managed Identity** を VM に付与し、アクセスキー・パスワード不要の Azure サービス連携を実現する
- Key Vault との連携: VM が Managed Identity 経由でシークレットを取得するパターン（`Key Vault Secrets User` ロール）
- Step 1 との Bicep 構文上の差分（追加リソース・削除リソース）の整理

**Step 1 との主な構成変更点**:

| 項目 | Step 1 | Step 4 |
|---|---|---|
| パブリック IP | あり（VM に直接付与） | **なし**（Bastion のみ） |
| SSH/RDP 接続 | インターネット経由で直接 | **Azure Bastion 経由のみ** |
| NSG | SSH(22) 等を開放 | Bastion 必要ポートのみ・VM への直接接続は拒否 |
| VM の ID | なし | **System-assigned Managed Identity** |
| シークレット管理 | パスワードをパラメーターで渡す | Key Vault + RBAC でパスワードレス化を目指す |

---

### Step 5 — コスト分析・予算管理

**目標**: Azure Cost Management のリソースを Bicep でデプロイし、サブスクリプションのコストを継続的に把握・制御する仕組みを構築する。

学習内容:
- **サブスクリプションスコープのデプロイ**: `targetScope = 'subscription'` を使って、リソースグループを超えたスコープに Bicep をデプロイする方法
- **予算アラート**（`Microsoft.Consumption/budgets`）: 月次予算の上限と通知しきい値（例: 80%・100%）を定義し、超過時にメール通知を送る
- **Action Group**（`Microsoft.Insights/actionGroups`）: アラートの通知先（メールアドレス等）を Bicep で管理する
- **コストエクスポート**（`Microsoft.CostManagement/exports`）: コストデータを定期的にストレージアカウントへ CSV 出力し、Power BI や Excel で分析できるようにする
- Step 3・4 で登場した `Microsoft.Authorization/roleAssignments` との組み合わせ: エクスポート先ストレージアカウントへのロール付与

**Step 4 との主な構成変更点**:

| 項目 | Step 1〜4 | Step 5 |
|---|---|---|
| デプロイスコープ | リソースグループ | **サブスクリプション** |
| 対象リソース | コンピューティング・ネットワーク | **コスト管理リソース** |
| Bicep の `targetScope` | `'resourceGroup'`（省略可） | **`'subscription'`** |
| デプロイコマンド | `az deployment group create` | **`az deployment sub create`** |

**構成するリソース**:

```
サブスクリプション
├── Microsoft.Consumption/budgets        # 月次予算（しきい値・通知条件）
├── Microsoft.Insights/actionGroups      # 通知先グループ（メール等）
└── Microsoft.CostManagement/exports     # コストデータの定期エクスポート
    └── 出力先: ストレージアカウント（既存 or 新規作成）
```

---

### Step 6 — ログ収集・監査（Log Analytics / Azure Monitor）

**目標**: Step 1〜4 で構築したリソースの操作ログ・サインインログ・リソース別ログを収集・分析する仕組みを Bicep で構成する。

運用中の Azure 環境では「誰がポータルにログインしたか」「どのリソースを誰が操作したか」の把握がセキュリティ・コンプライアンス上の基本要件です。本ステップでは 4 つのサブステップに分けて、それぞれ異なるアプローチでログ収集を実装します。

---

#### Step 6-1 — Activity Log → Log Analytics Workspace（基盤構築）

**前提条件**: Step 1〜5 が完了していること

**目標**: サブスクリプションの Activity Log を Log Analytics Workspace に転送し、Azure ポータル上での操作履歴を KQL で検索できるようにする。

学習内容:
- `Microsoft.OperationalInsights/workspaces`（Log Analytics Workspace）の作成
- サブスクリプションスコープの診断設定（`microsoft.insights/diagnosticSettings`）による Activity Log 転送
- `AzureActivity` テーブルの KQL クエリで「誰が・いつ・何を操作したか」を把握
- `Administrative`（リソース操作）・`Security`（RBAC 変更）・`Policy` 等のログカテゴリの使い分け

**把握できる操作例**:
- リソースの作成・変更・削除
- RBAC ロールの変更
- Azure Policy の準拠状況変化

---

#### Step 6-2 — Entra ID サインインログ → Log Analytics

**前提条件**: Step 6-1 が完了していること（Log Analytics Workspace が必要）

**目標**: テナントスコープの診断設定を通じて、Entra ID（旧 Azure AD）のサインインログと監査ログを Step 6-1 の Workspace に転送する。ポータルへのログイン追跡に対応する。

学習内容:
- **テナントスコープ** (`targetScope = 'tenant'`): `subscription` よりも上位のスコープ
- `microsoft.aadiam/diagnosticSettings` リソースによるサインインログ転送
- `SignInLogs` テーブルの KQL クエリで「誰が・いつ・どの IP から・ポータルにログインしたか」を把握
- Global Administrator / Security Administrator ロールが必要な操作と Bicep の限界の理解

**注意**: テナントスコープのデプロイには `az deployment tenant create` を使用し、Global Administrator または Security Administrator ロールが必要です。

---

#### Step 6-3 — リソース別 Diagnostic Settings（Step 2〜4 との統合）

**前提条件**: Step 2（Web Apps）・Step 3（Azure Functions）・Step 4（Secure VM + Key Vault）および Step 6-1 が完了していること

**目標**: Step 2〜4 で構築した既存リソースに診断設定を追加し、リソース固有のログ（HTTP アクセスログ・関数実行ログ・Key Vault アクセス履歴等）を Step 6-1 の Workspace に集約する。

学習内容:
- **`existing` キーワード**: 既存リソースへの参照（新規作成ではなく既存取得）
- **`scope` を使ったクロス RG デプロイ**: 異なるリソースグループをまたいだモジュール呼び出し
- Key Vault 監査ログ（`audit` カテゴリ）: 誰がどのシークレットにアクセスしたかの追跡
- App Service / Functions のアクセスログ・実行ログの有効化

| リソース | 重要ログカテゴリ | 目的 |
|---|---|---|
| Key Vault（Step 4） | `audit` | シークレット・キーへのアクセス追跡 |
| Web App（Step 2） | `AppServiceHTTPLogs`, `AppServiceAuditLogs` | HTTP アクセス・FTP ログイン記録 |
| Function App（Step 3） | `FunctionAppLogs` | 関数の実行結果とエラー記録 |

---

#### Step 6-4 — Activity Log → Storage Account（長期アーカイブ）

**前提条件**: Step 1〜5 が完了していること（Step 5 のストレージアカウントを再利用可能）

**目標**: Activity Log をストレージアカウントに直接出力し、長期保存・低コストアーカイブを実現する。Step 6-1（Log Analytics）との使い分けを理解する。

学習内容:
- `storageAccountId` を指定した診断設定による Activity Log のストレージ出力
- ストレージアカウントの `accessTier: 'Cool'` 設定（アーカイブ用途の低コスト化）
- `retentionPolicy` による保持期間の設定
- Step 6-1（Log Analytics）との比較: リアルタイム検索 vs. 長期保存コスト

**Step 6-1 との比較**:

| 観点 | Step 6-1（Log Analytics） | Step 6-4（Storage Account） |
|---|---|---|
| コスト | データ量に比例（比較的高め） | 低コスト（長期保存向き） |
| 検索性 | KQL でリアルタイム検索可能 | Azure Data Explorer / Power BI が必要 |
| 保持期間 | 最大 730 日 | 無制限（Blob ライフサイクル管理で制御） |
| 推奨用途 | 運用監視・アラート | コンプライアンス・長期監査 |

---

## ディレクトリ構成（予定）

```
base_bicep/
├── concept.md          # このファイル
├── step1-vm/           # Step 1: 仮想マシン
│   ├── main.bicep
│   └── README.md
├── step2-webapp/       # Step 2: Web Apps
│   ├── main.bicep
│   ├── modules/
│   └── README.md
├── step3-functions/    # Step 3: Azure Functions
│   ├── main.bicep
│   ├── modules/
│   └── README.md
├── step4-secure-vm/    # Step 4: セキュアな VM 構成（Bastion + Managed Identity）
│   ├── main.bicep
│   ├── modules/
│   └── README.md
└── step5-cost-mgmt/    # Step 5: コスト分析・予算管理
│   ├── main.bicep      # targetScope = 'subscription'
│   ├── modules/
│   └── README.md
└── step6-logging/      # Step 6: ログ収集・監査
    ├── step6-1/        # Activity Log → Log Analytics Workspace
    │   ├── main.bicep  # targetScope = 'subscription'
    │   ├── modules/
    │   │   └── logAnalytics.bicep
    │   └── README.md
    ├── step6-2/        # Entra ID サインインログ → Log Analytics
    │   ├── main.bicep  # targetScope = 'tenant'
    │   └── README.md
    ├── step6-3/        # リソース別 Diagnostic Settings（Step 2〜4 との統合）
    │   ├── main.bicep  # targetScope = 'resourceGroup'
    │   ├── modules/
    │   │   ├── keyVaultDiag.bicep
    │   │   ├── webAppDiag.bicep
    │   │   └── functionsDiag.bicep
    │   └── README.md
    └── step6-4/        # Activity Log → Storage Account（長期アーカイブ）
        ├── main.bicep  # targetScope = 'subscription'
        ├── modules/
        │   └── storageAccountDiag.bicep
        └── README.md
```

---

## 前提条件

- Azure サブスクリプションへのアクセス
- [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli) のインストール
- [Bicep CLI](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/install) のインストール（または Azure CLI 2.20.0 以上）
- VS Code + [Bicep 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep) の導入を推奨

---

## 参考リンク

- [Bicep ドキュメント](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/)
- [Bicep リソースリファレンス](https://learn.microsoft.com/ja-jp/azure/templates/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
