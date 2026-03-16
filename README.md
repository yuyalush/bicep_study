# Azure Bicep 学習プロジェクト

Azure のインフラをコードで管理する **Azure Bicep** の基礎を、段階的なハンズオンで学ぶプロジェクトです。  
シンプルな VM 作成から始まり、Web Apps・Azure Functions・セキュアなネットワーク構成へとステップアップします。

詳しいコンセプトは [concept.md](concept.md) を参照してください。

---

## 学習ステップ

| ステップ | 内容 | 新しく学ぶ Bicep の概念 |
|---|---|---|
| [Step 1 — 仮想マシン](step1-vm/README.md) | Linux VM のデプロイ | `param` / `var` / `resource` / `output`・リソース間参照・暗黙的な依存関係 |
| [Step 2 — Web Apps](step2-webapp/README.md) | App Service へのアプリデプロイ | `module`・モジュール間 output 参照・`uniqueString()`・`appSettings` |
| [Step 3 — Azure Functions](step3-functions/README.md) | サーバーレス Functions のデプロイ | Managed Identity・RBAC ロール割り当て・identity-based connection・Consumption プラン |
| [Step 4 — セキュアな VM](step4-secure-vm/README.md) | Bastion + Managed Identity による VM | Azure Bastion・Key Vault・パブリック IP 排除・`existing` リソース参照 |
| [Step 5 — コスト分析・予算管理](step5-cost-mgmt/README.md) | 予算アラート・ストレージ・Action Group のデプロイ | `targetScope = 'subscription'`・`az deployment sub create`・モジュールへの `scope` 指定・`utcNow()` の制約・`location: 'global'`・Azure Policy との衝突 |

---

## ディレクトリ構成

```
base_bicep/
├── concept.md              # プロジェクトのコンセプト
├── README.md               # このファイル
├── step1-vm/
│   ├── main.bicep          # VNet / NSG / パブリック IP / NIC / VM
│   └── README.md
├── step2-webapp/
│   ├── main.bicep          # モジュールを呼び出すエントリポイント
│   ├── modules/
│   │   ├── appServicePlan.bicep
│   │   └── webApp.bicep
│   └── README.md
├── step3-functions/
│   ├── main.bicep          # モジュールを呼び出すエントリポイント
│   ├── modules/
│   │   ├── storageAccount.bicep
│   │   └── functionApp.bicep
│   └── README.md
├── step4-secure-vm/
│   ├── main.bicep          # モジュールを呼び出すエントリポイント
│   ├── modules/
│   │   ├── network.bicep   # VNet / サブネット / NSG
│   │   ├── bastion.bicep   # Azure Bastion / パブリック IP
│   │   ├── vm.bicep        # VM（Managed Identity・パブリック IP なし）
│   │   └── keyVault.bicep  # Key Vault / RBAC ロール割り当て
│   └── README.md
└── step5-cost-mgmt/
    ├── main.bicep          # targetScope = 'subscription' のエントリポイント
    ├── modules/
    │   ├── actionGroup.bicep  # 通知先グループ（location: 'global' 固定）
    │   ├── budget.bicep       # 月次予算 / 3段階アラートしきい値
    │   ├── storage.bicep      # ストレージアカウント / Blob コンテナ
    │   ├── costExport.bicep   # コストエクスポート定義（参照用・Policy制約で未使用）
    │   └── exportRbac.bicep   # エクスポート MI へのロール付与（参照用・未使用）
    └── README.md
```

---

## 前提条件

以下のツールをインストールしてください。

```bash
# Azure CLI のバージョン確認
az --version

# Bicep CLI のバージョン確認 (Azure CLI 2.20.0 以上に同梱)
az bicep version
```

- [Azure CLI のインストール](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)
- VS Code + [Bicep 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep) の導入を推奨

---

## クイックスタート

```bash
# 1. Azure にログイン
az login

# 2. リソースグループを作成
az group create --name rg-bicep-step1 --location japaneast

# 3. Step 1 をデプロイ
az deployment group create \
  --resource-group rg-bicep-step1 \
  --template-file step1-vm/main.bicep \
  --parameters adminPassword="YourP@ssw0rd123"
```

各ステップの詳細な手順は、それぞれのディレクトリの **README.md** を参照してください。

---

## 参考リンク

**Bicep 構文**
- [Bicep ドキュメント（概要）](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/overview)
- [Bicep ファイルの構造と構文](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/file)
- [パラメーター](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/parameters)
- [変数](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/variables)
- [出力](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/outputs)
- [モジュール](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/modules)
- [デコレーター](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/parameters#decorators)
- [Bicep 関数リファレンス](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/bicep-functions)

**リソース・その他**
- [Bicep リソースリファレンス](https://learn.microsoft.com/ja-jp/azure/templates/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
