// ============================================================
// Step 8: バックアップからの復元
// Step 7 で設定した Azure Backup から VM を復元する
//
// ★ このテンプレートが学ぶ Bicep の概念:
//   - Microsoft.Resources/deploymentScripts:
//       Bicep テンプレートから Azure CLI スクリプトを実行する
//   - User-Assigned Managed Identity:
//       デプロイスクリプトが Azure API を呼び出すための認証 ID
//   - RBAC ロール割り当て:
//       最小権限の原則でスクリプトに必要な権限のみを付与する
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group rg-bicep-step1 \
//     --template-file main.bicep
//
// ★ Step 7 と同じリソースグループ (rg-bicep-step1) にデプロイすること
// ============================================================

// ------------------------------------------------------------
// パラメーター
// ------------------------------------------------------------

@description('リソースを作成する Azure リージョン')
param location string = resourceGroup().location

@description('環境名 (dev / stg / prod)')
@allowed(['dev', 'stg', 'prod'])
param environment string = 'dev'

@description('プロジェクト名 (リソース名のプレフィックスに使用)')
@minLength(2)
@maxLength(8)
param projectName string = 'bicep01'

@description('使用する復元ポイント名。空欄の場合は最新の復元ポイントを自動選択')
param recoveryPointName string = ''

// ------------------------------------------------------------
// 変数
// ------------------------------------------------------------

var prefix = '${projectName}-${environment}'
var vaultName    = '${prefix}-rsv'
var vmName       = '${prefix}-vm'

// 保護コンテナー名・保護アイテム名（Step 7 と同じ形式）
var protectionContainerName = 'iaasvmcontainer;iaasvmcontainerv2;${resourceGroup().name};${vmName}'
var protectedItemName       = 'vm;iaasvmcontainerv2;${resourceGroup().name};${vmName}'

// デプロイスクリプト用リソース名
var identityName = '${prefix}-restore-identity'

// uniqueString を使ってデプロイごとに異なるスクリプト名を生成し、再実行を可能にする
var scriptName   = '${prefix}-restore-${uniqueString(resourceGroup().id, deployment().name)}'

// RBAC 組み込みロール定義 ID
var backupOperatorRoleId = '00c29273-979b-4161-815c-10b084fb9324' // Backup Operator
var vmContributorRoleId  = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c' // Virtual Machine Contributor

// ------------------------------------------------------------
// 既存リソースへの参照
// ★ existing キーワード: Step 7 で作成済みのリソースを参照（新規作成しない）
// ------------------------------------------------------------

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

// ------------------------------------------------------------
// ① User-Assigned Managed Identity
// デプロイスクリプトが Azure API を呼び出す際の認証 ID
// ★ System-Assigned Identity もあるが、User-Assigned Identity は
//    リソースのライフサイクルから独立しているため、他のリソースでも再利用しやすい
// ------------------------------------------------------------

resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// ------------------------------------------------------------
// ② Backup Operator ロール割り当て（Vault スコープ）
// 復元ポイントの取得・復元ジョブのトリガーに必要
// ★ scope プロパティで Vault に権限を限定（最小権限の原則）
// ------------------------------------------------------------

resource backupOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, scriptIdentity.id, backupOperatorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', backupOperatorRoleId)
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------------------------------------
// ③ Virtual Machine Contributor ロール割り当て（リソースグループスコープ）
// 元の場所への復元（VM の停止・ディスク差し替え）に必要
// ------------------------------------------------------------

resource vmContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, scriptIdentity.id, vmContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------------------------------------
// ④ Deployment Script: 復元トリガー
// Azure CLI を使って復元ジョブを開始する
//
// ★ Microsoft.Resources/deploymentScripts:
//    Bicep テンプレートの一部として CLI / PowerShell スクリプトを実行できる。
//    スクリプトの実行には一時的なストレージアカウントとコンテナーインスタンスが
//    自動生成され、retentionInterval の経過後に自動削除される。
// ------------------------------------------------------------

