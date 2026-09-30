<#
.SYNOPSIS
  Watch whether the security monitoring extension SecurityMonitoringAgent Arc extension REAPPEARS on the POC
  nodes after removal. If it stays gone through the security-agent auto-config reconcile window,
  the SkipSecurityMonitoringAgent=true tag (resource/RG scope) is honored and no subscription-level
  change is needed. If it comes back, resource/RG scope is NOT honored -> escalate to sub scope.

  Read-only (az connectedmachine extension list). No changes.

.PARAMETER Nodes
  Arc machine names. Default 01/02/04/06.

.PARAMETER Iterations
  Poll cycles. Default 30.

.PARAMETER IntervalSeconds
  Seconds between polls. Default 60.
#>
[CmdletBinding()]
param(
    [string[]]$Nodes = @('AZL-NODE-01','AZL-NODE-02','AZL-NODE-04','AZL-NODE-06'),
    [string]$ResourceGroup = 'rg-azlocal-poc-001',
    [int]$Iterations = 30,
    [int]$IntervalSeconds = 60
)

$log = Join-Path $PSScriptRoot '..\out\_monitoring-agent-reappear.txt'
for ($i = 1; $i -le $Iterations; $i++) {
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line  = "[$stamp] "
    $back  = $false
    foreach ($n in $Nodes) {
        $names = az connectedmachine extension list -g $ResourceGroup --machine-name $n --query "[].name" -o tsv 2>$null
        $short = ($n -replace 'AZL-NODE-','')
        if ($names -match 'SecurityMonitoringAgent') { $line += "$short=BACK "; $back = $true }
        else { $line += "$short=gone " }
    }
    Write-Host $line
    $line | Add-Content $log
    if ($back) { Write-Host "  *** SecurityMonitoringAgent REAPPEARED - tag NOT honored at this scope; escalate to subscription scope. ***" -ForegroundColor Red }
    if ($i -lt $Iterations) { Start-Sleep -Seconds $IntervalSeconds }
}
Write-Host "watch complete - if all 'gone' throughout, the tag is honored at resource/RG scope." -ForegroundColor Green
