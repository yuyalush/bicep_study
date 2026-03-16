# Step 1 — 仮想マシン（VM）の作成

Bicep の基本構文を学びながら、Azure に Linux VM をデプロイするステップです。

---

## 学習目標

- `param` / `var` / `output` の役割と書き方を理解する
- `resource` ブロックで Azure リソースを宣言する方法を理解する
- リソース間の参照（シンボル名 + `.id`）と暗黙的な依存関係を理解する
- `az deployment group create` を使ったデプロイの流れを体験する

---

## 作成されるリソース構成

```
リソースグループ
└── VNet (10.0.0.0/16)
    └── Subnet: default (10.0.0.0/24)
        └── NSG ─── NIC ─── VM
                     └── パブリック IP
```

| リソース種別 | 名前の例 |
|---|---|
| ネットワーク セキュリティ グループ | `bicep01-dev-nsg` |
| 仮想ネットワーク | `bicep01-dev-vnet` |
| パブリック IP アドレス | `bicep01-dev-pip` |
| ネットワーク インターフェース | `bicep01-dev-nic` |
| 仮想マシン | `bicep01-dev-vm` |

---

## Bicep の基本構文ガイド

### `param` — パラメーター

テンプレートの外から値を受け取ります。デプロイ時に上書き可能です。

```bicep
@description('説明文')
param location string = resourceGroup().location  // デフォルト値あり

@secure()
param adminPassword string  // デフォルト値なし（デプロイ時に必須入力）
```

デコレーター（`@description`, `@secure`, `@allowed`, `@minLength` など）で制約や説明を付加できます。

---

### `var` — 変数

テンプレート内で値を計算・整形して再利用します。外部から変更できません。

```bicep
var prefix   = '${projectName}-${environment}'  // 文字列補間
var vmName   = '${prefix}-vm'
```

---

### `resource` — リソース定義

Azure リソースを宣言します。

```bicep
resource <シンボル名> '<リソースタイプ>@<API バージョン>' = {
  name: <リソース名>
  location: location
  properties: {
    // リソース固有の設定
  }
}
```

**シンボル名**はテンプレート内での参照に使います（Azure 上のリソース名とは別物）。

---

### リソース間参照と暗黙的な依存関係

別リソースのプロパティは **シンボル名.プロパティ** で参照できます。  
この参照を書くだけで、Bicep が自動的に正しいデプロイ順序を判断します（`dependsOn` 不要）。

```bicep
// NIC が VNet/Subnet の後にデプロイされることが自動保証される
resource nic '...' = {
  properties: {
    ipConfigurations: [{
      properties: {
        subnet: {
          id: '${vnet.id}/subnets/${subnetName}'  // vnet シンボルを参照
        }
      }
    }]
  }
}
```

---

### `output` — 出力

デプロイ後に値を参照できます。他テンプレートへの連携にも使います。

```bicep
output publicIpAddress string = publicIp.properties.ipAddress
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.ipAddress}'
```

---

## 前提条件

- Azure CLI がインストール済みであること (`az --version`)
- Bicep CLI が Azure CLI に含まれていること (`az bicep version`)
- デプロイ先のリソースグループが存在すること

---

## デプロイ手順

### 1. Azure にログイン

```bash
az login
```

### 2. リソースグループを作成

```bash
az group create \
  --name rg-bicep-step1 \
  --location japaneast
```

### 3. Bicep ファイルを検証（エラーチェック）

```bash
az deployment group validate \
  --resource-group rg-bicep-step1 \
  --template-file main.bicep \
  --parameters adminPassword="YourP@ssw0rd123"
```

### 4. What-if でデプロイ内容をプレビュー

```bash
az deployment group what-if \
  --resource-group rg-bicep-step1 \
  --template-file main.bicep \
  --parameters adminPassword="YourP@ssw0rd123"
```

### 5. デプロイ実行

```bash
az deployment group create \
  --resource-group rg-bicep-step1 \
  --template-file main.bicep \
  --parameters adminPassword="YourP@ssw0rd123"
```

デプロイ後、コンソールに `outputs` が表示されます。

```json
"outputs": {
  "sshCommand": { "value": "ssh azureuser@xx.xx.xx.xx" },
  "publicIpAddress": { "value": "xx.xx.xx.xx" }
}
```

### 6. SSH で接続確認

```bash
ssh azureuser@<publicIpAddress>
```

---

## パラメーターをカスタマイズする

コマンドラインで個別指定:

```bash
az deployment group create \
  --resource-group rg-bicep-step1 \
  --template-file main.bicep \
  --parameters projectName=myapp environment=dev adminPassword="YourP@ssw0rd123"
```

パラメーターファイル (`parameters.json`) を使う方法:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "projectName": { "value": "myapp" },
    "environment": { "value": "dev" },
    "adminPassword": { "value": "YourP@ssw0rd123" }
  }
}
```

```bash
az deployment group create \
  --resource-group rg-bicep-step1 \
  --template-file main.bicep \
  --parameters @parameters.json
```

---

## リソースの削除

学習後はリソースグループごと削除してコストを節約できます。

```bash
az group delete --name rg-bicep-step1 --yes --no-wait
```

---

## 次のステップ

Step 1 が完了したら、[Step 2 — Web Apps](../step2-webapp/README.md) に進みましょう。  
`module` を使ったリソースの分割・再利用を学びます。

---

## 参考

- [Microsoft.Compute/virtualMachines リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.compute/virtualmachines)
- [Microsoft.Network リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.network/virtualnetworks)
- [Bicep パラメーター](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/parameters)
- [Bicep 変数](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/variables)
- [Bicep 出力](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/outputs)
