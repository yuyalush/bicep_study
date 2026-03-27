# Step 8 — バックアップからの復元

Step 7 で設定した **Azure Backup** を使って、VM をバックアップから復元するステップです。  
復元の種類（元の場所・別の場所・ディスクのみ）の違いを理解し、Bicep の **デプロイスクリプト**（`deploymentScripts`）で復元を自動化する方法を学びます。

---

## 学習目標

- 3 種類の復元オプション（元の場所・別の場所・ディスク復元）の違いを理解する
- `Microsoft.Resources/deploymentScripts` を使って Bicep から Azure CLI を実行する方法を理解する
- User-Assigned Managed Identity の作成と RBAC ロール割り当てを理解する
- 復元ジョブのモニタリング方法を理解する

---

## 前提条件

- **Step 7 のデプロイが完了していること**（`rg-bicep-step1` に Recovery Services Vault と保護済み VM が存在すること）
- **バックアップジョブが少なくとも 1 回完了していること**（復元ポイントが存在すること）
- `Microsoft.Resources` プロバイダーが登録済みであること（通常はデフォルトで登録済み）

---

## 復元の種類

Azure Backup による VM の復元には 3 種類があります。用途に応じて選択してください。

| 復元タイプ | 概要 | 既存 VM | 新規 VM | 主な用途 |
|---|---|---|---|---|
| **元の場所への復元** (OLR) | 同じ VM のディスクをバックアップ時点に戻す | 上書き | 不要 | 誤操作・データ破損からの復旧 |
| **別の場所への復元** (ALR) | 別の VM 名・リソースグループに復元する | 変更なし | 作成 | 検証環境の複製・障害テスト |
| **ディスクの復元** | ディスクのみ作成し VM は作成しない | 変更なし | 不要 | 特定ファイルの取り出し・カスタム VM への接続 |

> このステップの Bicep テンプレートは**元の場所への復元**を自動化します。  
> 別の場所への復元とディスクの復元は後述の CLI 手順を参照してください。

---

## 作成されるリソース構成

```
リソースグループ (rg-bicep-step1)
├── [既存] Recovery Services Vault (bicep01-dev-rsv)  ← Step 7 で作成済み
├── [既存] VM (bicep01-dev-vm)                        ← Step 1 で作成済み
├── [新規] User-Assigned Managed Identity (bicep01-dev-restore-identity)
│          └── Backup Operator ロール（Vault スコープ）
│          └── Virtual Machine Contributor ロール（RG スコープ）
└── [新規] Deployment Script (bicep01-dev-restore-<一意の文字列>)
           └── 復元ジョブをトリガーし、ジョブ名を出力する
```

| リソース種別 | 名前の例 | 説明 |
|---|---|---|
| User-Assigned Managed Identity | `bicep01-dev-restore-identity` | デプロイスクリプトの認証 ID |
| RBAC ロール割り当て | ─ | Backup Operator（Vault）+ VM Contributor（RG） |
| Deployment Script | `bicep01-dev-restore-<hash>` | 復元ジョブをトリガーする CLI スクリプト |

---

## 新しく学ぶ Bicep の概念

### 1. `Microsoft.Resources/deploymentScripts` — Bicep から CLI を実行

`deploymentScripts` を使うと、Bicep テンプレートの一部として Azure CLI や PowerShell スクリプトを実行できます。  
リソースのプロビジョニングだけでは表現できない**運用アクション**（復元のトリガー・カスタム処理など）を Bicep に組み込む際に使います。

```bicep
resource restoreScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: scriptName
  location: location
  kind: 'AzureCLI'           // 'AzureCLI' または 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.53.0'
    retentionInterval: 'P1D'  // スクリプト完了後、一時リソースを保持する期間
    timeout: 'PT30M'          // スクリプトのタイムアウト（ISO 8601 形式）
    environmentVariables: [   // スクリプトに渡す環境変数
      { name: 'RG_NAME', value: resourceGroup().name }
    ]
    scriptContent: '''
      echo "Hello from deployment script!"
    '''
  }
}
```

> **内部動作**: デプロイスクリプトが実行されると、Azure は一時的なストレージアカウントと  
> Azure Container Instances を自動生成してスクリプトを実行し、`retentionInterval` 後に削除します。

---

### 2. User-Assigned Managed Identity とロール割り当て

デプロイスクリプトが Azure API を呼び出すには、認証 ID が必要です。  
この ID に必要最小限のロールのみを付与することで、最小権限の原則を実現します。

