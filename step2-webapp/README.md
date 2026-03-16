# Step 2 — ローカルソースコードを使った Web Apps

Step 1 の基本構文を土台に、**`module`** を使ったリソースの分割・再利用と、  
ローカルアプリを App Service（Web Apps）にデプロイする構成を学びます。

---

## 学習目標

- `module` キーワードでテンプレートを分割・再利用する方法を理解する
- モジュール間で `output` → `params` として値を受け渡す流れを理解する
- `uniqueString()` でグローバル一意なリソース名を生成する方法を知る
- `appSettings` でアプリケーション設定（環境変数）を管理する方法を理解する
- **Run-From-Package** を使ったソースコードのデプロイ手順を体験する

---

## ファイル構成

```
step2-webapp/
├── main.bicep                   # エントリポイント。モジュールを呼び出す
├── modules/
│   ├── appServicePlan.bicep     # App Service Plan の定義
│   └── webApp.bicep             # Web App の定義
└── README.md
```

---

## 作成されるリソース構成

```
リソースグループ
├── App Service Plan (Linux / B1)
└── Web App
    └── アプリ設定 (ENVIRONMENT / WEBSITE_RUN_FROM_PACKAGE / NODE_ENV)
```

---

## Bicep のモジュール解説

### `module` キーワード

大きなテンプレートを **小さなファイル（モジュール）** に分割できます。  
モジュールは再利用可能な部品として、複数の環境やプロジェクトで共有できます。

```bicep
module <シンボル名> '<ファイルパス>' = {
  name: '<デプロイ操作の名前>'  // Azure ポータルのデプロイ履歴に表示される
  params: {
    param1: value1
    param2: value2
  }
}
```

---

### モジュール間の値の受け渡し

モジュールの `output` は、呼び出し元から `<シンボル名>.outputs.<出力名>` で参照できます。  
この参照が書かれると、Bicep が自動的に正しいデプロイ順序を決定します。

```bicep
// ① App Service Plan を先にデプロイ
module appServicePlanModule 'modules/appServicePlan.bicep' = {
  name: 'deploy-appServicePlan'
  params: { planName: planName, ... }
}

// ② Web App は App Service Plan の output を使う → 自動的に ① の後にデプロイされる
module webAppModule 'modules/webApp.bicep' = {
  name: 'deploy-webApp'
  params: {
    appServicePlanId: appServicePlanModule.outputs.planId  // ← output を参照
  }
}
```

---

### `uniqueString()` — グローバル一意名の生成

Web App 名は Azure 全体で一意である必要があります。  
`uniqueString()` はシード値（通常はリソースグループ ID）から **決定論的な 13 文字の文字列** を生成します。  
同じリソースグループに何度デプロイしても同じ値が返るため、冪等性が保たれます。

```bicep
var webAppName = '${prefix}-app-${uniqueString(resourceGroup().id)}'
// 例: bicep02-dev-app-a5b3c7d9e1f2g
```

---

### `appSettings` — アプリケーション設定

Web App の環境変数に相当します。`{ name, value }` オブジェクトの配列で指定します。

```bicep
appSettings: [
  { name: 'ENVIRONMENT',              value: environment }
  { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
  { name: 'NODE_ENV',                 value: environment == 'prod' ? 'production' : 'development' }
]
```

`WEBSITE_RUN_FROM_PACKAGE = '1'` を設定すると、デプロイした ZIP パッケージをそのままマウントして実行する **Run-From-Package モード** が有効になります。

---

## 前提条件

- Azure CLI インストール済み
- Node.js アプリ（または任意のランタイム）のソースコードが手元にあること

---

## デプロイ手順

### 1. リソースグループを作成

```bash
az group create \
  --name rg-bicep-step2 \
  --location japaneast
```

### 2. Bicep を検証

```bash
az deployment group validate \
  --resource-group rg-bicep-step2 \
  --template-file main.bicep
```

### 3. What-if でプレビュー

```bash
az deployment group what-if \
  --resource-group rg-bicep-step2 \
  --template-file main.bicep
```

### 4. インフラをデプロイ

```bash
az deployment group create \
  --resource-group rg-bicep-step2 \
  --template-file main.bicep
```

デプロイ後、出力から `webAppUrl` を確認できます。

### 5. ソースコードをデプロイ（ZIP デプロイ）

アプリのソースディレクトリを ZIP 圧縮して、`az webapp deploy` でプッシュします。

```bash
# ソースを ZIP 圧縮（例: Node.js アプリ）
Compress-Archive -Path ./app/* -DestinationPath ./app.zip

# ZIP デプロイ
az webapp deploy \
  --resource-group rg-bicep-step2 \
  --name <webAppName>  \
  --src-path ./app.zip \
  --type zip
```

`WEBSITE_RUN_FROM_PACKAGE = '1'` が設定されているため、Azure が ZIP を自動解凍して実行します。

---

## パラメーターのカスタマイズ

```bash
az deployment group create \
  --resource-group rg-bicep-step2 \
  --template-file main.bicep \
  --parameters projectName=myapp environment=dev skuName=B1
```

---

## リソースの削除

```bash
az group delete --name rg-bicep-step2 --yes --no-wait
```

---

## Step 1 との比較まとめ

| 項目 | Step 1 (VM) | Step 2 (Web Apps) |
|---|---|---|
| リソース定義 | すべて `main.bicep` に記述 | `module` で分割 |
| リソース間参照 | シンボル名で直接参照 | モジュール `outputs` 経由で参照 |
| 一意名生成 | `var` で固定文字列 | `uniqueString()` を活用 |
| アプリ実行 | OS + ミドルウェアを自分で管理 | ランタイムはプラットフォーム任せ |

---

## 次のステップ

Step 2 が完了したら、[Step 3 — Azure Functions](../step3-functions/README.md) に進みましょう。  
サーバーレスアーキテクチャと、Functions に必要なストレージの扱いを学びます。

---

## 参考

- [Microsoft.Web/serverfarms リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.web/serverfarms)
- [Microsoft.Web/sites リファレンス](https://learn.microsoft.com/ja-jp/azure/templates/microsoft.web/sites)
- [Bicep モジュール](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/modules)
- [uniqueString 関数](https://learn.microsoft.com/ja-jp/azure/azure-resource-manager/bicep/bicep-functions-string#uniquestring)
- [Run-From-Package](https://learn.microsoft.com/ja-jp/azure/azure-functions/run-functions-from-deployment-package)
