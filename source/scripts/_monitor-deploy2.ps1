# Background deploy monitor v2: tracks the ACTUAL build tree at reportedProperties.deploymentStatus.steps
# (nested: step 0 "Deploy Azure Stack HCI" with substeps 0.1, 0.2, ...). Flattens the tree, prints a line
# only when a leaf step changes status, surfaces error detail on failure, writes out/_deploy-latest.json
# each cycle. Exits when top-level deploymentStatus.status = Succeeded/Failed (or provState settles).
param(
    [string]$SubscriptionId = '00000000-0000-0000-0000-000000000001',
    [string]$ResourceGroup  = 'rg-azlocal-poc-001',
    [string]$ClusterName    = 'AZL-CLUSTER-01',
    [string]$ApiVersion     = '2024-04-01',
    [int]   $IntervalSec    = 120,
    [int]   $MaxHours       = 8
)
$ErrorActionPreference = 'Continue'
$dsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.AzureStackHCI/clusters/$ClusterName/deploymentSettings/default?api-version=$ApiVersion"
$deadline = (Get-Date).AddHours($MaxHours)
$prev = @{}

function Get-Leaves($step, [ref]$acc) {
    if ($step.steps) { foreach ($c in $step.steps) { Get-Leaves $c $acc } }
    else { $acc.Value += $step }
}

Write-Host "==== Deploy monitor v2 started $(Get-Date -Format 'HH:mm:ss') (build tree, every ${IntervalSec}s) ===="
do {
    try {
        $r = az rest --method GET --uri $dsUri --output json 2>$null | ConvertFrom-Json
        $prov = $r.properties.provisioningState
        $ds   = $r.properties.reportedProperties.deploymentStatus
        $r | ConvertTo-Json -Depth 60 | Set-Content .\out\_deploy-latest.json
        $leaves = @(); foreach ($s in $ds.steps) { Get-Leaves $s ([ref]$leaves) }
        foreach ($s in $leaves) {
            $key = "$($s.fullStepIndex)"
            $st  = "$($s.status)"
            if (-not $st) { continue }
            if ($prev[$key] -ne $st) {
                Write-Host ("  {0}  {1,-10}  [{2}] {3}" -f (Get-Date -Format HH:mm:ss), $st, $s.fullStepIndex, $s.name)
                if ($st -eq 'Error' -or $st -eq 'Failed') {
                    $d = ($s.exception, $s.description | Where-Object { $_ }) -join ' | '
                    if ($d) { Write-Host ("             ERR: " + ($d.Substring(0,[Math]::Min(500,$d.Length)))) }
                }
                $prev[$key] = $st
            }
        }
        $inprog = ($leaves | Where-Object { "$($_.status)" -eq 'InProgress' } | ForEach-Object { "[$($_.fullStepIndex)] $($_.name)" }) -join ' ; '
        Write-Host ("  {0}  provState={1}  dsStatus={2}  running={3}" -f (Get-Date -Format HH:mm:ss), $prov, $ds.status, $inprog)
        if ($prov -in 'Succeeded','Failed' -or $ds.status -in 'Succeeded','Failed') { break }
    } catch {
        Write-Host ("  {0}  poll error: {1}" -f (Get-Date -Format HH:mm:ss), $_.Exception.Message)
    }
    Start-Sleep -Seconds $IntervalSec
} while ((Get-Date) -lt $deadline)
Write-Host ""
Write-Host "==== Monitor ended. provState=$prov dsStatus=$($ds.status)  $(Get-Date -Format 'HH:mm:ss') ===="
