# Fix Compute_Management intent to disable NetworkDirect (RDMA) since Broadcom 1G doesn't support it
$dsUri = "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-azlocal-poc-001/providers/Microsoft.AzureStackHCI/clusters/AZL-CLUSTER-01/deploymentSettings/default?api-version=2024-04-01"

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

Write-Host "==== Fetching current deploymentSettings ===="
$current = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
$backup = Join-Path $outDir "_ds-pre-rdma-fix-$stamp.json"
$current | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $backup -Encoding UTF8
Write-Host "  Backup: $backup"

$intents = $current.properties.deploymentConfiguration.scaleUnits[0].deploymentData.hostNetwork.intents
$cm = $intents | Where-Object { $_.name -eq 'Compute_Management' }
if (-not $cm) { throw "No Compute_Management intent found" }

Write-Host ""
Write-Host "==== BEFORE ===="
"  overrideAdapterProperty : $($cm.overrideAdapterProperty)"
"  networkDirect           : $($cm.adapterPropertyOverrides.networkDirect)"

# Enable override + disable NetworkDirect (Broadcom 1G has no RDMA)
$cm.overrideAdapterProperty = $true
$cm.adapterPropertyOverrides.networkDirect = 'Disabled'

Write-Host ""
Write-Host "==== AFTER ===="
"  overrideAdapterProperty : $($cm.overrideAdapterProperty)"
"  networkDirect           : $($cm.adapterPropertyOverrides.networkDirect)"

$body = @{
    properties = @{
        arcNodeResourceIds      = $current.properties.arcNodeResourceIds
        deploymentMode          = 'Validate'
        deploymentConfiguration = $current.properties.deploymentConfiguration
    }
} | ConvertTo-Json -Depth 32
$bodyFile = Join-Path $outDir "_ds-rdma-patch-$stamp.json"
$body | Set-Content -LiteralPath $bodyFile -Encoding UTF8

Write-Host ""
Write-Host "==== Submitting PATCH ===="
$r = az rest --method PUT --uri $dsUri --headers "Content-Type=application/json" --body "@$bodyFile" --output json 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "PATCH FAILED: $r"; exit 1 }
Write-Host "PATCH accepted. This will trigger a fresh validation run."
