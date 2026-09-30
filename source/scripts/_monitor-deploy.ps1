# Background deploy monitor: polls deploymentSettings every 2 min, prints a line only when a step
# CHANGES status (avoids spam), surfaces error detail if a step fails, and writes the latest full
# JSON to out/_deploy-latest.json each cycle. Exits when provState = Succeeded/Failed.
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
Write-Host "==== Deploy monitor started $(Get-Date -Format 'HH:mm:ss') (every ${IntervalSec}s) ===="
do {
    try {
        $r = az rest --method GET --uri $dsUri --output json 2>$null | ConvertFrom-Json
        $prov = $r.properties.provisioningState
        $steps = $r.properties.reportedProperties.validationStatus.steps
        $r | ConvertTo-Json -Depth 40 | Set-Content .\out\_deploy-latest.json
        # report status changes
        foreach ($s in $steps) {
            if ($prev[$s.name] -ne $s.status) {
                Write-Host ("  {0}  {1,-10}  {2}" -f (Get-Date -Format HH:mm:ss), $s.status, $s.name)
                if ($s.status -eq 'Error') {
                    $d = ($s.exception, $s.description | Where-Object { $_ }) -join ' | '
                    if ($d) { Write-Host ("             ERR: " + ($d.Substring(0,[Math]::Min(400,$d.Length)))) }
                }
                $prev[$s.name] = $s.status
            }
        }
        $cur = ($steps | Where-Object { $_.status -eq 'InProgress' } | Select-Object -First 1).name
        Write-Host ("  {0}  provState={1}  inProgress={2}" -f (Get-Date -Format HH:mm:ss), $prov, $cur)
    } catch {
        Write-Host ("  {0}  poll error: {1}" -f (Get-Date -Format HH:mm:ss), $_.Exception.Message)
    }
    if ($prov -in 'Succeeded','Failed') { break }
    Start-Sleep -Seconds $IntervalSec
} while ((Get-Date) -lt $deadline)
Write-Host ""
Write-Host "==== Monitor ended. provState=$prov  $(Get-Date -Format 'HH:mm:ss') ===="
$steps | ForEach-Object { "  [{0,-9}] {1}" -f $_.status, $_.name }
