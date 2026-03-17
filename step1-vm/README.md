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

### デコレーター（Decorator）

デコレーターは `param` や `output` の直前に `@` で付加するアノテーションです。  
バリデーション・ドキュメント・セキュリティの3つの用途で使われます。

#### バリデーション系

| デコレーター | 対象型 | 説明 |
|---|---|---|
| `@allowed([...])` | any | 許可する値の一覧を列挙。リスト外の値を拒否する |
| `@minLength(n)` | string / array | 最小文字数（または最小要素数） |
| `@maxLength(n)` | string / array | 最大文字数（または最大要素数） |
| `@minValue(n)` | int | 最小値 |
| `@maxValue(n)` | int | 最大値 |

```bicep
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@minLength(2)
@maxLength(8)
param projectName string = 'bicep01'

@minValue(1)
@maxValue(10)
param instanceCount int = 1
```

#### ドキュメント系

| デコレーター | 説明 |
|---|---|
| `@description('...')` | param / output / resource / module に説明文を付加する |
| `@metadata({...})` | 任意のメタデータを付加する（例: 作成者、バージョン） |

```bicep
@description('VM の管理者ユーザー名')
param adminUsername string = 'azureuser'
```

#### セキュリティ系

| デコレーター | 説明 |
|---|---|
| `@secure()` | string / object に付加するとデプロイログへの値の出力を抑制する |

```bicep
@secure()
param adminPassword string  // デプロイログに値が表示されなくなる
```

> `@secure()` を付けた `param` はデフォルト値を持てません（デプロイ時に必ず明示的な入力が必要）。

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

```powershell
az login
```

### 2. リソースグループを作成

```powershell
az group create `
  --name rg-bicep-step1 `
  --location japaneast
```

### 3. Bicep ファイルを検証（エラーチェック）

```powershell
az deployment group validate `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters adminPassword="YourP@ssw0rd123" location="japaneast"
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
  "sshCommand": { "value": "ssh azureuser@xx.xx.xx.xx" },
  "publicIpAddress": { "value": "xx.xx.xx.xx" }
}
```

### 6. SSH で接続確認

```powershell
ssh azureuser@<publicIpAddress>
```

---

## パラメーターをカスタマイズする

コマンドラインで個別指定:

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
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

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters @parameters.json
```

---

## リソースの削除

学習後はリソースグループごと削除してコストを節約できます。

```powershell
az group delete --name rg-bicep-step1 --yes --no-wait
```

---

## トラブルシューティング

### VM の SKU が利用不可の場合

デプロイ時に以下のようなエラーが表示された場合、指定したリージョンで VM サイズが利用できていません。

```
SkuNotAvailable: The requested VM size 'Standard_B2s' is not available in location 'xxx'.
```

次のコマンドで、指定リージョン・サイズで利用可能な SKU を確認できます。

```powershell
az vm list-skus --location centralus --size Standard_D --all --output table
```

| オプション | 説明 |
|---|---|
| `--location` | 確認するリージョン（例: `japaneast`, `centralus`） |
| `--size` | サイズ名のプレフィックスでフィルター（例: `Standard_B`, `Standard_D`） |
| `--all` | 制限付き（`NotAvailableForSubscription`）の SKU も表示する |
| `--output table` | 表形式で出力 |

`Restrictions` 列が空の行が利用可能な SKU です。  
利用可能な SKU が見つかったら、`main.bicep` の `vmSize` パラメーターのデフォルト値、または `--parameters vmSize="<SKU名>"` で指定してください。

```powershell
az deployment group create `
  --resource-group rg-bicep-step1 `
  --template-file main.bicep `
  --parameters adminPassword="YourP@ssw0rd123" location="japaneast" vmSize="Standard_D2s_v3"
```

---

### リソースプロバイダーが未登録の場合

デプロイ時に以下のようなエラーが表示された場合、サブスクリプションに必要なリソースプロバイダーが登録されていません。

```
The following resource providers are not registered:
Microsoft.Compute
Microsoft.Network
```

Azure CLI で `az provider register` コマンドでプロバイダーを登録できます。

```powershell
az provider register --name Microsoft.Compute
az provider register --name Microsoft.Network
```

---

## 次のステップ

Step 1 が完了したら、[Step 2 — Web Apps](../step2-webapp/README.md) に進みましょう。  
`module` を使ったリソースの分割・再利用を学びます。

---

## 参考

**Bicep 構文**
- [Bicep 構文の概要](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/file)
- [Bicep パラメーター](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/parameters)
- [Bicep 変数](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/variables)
- [Bicep 出力](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/outputs)
- [Bicep デコレーター](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/parameters#decorators)

**リソースリファレンス**
- [Microsoft.Compute/virtualMachines リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.compute/virtualmachines)
- [Microsoft.Network リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.network/virtualnetworks)