resource restoreScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: scriptName
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.53.0'
    retentionInterval: 'P1D'  // 実行完了後 1 日間ログを保持してからリソースを削除
    timeout: 'PT30M'          // スクリプト全体のタイムアウト: 30 分
    environmentVariables: [
      { name: 'RG_NAME',             value: resourceGroup().name }
      { name: 'VAULT_NAME',          value: vaultName }
      { name: 'CONTAINER_NAME',      value: protectionContainerName }
      { name: 'ITEM_NAME',           value: protectedItemName }
      { name: 'VM_NAME',             value: vmName }
      { name: 'RECOVERY_POINT_NAME', value: recoveryPointName }
    ]
    scriptContent: '''
      set -eo pipefail

      echo "=== Azure Backup 復元スクリプト 開始 ==="

      # ─── Step 1: 復元ポイントの決定 ──────────────────────────────
      RP="${RECOVERY_POINT_NAME:-}"
      if [ -z "${RP}" ]; then
        echo "[1/3] 最新の復元ポイントを取得しています..."
        RP=$(az backup recoverypoint list \
          --resource-group "${RG_NAME}" \
          --vault-name     "${VAULT_NAME}" \
          --container-name "${CONTAINER_NAME}" \
          --item-name      "${ITEM_NAME}" \
          --workload-type  VM \
          --query          "[0].name" \
          --output         tsv)

        if [ -z "${RP}" ]; then
          echo "エラー: 利用可能な復元ポイントがありません。" >&2
          echo "バックアップジョブが正常に完了しているか確認してください。" >&2
          exit 1
        fi
        echo "  => 使用する復元ポイント: ${RP}"
      else
        echo "[1/3] 指定された復元ポイントを使用: ${RP}"
      fi

      # ─── Step 2: VM の停止（元の場所への復元に必要） ────────────
      echo "[2/3] VM の状態を確認しています..."
      VM_STATE=$(az vm get-instance-view \
        --resource-group "${RG_NAME}" \
        --name           "${VM_NAME}" \
        --query          "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" \
        --output         tsv)
      echo "  => 現在の VM 状態: ${VM_STATE}"

      if [ "${VM_STATE}" != "PowerState/deallocated" ]; then
        echo "  => VM を停止しています..."
        az vm deallocate \
          --resource-group "${RG_NAME}" \
          --name           "${VM_NAME}"
        echo "  => VM の停止完了"
      else
        echo "  => VM はすでに停止済みです"
      fi

      # ─── Step 3: 復元ジョブのトリガー ─────────────────────────────
      echo "[3/3] 復元ジョブを開始しています（元の場所への復元）..."
      JOB_NAME=$(az backup restore restore-azurevm \
        --resource-group "${RG_NAME}" \
        --vault-name     "${VAULT_NAME}" \
        --container-name "${CONTAINER_NAME}" \
        --item-name      "${ITEM_NAME}" \
        --rp-name        "${RP}" \
        --restore-mode   OriginalLocation \
        --query          "name" \
        --output         tsv)

      echo "  => 復元ジョブ開始: ${JOB_NAME}"

      JOB_STATUS=$(az backup job show \
        --resource-group "${RG_NAME}" \
        --vault-name     "${VAULT_NAME}" \
        --name           "${JOB_NAME}" \
        --query          "properties.status" \
        --output         tsv)
      echo "  => 初期ジョブ状態: ${JOB_STATUS}"

      echo "=== 復元スクリプト完了 ==="
      echo "復元ジョブの進行状況は以下のコマンドで確認できます:"
      echo "  az backup job show --resource-group ${RG_NAME} --vault-name ${VAULT_NAME} --name ${JOB_NAME}"

      # デプロイスクリプトの出力（JSON 形式で $AZ_SCRIPTS_OUTPUT_PATH に書き込む）
      jq -n \
        --arg jobName       "${JOB_NAME}" \
        --arg jobStatus     "${JOB_STATUS}" \
        --arg recoveryPoint "${RP}" \
        '{"jobName": $jobName, "jobStatus": $jobStatus, "recoveryPointName": $recoveryPoint}' \
        > "${AZ_SCRIPTS_OUTPUT_PATH}"
    '''
  }
  dependsOn: [
    backupOperatorRoleAssignment
    vmContributorRoleAssignment
  ]
}

// ------------------------------------------------------------
// 出力
// ------------------------------------------------------------

@description('復元ジョブ名（az backup job show コマンドで監視に使用）')
output restoreJobName string = restoreScript.properties.outputs.jobName

@description('使用した復元ポイント名')
output recoveryPointUsed string = restoreScript.properties.outputs.recoveryPointName

@description('復元ジョブの初期ステータス')
output restoreJobStatus string = restoreScript.properties.outputs.jobStatus
