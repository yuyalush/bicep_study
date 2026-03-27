# Step 7 — VM バックアップの設定

Step 1 で作成した Linux VM に対して **Azure Backup** を設定するステップです。  
Recovery Services Vault・バックアップポリシーの作成から VM への適用までを Bicep で自動化します。

---

## 学習目標

- `existing` キーワードで既存リソースを参照する方法を理解する
- `parent` プロパティによる階層リソース定義を理解する
- Recovery Services Vault・バックアップポリシー・保護アイテムのリソース構造を理解する
- `dependsOn` を使った明示的な依存関係の定義を理解する

---

## 前提条件

- **Step 1 のデプロイが完了していること**（`rg-bicep-step1` リソースグループに VM が存在すること）
- Step 1 と同じリソースグループ・パラメーター値を使用する

---

## 作成されるリソース構成

```
リソースグループ (rg-bicep-step1)
├── [既存] VM (bicep01-dev-vm)          ← Step 1 で作成済み
└── [新規] Recovery Services Vault (bicep01-dev-rsv)
        └── Backup Policy (bicep01-dev-backup-policy)
                └── Protection Container
                        └── Protected Item  ← VM のバックアップを有効化
```

| リソース種別 | 名前の例 | 説明 |
|---|---|---|
| Recovery Services Vault | `bicep01-dev-rsv` | バックアップデータの保管庫 |
| Backup Policy | `bicep01-dev-backup-policy` | バックアップのスケジュールと保持期間 |
| Protection Container | `iaasvmcontainer;...` | VM ホスト情報の登録 |
| Protected Item | `vm;iaasvmcontainerv2;...` | バックアップ有効化・ポリシー適用 |

---

## バックアップポリシーの設定内容

デフォルトのバックアップポリシーは以下のとおりです。

| 項目 | 設定値 |
|---|---|
| スケジュール | 毎日（Daily） |
| バックアップ実行時刻 | 23:00 UTC（日本時間 翌 8:00） |
| タイムゾーン | Tokyo Standard Time |
| 日次バックアップ保持期間 | **30 日** |
| 週次バックアップ保持期間 | **12 週**（毎週日曜日） |
| 月次バックアップ保持期間 | **12 ヶ月**（毎月第 1 日曜日） |

---

## Tips: ランサムウェア対策 — 不変バックアップ（Immutable Vault）

ランサムウェア攻撃では、感染後にバックアップデータを削除・暗号化して復旧を妨げる手口が増えています。  
Azure Backup の **不変コンテナー（Immutable Vault）** を有効にすると、バックアップデータの削除・変更が  
保護期間中は一切できなくなるため、攻撃者にバックアップを消去されるリスクを排除できます。

### 不変コンテナーの 2 つのモード

| モード | 説明 | 解除 |
|---|---|---|
| **有効（ロックなし）** | バックアップデータの削除・ポリシーの短縮を禁止 | ✅ 後から無効化できる |
| **有効（ロックあり）** | 上記に加えて、不変設定自体の変更・無効化も禁止 | ❌ 一度ロックすると解除不可 |

> **注意**: ロックありモードに設定すると、サブスクリプションの削除以外に解除する方法がありません。  
> 本番環境では運用要件を十分に確認してから有効化してください。

### Bicep での設定方法

`Microsoft.RecoveryServices/vaults` の `securitySettings.immutabilitySettings` プロパティで設定します。

```bicep
resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    securitySettings: {
      immutabilitySettings: {
        // 'Disabled'        : 無効（デフォルト）
        // 'Unlocked'        : 有効（ロックなし）— 後から無効化可能
        // 'Locked'          : 有効（ロックあり）— 解除不可。本番環境推奨
        state: 'Unlocked'
      }
    }
  }
}
```

### ランサムウェア対策としての推奨構成

| 設定 | 推奨値 | 目的 |
|---|---|---|
| 不変コンテナー | `Locked`（本番）/ `Unlocked`（検証） | バックアップの削除・改ざん防止 |
| ソフト削除（Soft Delete） | 有効（デフォルト 14 日） | 誤削除・攻撃後の復旧猶予期間 |
| 多要素認証（MFA） | 有効 | バックアップ操作への追加認証 |
| アクセス制御（RBAC） | 最小権限の原則 | バックアップ管理者ロールの分離 |

