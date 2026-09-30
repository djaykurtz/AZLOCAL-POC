<#
.SYNOPSIS
    Re-trigger Azure Local wizard validation via ARM REST, bypassing the portal.

.DESCRIPTION
    The Azure Portal "Start validation" button is just a PATCH to
    Microsoft.AzureStackHCI/clusters/{cluster}/deploymentSettings/default with
    operationType=Validate. This script does exactly that.

    Rebuilds the PATCH body from the currently-saved deploymentSettings so all
    wizard values are preserved verbatim, then submits. Polls provisioningState
    until it settles (Succeeded/Failed) and dumps the validation step list.

.NOTES
    Read the CURRENT deploymentSettings, don't blow it away. This is the
    equivalent of clicking "Start validation" again, no wizard traversal needed.

    Use this once the AD gate is cleared (direct ACEs on AZLCL-DEPLOY-ADM
    added, gPOptions=1 set on the OU).
#>

param(
    [string]$SubscriptionId = '00000000-0000-0000-0000-000000000001',
    [string]$ResourceGroup  = 'rg-azlocal-poc-001',
    [string]$ClusterName    = 'AZL-CLUSTER-01',
    [string]$ApiVersion     = '2024-04-01',
    [int]   $PollSeconds    = 60,
    [int]   $MaxPollMinutes = 60
)

$ErrorActionPreference = 'Stop'
$dsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.AzureStackHCI/clusters/$ClusterName/deploymentSettings/default?api-version=$ApiVersion"

Write-Host "==== Fetching current deploymentSettings ===="
$current = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
Write-Host "  provisioningState : $($current.properties.provisioningState)"
Write-Host "  deploymentMode    : $($current.properties.deploymentMode)"
Write-Host "  operationType     : $($current.properties.operationType)"

$body = @{
    properties = @{
        arcNodeResourceIds      = $current.properties.arcNodeResourceIds
        deploymentMode          = 'Validate'
        deploymentConfiguration = $current.properties.deploymentConfiguration
    }
} | ConvertTo-Json -Depth 32

$bodyFile = Join-Path (Resolve-Path .).Path 'out\_ds-patch-body.json'
$body | Set-Content -LiteralPath $bodyFile -Encoding UTF8
Write-Host ""
Write-Host "==== Body written to $bodyFile ===="

Write-Host ""
Write-Host "==== Submitting PATCH (re-trigger validation) ===="
$patchOut = az rest --method PUT --uri $dsUri --headers "Content-Type=application/json" --body "@$bodyFile" --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  PATCH FAILED:"
    Write-Host $patchOut
    return
}
Write-Host "  PATCH accepted."

Write-Host ""
Write-Host "==== Polling every $PollSeconds s (up to $MaxPollMinutes min) ===="
$start = Get-Date
while ((Get-Date) - $start -lt (New-TimeSpan -Minutes $MaxPollMinutes)) {
    Start-Sleep -Seconds $PollSeconds
    $now  = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
    $ps   = $now.properties.provisioningState
    $vs   = $now.properties.reportedProperties.validationStatus
    $step = if ($vs) {
        $inflight = $vs.steps | Where-Object { $_.status -notin 'Success','Error','Failed' } | Select-Object -First 1
        if ($inflight) { $inflight.name } else { '(none in-flight)' }
    } else { '(no validationStatus yet)' }
    Write-Host ("  {0}  provState={1}  vsStatus={2}  currentStep={3}" -f (Get-Date -Format 'HH:mm:ss'), $ps, ($vs.status), $step)
    if ($ps -in 'Succeeded','Failed','Canceled') { break }
}

Write-Host ""
Write-Host "==== Final step list ===="
$final = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
$vs = $final.properties.reportedProperties.validationStatus
if ($vs) {
    $vs.steps | ForEach-Object {
        "  [{0,-8}] {1}" -f $_.status, $_.name
        if ($_.exception) { "           ERR: $($_.exception -split "`n" | Select-Object -First 3 | Out-String)" }
    }
} else {
    "  No validationStatus in reportedProperties."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = "out\_ds-retry-result-$stamp.json"
$final | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $outFile -Encoding UTF8
Write-Host ""
Write-Host "Full result: $outFile"
