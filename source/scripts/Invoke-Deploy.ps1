<#
.SYNOPSIS
    Trigger the ACTUAL Azure Local cluster deployment (deploymentMode=Deploy).

.DESCRIPTION
    Mirror of Invoke-ValidationRetry.ps1 but sets deploymentMode='Deploy', which is
    exactly what the portal "Deploy" / Review+Create does: PUT deploymentSettings/default
    with the same wizard config and deploymentMode=Deploy. ECE then runs the multi-hour
    build (domain join, cluster create, S2D, Network ATC/RDMA, ARB/MOC, custom location).

    This is a big, mostly-irreversible action. It is also RESUMABLE: if a step fails, ECE
    stops there; fix + re-PUT to resume. Polls only a short initial window to confirm the
    deploy STARTED, then hands off (deploy continues server-side regardless of this script).

.NOTES
    Keep PIM active. Monitor with: & .\scripts\_poll-validation.ps1  (same poller works for deploy)
    Full step list lands in out\_ds-deploy-result-*.json when this script's window ends.
#>
param(
    [string]$SubscriptionId = '00000000-0000-0000-0000-000000000001',
    [string]$ResourceGroup  = 'rg-azlocal-poc-001',
    [string]$ClusterName    = 'AZL-CLUSTER-01',
    [string]$ApiVersion     = '2024-04-01',
    [int]   $InitialPollMinutes = 8,     # just confirm it started; deploy runs for hours after
    [switch]$Confirm
)
$ErrorActionPreference = 'Stop'
$dsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.AzureStackHCI/clusters/$ClusterName/deploymentSettings/default?api-version=$ApiVersion"

Write-Host "==== Fetching current deploymentSettings ===="
$current = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
Write-Host "  provisioningState : $($current.properties.provisioningState)"
Write-Host "  deploymentMode    : $($current.properties.deploymentMode)"

if (-not $Confirm) {
    Write-Host ""
    Write-Host "*** This will START THE ACTUAL MULTI-HOUR CLUSTER DEPLOYMENT (deploymentMode=Deploy). ***"
    Write-Host "Re-run with -Confirm to proceed."
    return
}

$body = @{
    properties = @{
        arcNodeResourceIds      = $current.properties.arcNodeResourceIds
        deploymentMode          = 'Deploy'
        deploymentConfiguration = $current.properties.deploymentConfiguration
    }
} | ConvertTo-Json -Depth 32
$bodyFile = Join-Path (Resolve-Path .).Path 'out\_ds-deploy-body.json'
$body | Set-Content -LiteralPath $bodyFile -Encoding UTF8

Write-Host ""
Write-Host "==== Submitting PUT (deploymentMode=Deploy) - starting the real deploy ===="
$patchOut = az rest --method PUT --uri $dsUri --headers "Content-Type=application/json" --body "@$bodyFile" --output json 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "  SUBMIT FAILED:"; Write-Host $patchOut; return }
Write-Host "  Deploy submitted."

Write-Host ""
Write-Host "==== Confirming it started (polling ~$InitialPollMinutes min; deploy continues for HOURS after) ===="
$deadline = (Get-Date).AddMinutes($InitialPollMinutes)
do {
    Start-Sleep -Seconds 60
    $r = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
    $steps = $r.properties.reportedProperties.validationStatus.steps
    $cur = ($steps | Where-Object { $_.status -eq 'InProgress' } | Select-Object -First 1).name
    if (-not $cur) { $cur = ($steps | Select-Object -Last 1).name }
    Write-Host ("  {0}  provState={1}  step={2}" -f (Get-Date -Format HH:mm:ss), $r.properties.provisioningState, $cur)
} while ((Get-Date) -lt $deadline -and $r.properties.provisioningState -notin 'Succeeded','Failed')

$r | ConvertTo-Json -Depth 40 | Set-Content ".\out\_ds-deploy-result-$(Get-Date -Format yyyyMMdd-HHmmss).json"
Write-Host ""
Write-Host "Initial window done. provState=$($r.properties.provisioningState)."
Write-Host "The deploy runs server-side for several hours. Monitor with: & .\scripts\_poll-validation.ps1"
