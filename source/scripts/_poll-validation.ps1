# Poll the in-flight validation
$dsUri = "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-azlocal-poc-001/providers/Microsoft.AzureStackHCI/clusters/AZL-CLUSTER-01/deploymentSettings/default?api-version=2024-04-01"
$start = Get-Date
$lastStep = ''
$maxMin = 45

while (((Get-Date) - $start).TotalMinutes -lt $maxMin) {
    $now = az rest --method GET --uri $dsUri --output json 2>&1 | ConvertFrom-Json
    $ps  = $now.properties.provisioningState
    $vs  = $now.properties.reportedProperties.validationStatus
    $inflight = if ($vs) { ($vs.steps | Where-Object { $_.status -notin 'Success','Error','Failed' } | Select-Object -First 1) } else { $null }
    $step = if ($inflight) { $inflight.name } else { '(none)' }
    if ($step -ne $lastStep -or $ps -in 'Succeeded','Failed','Canceled') {
        Write-Host ("  {0}  provState={1}  vsStatus={2}  step={3}" -f (Get-Date -Format 'HH:mm:ss'), $ps, $vs.status, $step)
        $lastStep = $step
    }
    if ($ps -in 'Succeeded','Failed','Canceled') { break }
    Start-Sleep -Seconds 45
}

Write-Host ""
Write-Host "==== Final ===="
$final = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = "out\_ds-post-simcutover-$stamp.json"
$final | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $outFile -Encoding UTF8
$vs = $final.properties.reportedProperties.validationStatus
if ($vs) {
    $vs.steps | ForEach-Object {
        $mark = "[{0,-8}]" -f "$($_.status)"
        Write-Host "  $mark $($_.name)"
        if ($_.exception) {
            $short = ($_.exception -split "`n" | Select-Object -First 3) -join ' | '
            Write-Host "           ERR: $short"
        }
    }
}
Write-Host ""
Write-Host "Full result: $outFile"