```bicep
// ID の作成
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// Vault スコープに限定したロール割り当て（サブスクリプション全体には付与しない）
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault                // ← 権限の適用スコープを Vault に限定
  name: guid(vault.id, scriptIdentity.id, roleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

---

### 3. `uniqueString()` と `deployment().name` — 再実行可能なスクリプト名

`deploymentScripts` は同じ名前のリソースが既に存在すると、スクリプトを再実行しません（べき等性）。  
`uniqueString()` を使ってデプロイごとに異なる名前を生成することで、毎回スクリプトを実行できます。

```bicep
// デプロイごとに異なるスクリプト名を生成
var scriptName = '${prefix}-restore-${uniqueString(resourceGroup().id, deployment().name)}'
```

---

## デプロイ手順（Bicep による自動復元）

> **注意**: このテンプレートをデプロイすると、VM が自動的に停止され復元ジョブが開始されます。  
> 本番環境では事前にメンテナンスウィンドウを設けてください。

### 1. 復元ポイントの確認

```powershell
az backup recoverypoint list `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --workload-type VM `
  --output table
```

出力例:
```
Name                          Time                      Consistency    Tier
----------------------------  ------------------------  -------------  ------
DefaultPolicy-20241215-230000 2024-12-15T23:00:00+00:00 CrashConsistent Standard
DefaultPolicy-20241214-230000 2024-12-14T23:00:00+00:00 CrashConsistent Standard
```

### 2. Bicep ファイルを検証（エラーチェック）

```powershell
az deployment group validate `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep
```

### 3. What-if でデプロイ内容をプレビュー

```powershell
az deployment group what-if `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep
```

### 4. デプロイ実行（最新の復元ポイントを使用）

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep
```

### 5. 特定の復元ポイントを指定して実行

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters recoveryPointName="DefaultPolicy-20241215-230000"
```

デプロイ後、コンソールに `outputs` が表示されます。

```json
"outputs": {
  "restoreJobName":     { "value": "12345678-abcd-efgh-ijkl-mnopqrstuvwx" },
  "recoveryPointUsed":  { "value": "DefaultPolicy-20241215-230000" },
  "restoreJobStatus":   { "value": "InProgress" }
}
```

---

## 復元ジョブの監視

### リアルタイムで進捗を確認

```powershell
# outputs に表示されたジョブ名を使用
$JOB_NAME = "12345678-abcd-efgh-ijkl-mnopqrstuvwx"

az backup job show `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --name $JOB_NAME `
  --output table
```

### 完了するまで待機

```powershell
az backup job wait `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --name $JOB_NAME
```

> 復元ジョブは通常 **30 分〜数時間** かかります（VM ディスクのサイズや帯域幅による）。

### 最近のジョブ一覧で確認

```powershell
az backup job list `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --output table
```

---

## 復元後の確認

復元ジョブが完了（`Completed`）したら、VM を起動して動作を確認します。

```powershell
# VM を起動
az vm start `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm

# VM の状態確認
az vm get-instance-view `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm `
  --query "instanceView.statuses[].displayStatus" `
  --output table

# SSH で接続して OS レベルの動作確認
$PUBLIC_IP = $(az vm list-ip-addresses `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm `
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" `
  --output tsv)
ssh azureuser@$PUBLIC_IP
```

---

## 手動 CLI による復元手順

Bicep テンプレートを使わずに、Azure CLI で直接復元することもできます。

### パターン A: 元の場所への復元（OLR）

```powershell
# 1. 復元ポイントの確認
az backup recoverypoint list `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --workload-type VM `
  --output table

# 2. VM の停止（元の場所への復元に必要）
az vm deallocate `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm

# 3. 復元トリガー
az backup restore restore-azurevm `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --rp-name "DefaultPolicy-20241215-230000" `
  --restore-mode OriginalLocation

# 4. 復元完了を待機（省略可）
az backup job wait `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --name <ジョブ名>

# 5. VM の起動
az vm start `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm
```

---

### パターン B: 別の場所への復元（ALR）

既存の VM に影響を与えずに、別の VM として復元します。  
検証や障害テストに有効です。

```powershell
# 1. VNet・サブネット名の確認（Step 1 で作成済み）
az network vnet list `
  --resource-group rg-bicep-step1 `
  --output table

# 2. 別の場所への復元トリガー
az backup restore restore-azurevm `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --rp-name "DefaultPolicy-20241215-230000" `
  --restore-mode AlternateLocation `
  --target-resource-group rg-bicep-step1 `
  --target-vm-name bicep01-dev-vm-restored `
  --target-vnet-name bicep01-dev-vnet `
  --target-vnet-resource-group rg-bicep-step1 `
  --target-subnet-name bicep01-dev-subnet
