<#
.SYNOPSIS
  Poll Arc mandatory-extension state across the Azure Local POC nodes and, for any
  extension that is not Succeeded, dump the failure detail so remediation is immediate.

.DESCRIPTION
  Azure Local requires 5 mandatory Arc extensions per node before the deployment
  "Select machines" page reports ready:
    AzureEdgeDeviceManagement, AzureEdgeTelemetryAndDiagnostics,
    AzureEdgeRemoteSupport, SecurityMonitoringAgent, AzureEdgeLifecycleManager
  This script reports provisioningState per extension. For anything in a Failed
  state it pulls the instanceView status message + code (the real error text that
  the portal truncates), so we can move fast on a fix.

  Read-only. Uses az CLI (connectedmachine extension). No node WinRM needed.

.PARAMETER ResourceGroup
  RG holding the Arc machines. Default: rg-azlocal-poc-001

.PARAMETER Nodes
  Arc machine names. Default: the 4 POC nodes (01/02/04/06).

.EXAMPLE
  .\scripts\Watch-ArcExtensions.ps1
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-azlocal-poc-001',
    [string[]]$Nodes = @('AZL-NODE-01','AZL-NODE-02','AZL-NODE-04','AZL-NODE-06')
)

$ErrorActionPreference = 'Stop'

# The 5 extensions Azure Local requires before a machine validates.
$required = @(
    'AzureEdgeDeviceManagement',
    'AzureEdgeTelemetryAndDiagnostics',
    'AzureEdgeRemoteSupport',
    'SecurityMonitoringAgent',
    'AzureEdgeLifecycleManager'
)

$allGreen = $true
$failures = New-Object System.Collections.Generic.List[object]

foreach ($n in $Nodes) {
    Write-Host ""
    Write-Host "=== $n ===" -ForegroundColor Cyan

    # tsv with a bracket (not brace) projection to avoid shell quoting issues.
    $raw = az connectedmachine extension list -g $ResourceGroup --machine-name $n `
        --query "[].[name,properties.provisioningState]" -o tsv 2>$null

    if (-not $raw) {
        Write-Host "  (no extensions returned - machine not onboarded or CLI error)" -ForegroundColor Yellow
        $allGreen = $false
        continue
    }

    # Build a name -> state map from the tsv lines.
    $state = @{}
    foreach ($line in $raw) {
        $parts = $line -split "`t"
        if ($parts.Count -ge 2) { $state[$parts[0]] = $parts[1] }
    }

    foreach ($ext in $required) {
        if (-not $state.ContainsKey($ext)) {
            Write-Host ("  {0,-34} MISSING" -f $ext) -ForegroundColor Yellow
            $allGreen = $false
            continue
        }
        $s = $state[$ext]
        switch -Regex ($s) {
            'Succeeded' { Write-Host ("  {0,-34} {1}" -f $ext, $s) -ForegroundColor Green }
            'Failed'    {
                Write-Host ("  {0,-34} {1}" -f $ext, $s) -ForegroundColor Red
                $allGreen = $false
                $failures.Add([pscustomobject]@{ Node = $n; Extension = $ext })
            }
            default     {
                # Creating / Updating / Deleting / etc.
                Write-Host ("  {0,-34} {1}" -f $ext, $s) -ForegroundColor Yellow
                $allGreen = $false
            }
        }
    }
}

# For every Failed extension, pull the real error text (instance view status).
if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "===== FAILURE DETAIL (instanceView) =====" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host ""
        Write-Host ("--- {0} / {1} ---" -f $f.Node, $f.Extension) -ForegroundColor Red
        # instanceView.status carries code + message; also surface any error from status.
        az connectedmachine extension show -g $ResourceGroup `
            --machine-name $f.Node -n $f.Extension `
            --query "{state:properties.provisioningState, statusCode:properties.instanceView.status.code, statusLevel:properties.instanceView.status.level, message:properties.instanceView.status.message}" `
            -o yaml 2>$null
    }
}

Write-Host ""
if ($allGreen) {
    Write-Host "ALL 4 NODES: all 5 mandatory extensions Succeeded. Machine page should be ready." -ForegroundColor Green
} else {
    Write-Host "Not ready yet (or failures present above). Re-run to re-poll." -ForegroundColor Yellow
}
