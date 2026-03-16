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
    ├── main.bicep      # targetScope = 'subscription'
    ├── modules/
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
