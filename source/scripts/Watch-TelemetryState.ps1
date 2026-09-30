<#
.SYNOPSIS
  Read-only watcher for the AzureEdgeTelemetryAndDiagnostics extension provisioning
  state across the four POC nodes. Reports one line per poll and stops when all four
  reach a terminal state (Succeeded or Failed). Does NOT touch the nodes or services.

.PARAMETER Nodes
  Arc machine names. Default 01/02/04/06.

.PARAMETER Iterations
  Poll cycles. Default 30.

.PARAMETER IntervalSeconds
  Seconds between polls. Default 30.
#>
[CmdletBinding()]
param(
    [string[]]$Nodes = @('AZL-NODE-01','AZL-NODE-02','AZL-NODE-04','AZL-NODE-06'),
    [string]$ResourceGroup = 'rg-azlocal-poc-001',
    [int]$Iterations = 30,
    [int]$IntervalSeconds = 30
)

for ($i = 1; $i -le $Iterations; $i++) {
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line  = "[$stamp] "
    $states = @()
    foreach ($n in $Nodes) {
        $s = az connectedmachine extension show -g $ResourceGroup --machine-name $n `
            -n AzureEdgeTelemetryAndDiagnostics --query "properties.provisioningState" -o tsv 2>$null
        if (-not $s) { $s = 'none' }
        $states += $s
        $short = ($n -replace 'AZL-NODE-','')
        $line += "$short=$s  "
    }
    Write-Host $line
    $line | Add-Content (Join-Path $PSScriptRoot '..\out\_telemetry-state.txt')

    # Terminal when every node is Succeeded or Failed (none Creating/Deleting/Updating).
    $pending = $states | Where-Object { $_ -match 'Creating|Deleting|Updating|none' }
    if (-not $pending) {
        Write-Host "All nodes terminal (Succeeded/Failed)." -ForegroundColor Green
        break
    }
    if ($i -lt $Iterations) { Start-Sleep -Seconds $IntervalSeconds }
}
