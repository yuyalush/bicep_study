# Step 4 — セキュアな VM 構成（Bastion + Managed Identity）

Step 1 の VM 構成を発展させ、**パブリック IP を持たないゼロトラスト寄りのアーキテクチャ**を Bicep で定義します。  
VM へのアクセスは Azure Portal から Azure Bastion 経由でのみ行い、  
Managed Identity で VM に Key Vault へのキーレスアクセスを付与します。

---

## 学習目標

- **Azure Bastion** の役割と、パブリック IP 直付けとの違いを理解する
- Bastion 専用サブネット（`AzureBastionSubnet`）の名前・サイズ要件と NSG ルールを把握する
- VM からパブリック IP を除去してプライベートネットワーク専用にする方法を学ぶ
- **System-assigned Managed Identity** を VM に付与し、Key Vault へキーレスアクセスする構成を実装する
- `Microsoft.KeyVault/vaults` の `enableRbacAuthorization: true` によるアクセス制御を理解する
- Step 1 との Bicep 構文上の差分（追加・削除リソース）を整理する

---

## ファイル構成

```
step4-secure-vm/
├── main.bicep                  # エントリポイント
├── modules/
│   ├── network.bicep           # VNet / 2 サブネット / NSG x2
│   ├── bastion.bicep           # パブリック IP / Azure Bastion ホスト
│   ├── vm.bicep                # NIC（パブリック IP なし）/ VM（Managed Identity）
│   └── keyVault.bicep          # Key Vault / RBAC ロール割り当て
└── README.md
```

---

## 作成されるリソース構成

```
リソースグループ
├── 仮想ネットワーク (VNet: 10.0.0.0/16)
│   ├── default サブネット (10.0.0.0/24)          ← VM 配置
│   │   └── NSG: インターネットからの直接 SSH を拒否
│   └── AzureBastionSubnet (10.0.1.0/26)           ← Bastion 専用（名前固定）
│       └── NSG: Bastion 必要ポートのみ許可
├── パブリック IP（Bastion 用のみ）
├── Azure Bastion ホスト
├── NIC（パブリック IP なし）
├── 仮想マシン  [System-assigned Managed Identity]
│   └── Managed Identity → Key Vault Secrets User ロール
└── Key Vault（RBAC 認証・ソフト削除有効）
    └── RBAC ロール割り当て: Key Vault Secrets User → VM の Managed Identity
```

---

## Step 1 との比較

| 項目 | Step 1 | Step 4 |
|---|---|---|
| パブリック IP | あり（VM に直接付与） | **Bastion のみ**（VM には付与しない） |
| SSH 接続 | インターネット経由で直接 | **Azure Bastion 経由のみ** |
| NSG | SSH(22) をインターネットに開放 | Bastion → VM 間のみ許可・インターネットは拒否 |
| VM の identity | なし | **System-assigned Managed Identity** |
| Key Vault | なし | RBAC 有効・VM が Secrets User ロールで読み取り |
| モジュール分割 | なし（単一ファイル） | 4 モジュール（network / bastion / vm / keyVault） |

---

## 新しい Bicep の概念

### Azure Bastion とサブネット名の制約

Bastion を配置するサブネットは名前が **`AzureBastionSubnet`** でなければならず、  
サイズは最低 **/26**（64 アドレス）以上が必要です。

```bicep
// サブネット名は必ず "AzureBastionSubnet"
{
  name: 'AzureBastionSubnet'   // ← 変更不可
  properties: {
    addressPrefix: '10.0.1.0/26'  // /26 以上
  }
}
```

---

### VM からパブリック IP を除去する

NIC の `ipConfigurations` から `publicIPAddress` を省略するだけです。

```bicep
// Step 1: パブリック IP あり
properties: {
  ipConfigurations: [{
    properties: {
      subnet: { id: vmSubnetId }
      publicIPAddress: { id: publicIp.id }  // ← これを削除するだけ
    }
  }]
}

// Step 4: パブリック IP なし
properties: {
  ipConfigurations: [{
    properties: {
      subnet: { id: vmSubnetId }
      // publicIPAddress を指定しない → VM はプライベート IP のみ
    }
  }]
}
```

---

### Managed Identity と `tenant()` 関数

VM への `identity` ブロックと、Key Vault の `tenantId` 設定:

```bicep
// VM に System-assigned Managed Identity を付与
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  identity: {
    type: 'SystemAssigned'
  }
  ...
}

// Key Vault: tenant() でデプロイ先テナントの ID を自動取得
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  properties: {
    tenantId: tenant().tenantId       // 現在のテナント ID を自動取得
    enableRbacAuthorization: true     // アクセスポリシー方式を無効化、RBAC のみ
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}
```

---

### Key Vault の RBAC 制御

`enableRbacAuthorization: true` を設定すると、従来の「アクセスポリシー」方式が無効化され、  
Azure RBAC のロール割り当てだけでアクセスを制御します。

| ロール | 権限 | 推奨用途 |
|---|---|---|
| **Key Vault Secrets User** | シークレットの読み取りのみ | **VM（最小権限）** |
| Key Vault Secrets Officer | 読み書き・管理 | アプリ管理者 |
| Key Vault Administrator | 全操作 | インフラ管理者 |

