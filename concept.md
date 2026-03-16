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
- Azure Functions のアプリ設定（`AzureWebJobsStorage` 等）
- 既存の Web Apps 構成との差分・共通点の整理

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
└── step3-functions/    # Step 3: Azure Functions
    ├── main.bicep
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