```

---

### パターン C: ディスクの復元

VM は作成せず、マネージドディスクのみを復元します。  
特定ファイルの取り出しやカスタム VM への接続に使います。

```powershell
# 1. ステージング用ストレージアカウントの作成（既存を使う場合は省略）
az storage account create `
  --resource-group rg-bicep-step1 `
  --name bicep01staging$RANDOM `
  --sku Standard_LRS `
  --location japaneast

# 2. ディスク復元トリガー
az backup restore restore-disks `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --rp-name "DefaultPolicy-20241215-230000" `
  --storage-account <ストレージアカウント名>

# 3. 復元されたディスクを既存 VM にアタッチ（例）
az vm disk attach `
  --resource-group rg-bicep-step1 `
  --vm-name bicep01-dev-vm `
  --name <復元されたディスク名>
```

---

## パラメーター一覧

| パラメーター | 型 | デフォルト | 説明 |
|---|---|---|---|
| `location` | string | `resourceGroup().location` | リージョン |
| `environment` | string | `dev` | 環境名 (dev / stg / prod) |
| `projectName` | string | `bicep01` | プロジェクト名（プレフィックス） |
| `recoveryPointName` | string | `""` (最新を自動選択) | 使用する復元ポイント名 |

---

## リソースのクリーンアップ

デプロイスクリプトが作成した Managed Identity は不要になったら削除してください。  
（Deployment Script リソース自体は `retentionInterval` 後に自動削除されます。）

```powershell
# Managed Identity の削除
az identity delete `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-restore-identity

# 別の場所への復元で作成した VM を削除する場合
az vm delete `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm-restored `
  --yes
```

---

## トラブルシューティング

### 復元ポイントが見つからない

```
エラー: 利用可能な復元ポイントがありません。
```

Step 7 のバックアップジョブが完了しているか確認してください。

```powershell
# バックアップジョブの状態確認
az backup job list `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --output table
```

バックアップが設定直後の場合、初回バックアップは**翌 8:00（日本時間）まで実行されません**。  
すぐに試したい場合はオンデマンドバックアップを実行してください。

```powershell
# オンデマンドバックアップの実行
az backup protection backup-now `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --retain-until 30-12-2025 `
  --backup-management-type AzureIaasVM
```

---

### デプロイスクリプトがタイムアウトする

VM の停止に時間がかかる場合、スクリプトの `timeout` 値（デフォルト: `PT30M`）を超えることがあります。

```powershell
# timeout を延長してデプロイ（1時間に設定する例）
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters timeout="PT1H"
```

または、事前に VM を手動停止してからデプロイすることでスクリプトの実行時間を短縮できます。

```powershell
# 事前に VM を停止
az vm deallocate --resource-group rg-bicep-step1 --name bicep01-dev-vm

# その後デプロイ実行
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep
```

---

### デプロイスクリプトのログ確認

デプロイスクリプトが失敗した場合、ログを確認できます（`retentionInterval` 内であれば参照可能）。

```powershell
# デプロイスクリプトのログ表示
az deployment-scripts show-log `
  --resource-group rg-bicep-step1 `
  --name <スクリプト名>
```

---

### ロール割り当てエラー

```
The client does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'
```

デプロイを実行するユーザーに `Owner` または `User Access Administrator` ロールが必要です。

```powershell
# 現在のユーザーのロール確認
az role assignment list `
  --resource-group rg-bicep-step1 `
  --assignee $(az ad signed-in-user show --query id -o tsv) `
  --output table
```

---

## 次のステップ

- 定期的な復元テスト（DR テスト）の自動化を検討してください。
- [Azure Backup のモニタリングとレポート](https://learn.microsoft.com/ja-jp/azure/backup/monitoring-and-alerts-overview) で復元ジョブのアラートを設定できます。

---

## 参考

**Bicep 構文**
- [デプロイスクリプトの概要](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/deployment-script-bicep)
- [デプロイスクリプトで CLI を使用する](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/templates/deployment-script-template)
- [User-Assigned Managed Identity](https://learn.microsoft.com/ja-jp/azure/active-directory/managed-identities-azure-resources/overview)
- [RBAC ロール割り当て（Bicep）](https://learn.microsoft.com/ja-jp/azure/role-based-access-control/role-assignments-bicep)

**Azure Backup 復元**
- [Azure VM の復元オプション](https://learn.microsoft.com/ja-jp/azure/backup/about-azure-vm-restore)
- [Azure Portal から VM を復元する](https://learn.microsoft.com/ja-jp/azure/backup/backup-azure-arm-restore-vms)
- [Azure CLI でバックアップを管理する](https://learn.microsoft.com/ja-jp/azure/backup/backup-azure-vms-automation)
- [az backup restore restore-azurevm リファレンス](https://learn.microsoft.com/ja-jp/cli/azure/backup/restore#az-backup-restore-restore-azurevm)
