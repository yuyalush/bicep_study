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
| [Step 6-1 — Activity Log → Log Analytics](step6-logging/step6-1/README.md) | サブスクリプションの操作履歴を Log Analytics に転送 | サブスクリプションスコープの `diagnosticSettings`・`targetScope = 'subscription'` |
| [Step 6-2 — Entra ID ログ → Log Analytics](step6-logging/step6-2/README.md) | ポータルサインイン履歴を Log Analytics に転送 | `targetScope = 'tenant'`・`az deployment tenant create`・テナントスコープ権限昇格 |
| [Step 6-3 — リソース別診断設定](step6-logging/step6-3/README.md) | Step 2〜4 の既存リソースに診断設定を後付け | `existing` キーワード・クロス RG デプロイ（`scope: resourceGroup()`） |
| [Step 6-4 — Activity Log → Storage](step6-logging/step6-4/README.md) | Activity Log を Storage Account に長期アーカイブ | 条件付きリソース作成（`if` 条件）・`dependsOn` の明示・Cool アクセス層 |
| [Step 7 — VM バックアップの設定](step7-backup/README.md) | Step 1 の VM に Azure Backup を設定 | `existing` キーワード・`parent` プロパティ・Recovery Services Vault・バックアップポリシー |
| [Step 8 — バックアップからの復元](step8-restore/README.md) | Step 7 で取得したバックアップから VM を復元 | `Microsoft.Resources/deploymentScripts`・User-Assigned Managed Identity・RBAC スコープ指定・復元タイプ（OLR / ALR / ディスク） |

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
├── step5-cost-mgmt/
│   ├── main.bicep          # targetScope = 'subscription' のエントリポイント
│   ├── modules/
│   │   ├── actionGroup.bicep  # 通知先グループ（location: 'global' 固定）
│   │   ├── budget.bicep       # 月次予算 / 3段階アラートしきい値
│   │   ├── storage.bicep      # ストレージアカウント / Blob コンテナ
│   │   ├── costExport.bicep   # コストエクスポート定義（参照用・Policy制約で未使用）
│   │   └── exportRbac.bicep   # エクスポート MI へのロール付与（参照用・未使用）
│   └── README.md
└── step6-logging/
    ├── step6-1/
    │   ├── main.bicep          # targetScope = 'subscription' / Activity Log 診断設定
    │   ├── modules/
    │   │   └── logAnalytics.bicep  # Log Analytics Workspace
    │   └── README.md
    ├── step6-2/
    │   ├── main.bicep          # targetScope = 'tenant' / Entra ID 診断設定
    │   └── README.md
    ├── step6-3/
    │   ├── main.bicep          # targetScope = 'resourceGroup' / クロス RG デプロイ
    │   ├── modules/
    │   │   ├── keyVaultDiag.bicep    # Key Vault 診断設定（existing + scope）
    │   │   ├── webAppDiag.bicep      # Web App 診断設定
    │   │   └── functionsDiag.bicep   # Function App 診断設定
    │   └── README.md
    └── step6-4/
        ├── main.bicep          # targetScope = 'subscription' / 条件付きリソース
        ├── modules/
        │   └── storageAccountDiag.bicep  # アーカイブ用ストレージアカウント
        └── README.md
step7-backup/
├── main.bicep                  # existing VM 参照 / Recovery Services Vault / Backup Policy / Protected Item
└── README.md
step8-restore/
├── main.bicep                  # existing Vault 参照 / Managed Identity / RBAC / Deployment Script（復元トリガー）
└── README.md
```

---

## 前提条件

以下のツールをインストールしてください。

```powershell
# Azure CLI のバージョン確認
az --version

# Bicep CLI のバージョン確認 (Azure CLI 2.20.0 以上に同梱)
az bicep version
```

- [Azure CLI のインストール](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)
- VS Code + [Bicep 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep) の導入を推奨

---

## クイックスタート

```powershell
# 1. Azure にログイン
az login

# 2. リソースグループを作成
az group create --name rg-bicep-step1 --location japaneast

# 3. Step 1 をデプロイ
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file step1-vm/main.bicep `
  --parameters adminPassword="YourP@ssw0rd123"
```

各ステップの詳細な手順は、それぞれのディレクトリの **README.md** を参照してください。

---

## PowerShell と Bash の読み替えガイド

本プロジェクトのすべての手順は **PowerShell**（Windows PowerShell / PowerShell 7 以降）を前提に記載しています。  
macOS / Linux 上で Bash（zsh 含む）を使う場合は以下の対応表を参考に読み替えてください。

> **Azure CLI コマンド自体（`az` コマンド）は PowerShell・Bash 共通で使えます。**  
> 変更が必要なのは「改行継続の記号」と「変数の代入構文」の 2 点です。

### 1. 改行継続（複数行コマンド）

| | PowerShell | Bash |
|---|---|---|
| 改行継続文字 | バッククォート `` ` `` | バックスラッシュ `\` |

```powershell
# PowerShell
az deployment group create `
  --resource-group rg-example `
  --template-file main.bicep
```

```bash
# Bash
az deployment group create \
  --resource-group rg-example \
  --template-file main.bicep
```

### 2. 変数への代入と参照

| 操作 | PowerShell | Bash |
|---|---|---|
| 変数への代入 | `$VAR = "value"` | `VAR="value"` |
| コマンド出力を代入 | `$VAR = $(command)` | `VAR=$(command)` |
| 変数の参照 | `$VAR` | `$VAR` |
| 標準出力 | `Write-Host $VAR` または `echo $VAR` | `echo $VAR` |

```powershell
# PowerShell
$WORKSPACE_ID = $(az deployment sub show `
  --name main `
  --query properties.outputs.workspaceId.value `
  -o tsv)
Write-Host $WORKSPACE_ID
```

```bash
# Bash
WORKSPACE_ID=$(az deployment sub show \
  --name main \
  --query properties.outputs.workspaceId.value \
  -o tsv)
echo $WORKSPACE_ID
```

### 3. その他の違い

| 操作 | PowerShell | Bash |
|---|---|---|
| ファイルを ZIP 圧縮 | `Compress-Archive -Path ./app/* -DestinationPath app.zip -Force` | `zip -r app.zip ./app` |
| テキストフィルタ | `Select-String "pattern"` | `grep "pattern"` |
| 文字列の分割 | `$str.Split(".")[0]` | `echo $str \| cut -d. -f1` |
| HTTP リクエスト | `Invoke-RestMethod "https://..."` | `curl https://...` |

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