```bicep
// VM の Managed Identity に Key Vault Secrets User を付与
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, vmPrincipalId, '4633458b-17de-408a-b874-0445c86b69e0')
  scope: keyVault  // Key Vault スコープで限定
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e0'  // Key Vault Secrets User
    )
    principalId:   vmPrincipalId
    principalType: 'ServicePrincipal'
  }
}
```

---

## 前提条件

- Azure CLI インストール済み

---

## デプロイ手順

### 1. リソースグループを作成

```powershell
az group create --name rg-bicep-step4 --location japaneast
```

### 2. インフラをデプロイ

```powershell
az deployment group create `
  --resource-group rg-bicep-step4 `
  --template-file main.bicep `
  --parameters adminPassword="YourP@ssw0rd123"
```

### 3. Bastion 経由で VM に接続

1. Azure Portal で VM のリソースページを開く
2. 左メニューの **[接続]** → **[Bastion 経由で接続]** を選択
3. ユーザー名（`azureuser`）とパスワードを入力
4. ブラウザー内で SSH セッションが開く（ポート 22 開放不要）

### 4. VM から Key Vault へアクセスを確認

VM 内のターミナルで以下を実行すると、Managed Identity 経由でトークンを取得できます。

```bash
# Managed Identity でアクセストークンを取得
curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' \
  -H 'Metadata: true' | python3 -m json.tool

# Key Vault シークレットを取得（例）
# ※シークレットは事前に Azure Portal または az CLI で作成しておく
az login --identity
az keyvault secret show --vault-name <keyVaultName> --name <secret-name>
```

### 5. デプロイ出力を確認

```powershell
az deployment group show `
  --resource-group rg-bicep-step4 `
  --name main `
  --query "properties.outputs" `
  --output table
```

---

## リソースの削除

```powershell
az group delete --name rg-bicep-step4 --yes --no-wait
```

> **注意**: Key Vault はソフト削除が有効なため、リソースグループ削除後も  
> 削除済み状態で 7 日間保持されます。同名で再作成する場合は以下で完全削除が必要です。
>
> ```powershell
> az keyvault purge --name <keyVaultName> --location japaneast
> ```

---

## Tips

### SSH キーを使う場合の変更点

現在の構成はパスワード認証ですが、SSH キー（公開鍵認証）に切り替えることでよりセキュアになります。  
必要な変更箇所は `vm.bicep` の `osProfile` と、`main.bicep` のパラメーターの 2 箇所です。

**`main.bicep` のパラメーター変更:**

```bicep
// 変更前: パスワード
@secure()
param adminPassword string

// 変更後: SSH 公開鍵
@description('SSH 公開鍵（ssh-rsa ... 形式）')
@secure()
param adminPublicKey string
```

**`modules/vm.bicep` の `osProfile` 変更:**

```bicep
// 変更前: パスワード認証
osProfile: {
  computerName:  '${prefix}-vm'
  adminUsername: adminUsername
  adminPassword: adminPassword
  linuxConfiguration: {
    disablePasswordAuthentication: false
  }
}

// 変更後: SSH キー認証（パスワード認証を完全無効化）
osProfile: {
  computerName:  '${prefix}-vm'
  adminUsername: adminUsername
  linuxConfiguration: {
    disablePasswordAuthentication: true   // パスワードログインを禁止
    ssh: {
      publicKeys: [
        {
          path:    '/home/${adminUsername}/.ssh/authorized_keys'
          keyData: adminPublicKey  // 公開鍵の内容（ssh-rsa ...）
        }
      ]
    }
  }
}
```

**SSH キーの生成とデプロイ例（PowerShell）:**

```powershell
# SSH キーペアを生成（既にある場合はスキップ）
ssh-keygen -t rsa -b 4096 -f ~/.ssh/bicep04_rsa -N '""'

# 公開鍵の内容を変数に格納
$publicKey = Get-Content ~/.ssh/bicep04_rsa.pub

# デプロイ時に公開鍵を渡す
az deployment group create `
  --resource-group rg-bicep-step4 `
  --template-file main.bicep `
  --parameters adminPublicKey="$publicKey"
```

> **Bastion 経由での SSH キー接続について**  
> Azure Bastion の Basic SKU はブラウザー上のパスワード入力のみ対応です。  
> SSH キーで接続したい場合は **Standard SKU** が必要で、  
> ローカルの秘密鍵ファイルをそのまま使った接続が可能になります（`bastionSku: 'Standard'`）。

---

## 次のステップ（発展的な内容）

- **Private Endpoint**: Key Vault への接続をプライベートネットワーク経由に限定
- **Azure Monitor / Log Analytics**: VM の診断ログ・メトリクスを収集
- **Azure Policy**: Bastion なし VM のデプロイを禁止するポリシー
- **UserAssigned Managed Identity**: 複数 VM で同一 ID を共有する構成

---

## 参考

- [Azure Bastion とは](https://learn.microsoft.com/ja-jp/azure/bastion/bastion-overview)
- [Azure Bastion に必要な NSG ルール](https://learn.microsoft.com/ja-jp/azure/bastion/bastion-nsg)
- [Azure VM のマネージド ID](https://learn.microsoft.com/ja-jp/entra/identity/managed-identities-azure-resources/overview)
- [Key Vault の RBAC 認証](https://learn.microsoft.com/ja-jp/azure/key-vault/general/rbac-guide)
- [Microsoft.Network/bastionHosts リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.network/bastionhosts)
- [Microsoft.KeyVault/vaults リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.keyvault/vaults)
