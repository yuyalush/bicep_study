# Step 6-4 — Activity Log → Storage Account（長期アーカイブ）

## 学習目標

Activity Log をストレージアカウントに直接出力することで  
**低コストな長期アーカイブ**を実現し、Step 6-1（Log Analytics）との使い分けを理解する。  
また、Bicep の**条件付きリソース作成**（`if` 条件）を学ぶ。

---

## 前提条件

| ステップ | 状態 |
|---|---|
| Step 1〜5 | 完了済みであること |
| Azure CLI | ログイン済みであること (`az login`) |
| 権限 | サブスクリプションの `Owner` または `Contributor` + `Monitoring Contributor` ロール |

> Step 5 で作成したストレージアカウントを再利用することもできます（後述）。

---

## ファイル構成

```
step6-4/
├── main.bicep                        # targetScope = 'subscription'
├── modules/
│   └── storageAccountDiag.bicep      # アーカイブ用ストレージアカウント
└── README.md                         # このファイル
```

---

## デプロイ手順

### パターン 1: 新規ストレージアカウントを作成する

```powershell
az deployment sub create `
  --location japaneast `
  --template-file main.bicep `
  --parameters location=japaneast
```

### パターン 2: Step 5 のストレージアカウントを再利用する

```powershell
# Step 5 のストレージ ID を取得
$STORAGE_ID = $(az storage account show `
  --name "stbicepexportdev" `
  --resource-group "rg-bicep-cost-dev" `
  --query id -o tsv)

# 既存ストレージに Activity Log を転送
az deployment sub create `
  --location japaneast `
  --template-file main.bicep `
  --parameters location=japaneast existingStorageAccountId="$STORAGE_ID"
```

---

## 新しく学ぶ Bicep の概念

### 1. 条件付きリソース作成（`if` 条件）

パラメーターの値によって **リソースを作成するかスキップするか** を制御できます。

```bicep
// フラグ変数でスイッチを作る
var useExistingStorage = !empty(existingStorageAccountId)

// リソースグループ: 新規作成が必要な場合のみデプロイ
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = if (!useExistingStorage) {
  name: 'rg-${projectName}-actlog-${environment}'
  location: location
}

// モジュール: 同様に条件付き
module storage 'modules/storageAccountDiag.bicep' = if (!useExistingStorage) {
  name: 'deploy-storageForActivityLog'
  scope: rg
  params: { ... }
}
```

### 2. 三項演算子による出力値の切り替え

```bicep
// 既存 or 新規作成のどちらのストレージ ID を使うか分岐
storageAccountId: useExistingStorage
  ? existingStorageAccountId         // 既存を使う場合
  : storage.outputs.storageAccountId // 新規作成した場合
```

### 3. `retentionPolicy` による自動削除設定

Log Analytics にはない、ストレージ固有の保持ポリシーを設定できます。

```bicep
{
  category: 'Administrative'
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 365   // 365日後に自動削除（0 = 無期限）
  }
}
```

### 4. Cool アクセス層（アーカイブ用途の最適化）

```bicep
resource storageAccount '...' = {
  properties: {
    accessTier: 'Cool'  // Hot より低コスト（読み取り頻度が低いアーカイブ向け）
  }
}
```

| アクセス層 | 保存コスト | 読み取りコスト | 推奨用途 |
|---|---|---|---|
| `Hot` | 高い | 低い | 頻繁にアクセスするデータ |
| `Cool` | 中程度 | 中程度 | 30日以上保存・低頻度アクセス |
| `Cold` | 低い | 高い | 90日以上保存・さらに低頻度 |
| `Archive` | 最低 | 最高（取り出しに時間） | 180日以上・ほぼアクセスしない |

---

## Step 6-1（Log Analytics）との比較

| 観点 | Step 6-1（Log Analytics） | Step 6-4（Storage Account） |
|---|---|---|
| 保存コスト | データ量に比例（比較的高め） | **低コスト**（Cool 層） |
| 検索性 | **KQL でリアルタイム検索** | Azure Data Explorer / Power BI が必要 |
| 保持期間 | 最大 730 日 | **無制限**（ライフサイクル管理で制御） |
| アラート連携 | 可能（Step 5 との組み合わせ） | 直接はできない |
| 推奨用途 | 運用監視・インシデント対応 | **コンプライアンス・長期監査** |

> **実運用ではどちらか一方ではなく、両方を併用するケースが多いです。**  
> 直近 90 日は Log Analytics で素早く検索し、それ以降は Storage で低コスト保存する構成が一般的です。

---

## デプロイ後のデータ確認

Activity Log のデータはストレージアカウントの以下のパスに自動配置されます。

```
<storage-container>/
└── insights-activity-logs/
    └── ResourceId=<SUBSCRIPTION_RESOURCE_ID>/
        └── y=<YEAR>/
            └── m=<MONTH>/
                └── d=<DAY>/
                    └── h=<HOUR>/
                        └── m=00/
                            └── PT1H.json
```

```powershell
# Azure CLI でアップロードされたファイルを確認
az storage blob list `
  --account-name "<ストレージアカウント名>" `
  --container-name "insights-activity-logs" `
  --output table
```

> ⚠️ データが出力されるまでには最大 **5〜15 分**かかる場合があります。
