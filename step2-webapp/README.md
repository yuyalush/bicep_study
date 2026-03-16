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
├── app/
│   ├── package.json             # Node.js プロジェクト設定
│   └── server.js                # Express アプリ本体
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

## サンプルアプリ（app/）

`app/` ディレクトリに学習用の Node.js + Express アプリが同梱されています。

| ファイル | 内容 |
|---|---|
| `package.json` | 依存パッケージの定義（express のみ） |
| `server.js` | Express サーバー。2つのエンドポイントを持つ |

**エンドポイント:**

| パス | 内容 |
|---|---|
| `GET /` | HTML ページ。Bicep の `appSettings` で設定した環境変数を表示する |
| `GET /health` | JSON でステータスと環境変数を返すヘルスチェック |

アプリは `ENVIRONMENT` / `NODE_ENV` / `PORT` を環境変数（= Bicep の `appSettings`）から読み込むため、  
デプロイ先の環境（dev / stg / prod）に応じて自動的に表示が変わります。

**ローカル動作確認:**

```bash
cd app
npm install
npm start
# → http://localhost:3000
```

---

## 前提条件

- Azure CLI インストール済み
- Node.js がインストール済みであること（`node --version`）

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

### 5. 依存パッケージをインストール

ZIP デプロイ前にローカルで `node_modules` を生成しておきます。

```bash
cd app
npm install
cd ..
```

### 6. ソースコードをデプロイ（ZIP デプロイ）

デプロイ先の Web App 名は、手順 4 の出力に含まれる `appServicePlanName` の隣に表示される  
`webAppHostName`（例: `bicep02-dev-app-xxxxxxx.azurewebsites.net`）のサブドメイン部分です。  
`az deployment group show` で確認することもできます。

**PowerShell:**

```powershell
# デプロイ済みの Web App 名を確認
$WEB_APP_NAME = (az deployment group show `
  --resource-group rg-bicep-step2 `
  --name main `
  --query properties.outputs.webAppHostName.value `
  --output tsv).Split(".")[0]

# app フォルダを ZIP 圧縮
Compress-Archive -Path ./app/* -DestinationPath ./app.zip -Force

# ZIP デプロイ
az webapp deploy `
  --resource-group rg-bicep-step2 `
  --name $WEB_APP_NAME `
  --src-path ./app.zip `
  --type zip
```

**Bash:**

```bash
# デプロイ済みの Web App 名を確認
WEB_APP_NAME=$(az deployment group show \
  --resource-group rg-bicep-step2 \
  --name main \
  --query properties.outputs.webAppHostName.value \
  --output tsv | cut -d. -f1)

# app フォルダを ZIP 圧縮
zip -r ./app.zip ./app

# ZIP デプロイ
az webapp deploy \
  --resource-group rg-bicep-step2 \
  --name $WEB_APP_NAME \
  --src-path ./app.zip \
  --type zip
```

`WEBSITE_RUN_FROM_PACKAGE = '1'` が設定されているため、Azure が ZIP をマウントして実行します。

### 7. 動作確認

```bash
# ブラウザで開く（出力された webAppUrl を使用）
az deployment group show \
  --resource-group rg-bicep-step2 \
  --name main \
  --query properties.outputs.webAppUrl.value \
  --output tsv

# ヘルスチェック
curl https://<webAppName>.azurewebsites.net/health
```

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

## Tips

### `node_modules` はリポジトリに含めない

`node_modules` は `npm install` で再生成できるため、Git の管理対象から除外するのが一般的です。  
プロジェクトルートの `.gitignore` に以下を追加してください。

```
step2-webapp/app/node_modules/
```

ZIP デプロイ前にローカルで `npm install` を実行するのが、手順 5 の目的です。

### App Service 側でビルドする方法（応用）

`node_modules` を ZIP に含めず、App Service に `package.json` だけをデプロイして  
**Azure 側で `npm install` を実行させる**方法もあります。

```bash
az webapp config appsettings set \
  --resource-group rg-bicep-step2 \
  --name $WEB_APP_NAME \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true
```

ただし、この方法は `WEBSITE_RUN_FROM_PACKAGE=1` との併用ができません。  
今回の `main.bicep` の構成（Run-From-Package）とは組み合わせられないため、  
手順 5 の `npm install` → ZIP デプロイの方法を推奨します。

### GitHub リポジトリからデプロイする場合の主な変更点

ZIP デプロイの代わりに、GitHub リポジトリと App Service を連携させて自動デプロイすることもできます。

**Bicep 側の変更点:**

`main.bicep` の `appSettings` から `WEBSITE_RUN_FROM_PACKAGE` を削除し、  
`webApp.bicep` の `siteConfig` に `sourcecontrols` リソース、または以下の設定を追加します。

```bicep
// webApp.bicep に sourcecontrol リソースを追加
resource sourceControl 'Microsoft.Web/sites/sourcecontrols@2023-01-01' = {
  name: '${webApp.name}/web'
  properties: {
    repoUrl: 'https://github.com/<owner>/<repo>'
    branch: 'main'
    isManualIntegration: false  // GitHub Actions による自動デプロイを有効化
  }
}
```

**運用上の注意点:**

| 項目 | ZIP デプロイ | GitHub 連携 |
|---|---|---|
| トリガー | 手動（CLI コマンド） | push / PR マージ で自動 |
| `node_modules` | ZIP に含める（または SCM ビルド） | GitHub Actions で `npm install` → デプロイ |
| `WEBSITE_RUN_FROM_PACKAGE` | `1` に設定 | 不要（削除する） |
| 向いている用途 | 学習・スポット更新 | CI/CD パイプライン構築 |

GitHub Actions を使う場合は、Azure がリポジトリに自動生成するワークフローファイル  
(`.github/workflows/*.yml`) を利用するのが最も簡単です。

### デプロイスロット（ステージング）を使う

App Service の **デプロイスロット** を使うと、本番環境を止めずに新バージョンを  
ステージング環境で検証し、問題なければ **スワップ（swap）** で本番に反映できます。

**Bicep でスロットを定義する:**

```bicep
// webApp.bicep または modules/slot.bicep に追加
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = {
  name: '${webApp.name}/staging'
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlanId
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appSettings: [
        { name: 'ENVIRONMENT',              value: 'staging' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
      ]
    }
  }
}
```

> スロットは **Standard (S1) 以上** のプランでのみ利用できます。  
> 現在の `main.bicep` の `skuName` を `S1` 以上に変更してください。

**ステージングへのデプロイとスワップ:**

```powershell
# ステージングスロットへ ZIP デプロイ
az webapp deploy `
  --resource-group rg-bicep-step2 `
  --name $WEB_APP_NAME `
  --slot staging `
  --src-path ./app.zip `
  --type zip

# 動作確認（ステージング URL: https://<name>-staging.azurewebsites.net）
curl https://$WEB_APP_NAME-staging.azurewebsites.net/health

# 問題なければ本番とスワップ
az webapp deployment slot swap `
  --resource-group rg-bicep-step2 `
  --name $WEB_APP_NAME `
  --slot staging `
  --target-slot production
```

スワップ後は元の本番コードがステージングスロットに移るため、問題があれば再スワップで即時ロールバックできます。

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