> 参考: [Azure Backup のセキュリティ機能](https://learn.microsoft.com/ja-jp/azure/backup/security-overview)  
> 参考: [不変コンテナーの概要](https://learn.microsoft.com/ja-jp/azure/backup/backup-azure-immutable-vault-concept)

---

## 新しく学ぶ Bicep の概念

### 1. `existing` — 既存リソースの参照

`existing` キーワードを使うと、すでに Azure 上にあるリソースを**新規作成せず参照**できます。  
Step 1 で作成した VM をこの方法で参照し、バックアップの設定に利用しています。

```bicep
// 既存 VM の参照（新規作成しない）
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName  // 参照する VM の名前
}

// 参照した VM の id を Protected Item の sourceResourceId に渡す
resource protectedItem '...' = {
  properties: {
    sourceResourceId: vm.id  // ← existing リソースのプロパティも参照できる
  }
}
```

> `existing` で参照するリソースは、同じリソースグループ内に存在する必要があります（別スコープの場合は `scope` プロパティを指定）。

---

### 2. `parent` — 階層リソースの親指定

Azure の多くのリソースは親子関係（階層構造）を持ちます。  
`parent` プロパティを使うと、子リソースの定義内に `parent: <親リソースのシンボル名>` を指定するだけで  
親子関係を明確に表現できます。`name` に親リソースのパスを含める必要がなくなります。

```bicep
// 親リソース
resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  // ...
}

// 子リソース: parent プロパティで親を指定
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: vault              // ← 親リソースのシンボル名を指定
  name: policyName           // ← サブリソース名だけでよい（親パスは不要）
  properties: { ... }
}
```

> `parent` を使わない場合は `name: '${vaultName}/${policyName}'` のように  
> フルパスを文字列補間で組み立てる必要があります（後述の Protection Container の例を参照）。

---

### 3. `dependsOn` — 明示的な依存関係

通常、Bicep はリソース間の参照（シンボル名.プロパティ）から自動的にデプロイ順序を解決します。  
しかし、Protection Container と Protected Item は親子関係の途中に  
名前文字列で参照する `backupFabrics/Azure` が挟まるため、  
シンボル参照だけでは依存関係が解決されません。  
このようなケースでは `dependsOn` で明示的に順序を指定します。

```bicep
resource protectionContainer '...protectionContainers@2024-04-01' = {
  name: '${vaultName}/Azure/${protectionContainerName}'
  // ...
  dependsOn: [vault]   // ← vault が作成されるまで待つ
}

resource protectedItem '...protectedItems@2024-04-01' = {
  name: '${vaultName}/Azure/${protectionContainerName}/${protectedItemName}'
  properties: {
    policyId: backupPolicy.id  // ← backupPolicy への暗黙的依存
    sourceResourceId: vm.id    // ← vm への暗黙的依存
  }
  dependsOn: [protectionContainer]  // ← protectionContainer への明示的依存
}
```

---

## デプロイ手順

### 1. Azure にログイン

```powershell
az login
```

### 2. Step 1 のリソースグループを確認

```powershell
az group show --name rg-bicep-step1
```

### 3. Bicep ファイルを検証（エラーチェック）

```powershell
az deployment group validate `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters adminPassword="YourP@ssw0rd123"
```

### 4. What-if でデプロイ内容をプレビュー

```powershell
az deployment group what-if `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters adminPassword="YourP@ssw0rd123"
```

### 5. デプロイ実行

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters adminPassword="YourP@ssw0rd123"
```

デプロイ後、コンソールに `outputs` が表示されます。

```json
"outputs": {
  "vaultName":        { "value": "bicep01-dev-rsv" },
  "vaultId":          { "value": "/subscriptions/.../bicep01-dev-rsv" },
  "backupPolicyName": { "value": "bicep01-dev-backup-policy" },
  "backupPolicyId":   { "value": "/subscriptions/.../backupPolicies/bicep01-dev-backup-policy" }
}
```

### 6. バックアップの確認

デプロイ後、Azure Portal または Azure CLI でバックアップが設定されていることを確認します。

```powershell
# Recovery Services Vault の一覧表示
az backup vault list `
  --resource-group rg-bicep-step1 `
  --output table

# VM のバックアップ保護状態を確認
az backup item list `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --output table
```

---

## パラメーターをカスタマイズする

バックアップポリシーの設定はパラメーターで変更できます。

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters `
    adminPassword="YourP@ssw0rd123" `
    backupTime="02:00" `
    dailyRetentionDays=90 `
    weeklyRetentionWeeks=52 `
    monthlyRetentionMonths=24
```

| パラメーター | 型 | デフォルト | 説明 |
|---|---|---|---|
| `location` | string | `resourceGroup().location` | リージョン |
| `environment` | string | `dev` | 環境名 (dev / stg / prod) |
| `projectName` | string | `bicep01` | プロジェクト名（プレフィックス） |
| `adminPassword` | securestring | — | VM の管理者パスワード（必須） |
| `backupTime` | string | `23:00` | バックアップ実行時刻（UTC） |
| `dailyRetentionDays` | int | `30` | 日次バックアップの保持日数 |
| `weeklyRetentionWeeks` | int | `12` | 週次バックアップの保持週数 |
| `monthlyRetentionMonths` | int | `12` | 月次バックアップの保持月数 |

---

## リソースの削除

```powershell
# バックアップが設定されている場合、先に保護を停止してバックアップデータを削除する
az backup protection disable `
  --resource-group rg-bicep-step1 `
  --vault-name bicep01-dev-rsv `
  --container-name "iaasvmcontainer;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --item-name "vm;iaasvmcontainerv2;rg-bicep-step1;bicep01-dev-vm" `
  --delete-backup-data true `
  --yes

# Recovery Services Vault を削除（Vault 内が空になってから）
az resource delete `
  --resource-group rg-bicep-step1 `
  --resource-type Microsoft.RecoveryServices/vaults `
  --name bicep01-dev-rsv

# 学習後はリソースグループごと削除してコストを節約
az group delete --name rg-bicep-step1 --yes --no-wait
```

> **注意**: Recovery Services Vault はバックアップアイテムが残っている状態では削除できません。  
> 必ず保護を停止し、バックアップデータを削除してから Vault を削除してください。

---

## トラブルシューティング

### VM が見つからない場合

```
Resource 'bicep01-dev-vm' was not found.
```

Step 1 のデプロイが完了していることを確認してください。  
また、`projectName` と `environment` パラメーターが Step 1 と一致しているか確認してください。

```powershell
# VM の存在確認
az vm show `
  --resource-group rg-bicep-step1 `
  --name bicep01-dev-vm `
  --output table
```

### リソースプロバイダーが未登録の場合

```
The following resource providers are not registered:
Microsoft.RecoveryServices
```

```powershell
az provider register --name Microsoft.RecoveryServices
```

---

## 次のステップ

Step 7 が完了したら、**[Step 8 — バックアップからの復元](../step8-restore/README.md)** に進んでください。  
Step 8 では、ここで設定したバックアップを使って VM を復元する方法（元の場所・別の場所・ディスク復元）と、  
`Microsoft.Resources/deploymentScripts` を使った Bicep による復元の自動化を学びます。

バックアップジョブの監視やポイントインタイムリストア（PITR）も試してみましょう。

- [Azure VM バックアップの概要](https://learn.microsoft.com/ja-jp/azure/backup/backup-azure-vms-introduction)
- [Recovery Services コンテナーの作成](https://learn.microsoft.com/ja-jp/azure/backup/backup-create-rs-vault)

---

## 参考

**Bicep 構文**
- [existing キーワード](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/existing-resource)
- [子リソースの定義](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/child-resource-name-type)
- [dependsOn](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/resource-dependencies)

**リソースリファレンス**
- [Microsoft.RecoveryServices/vaults リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.recoveryservices/vaults)
- [Microsoft.RecoveryServices/vaults/backupPolicies リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.recoveryservices/vaults/backuppolicies)
- [Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems)
