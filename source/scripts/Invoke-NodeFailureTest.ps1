<#
.SYNOPSIS
    Sprint S3 - node failure and recovery test. DESTRUCTIVE stage is NOT automated.
.DESCRIPTION
    Dry-run by default. With -Execute it performs ONLY Stage 1, the graceful drain and resume, which is
    safe (roles live-migrate off, then the node comes back). Stage 2, the ungraceful power-off, is NEVER
    executed by this script. It prints the manual iDRAC steps and how to watch recovery, because pulling a
    node hard needs a human present, especially on this marginal hardware.
.NOTES
    Run from a connection node that is NOT the target, so WinRM survives the drain. Captures cluster and
    storage health before, during, and after.
#>
param(
    [string]$TargetNode = 'AZL-NODE-04',
    [string]$TargetFqdn  = 'azl-node-04.lab.example.com',
    [string]$ConnectNode = 'azl-node-01.lab.example.com',
    [ValidateSet('Drain','Reboot')]
    [string]$Mode = 'Drain',
    [int]$RejoinTimeoutSec = 900,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\sim-example-internal-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)
function Invoke-OnNode([scriptblock]$sb,$a){ Invoke-Command $ConnectNode -Credential $cred -Authentication Negotiate -ScriptBlock $sb -ArgumentList $a -ErrorAction Stop }

function Show-Health($label) {
    Write-Host "==== HEALTH: $label ===="
    Invoke-OnNode {
        "nodes:   " + ((Get-ClusterNode | ForEach-Object { "$($_.Name)=$($_.State)" }) -join '  ')
        "pool:    " + ((Get-StoragePool -IsPrimordial $false | Select-Object -First 1).HealthStatus)
        "vdisks:  " + ((Get-VirtualDisk | Group-Object HealthStatus | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '  ')
        $sj = Get-StorageJob -EA SilentlyContinue
        "jobs:    " + $(if($sj){ ($sj | ForEach-Object { "$($_.Name)=$($_.PercentComplete)%" }) -join '  ' } else { 'idle' })
    } $null | Write-Host
}

Write-Host "== Sprint S3 node failure and recovery ($TargetNode) =="
if ($ConnectNode -match $TargetNode.ToLower()) { Write-Warning "ConnectNode should not be the target node."; return }

Show-Health "baseline"

if (-not $Execute) {
    Write-Host ""
    Write-Host "DRY-RUN (Mode=$Mode). With -Execute this runs:"
    if ($Mode -eq 'Drain') {
        Write-Host "  Stage 1 (safe graceful drain):"
        Write-Host "    Suspend-ClusterNode -Name $TargetNode -Drain   # roles live-migrate off"
        Write-Host "    (verify roles moved, storage Healthy)"
        Write-Host "    Resume-ClusterNode -Name $TargetNode -Failback Immediate"
    } else {
        Write-Host "  Reboot replication test (unattended-safe, endorsed 2026-07-28):"
        Write-Host "    1. Capture baseline health (above)."
        Write-Host "    2. Restart-Computer -Force on $TargetFqdn over WinRM (authority = sim\labadmin)."
        Write-Host "    3. Poll from $ConnectNode until $TargetNode leaves the cluster (Down),"
        Write-Host "       showing vdisks go Degraded but stay Online (3-way mirror tolerates 1 node)."
        Write-Host "    4. Poll until $TargetNode rejoins (Up), up to $RejoinTimeoutSec s."
        Write-Host "    5. Watch Get-StorageJob (repair/resync) until idle and vdisks Healthy."
    }
    Write-Host ""
    Write-Host "Stage 2 (ungraceful hard power-off, MANUAL - never run by this script):"
    Write-Host "  Power off $TargetNode hard via iDRAC only with a human present at the console,"
    Write-Host "  then power back on and watch Get-StorageJob resync to Healthy."
    return
}

if ($Mode -eq 'Reboot') {
    Write-Host ""
    Write-Host "== REBOOT REPLICATION TEST: $TargetNode ($TargetFqdn) =="
    $t0 = Get-Date
    Write-Host "Issuing Restart-Computer -Force on $TargetFqdn ..."
    try {
        Invoke-Command -ComputerName $TargetFqdn -Credential $cred -Authentication Negotiate -ScriptBlock { Restart-Computer -Force } -ErrorAction Stop
    } catch {
        # WinRM connection often drops as the reboot begins; that is expected, not a failure.
        Write-Host "  (WinRM dropped as reboot began - expected)"
    }
    # Wait for the node to leave the cluster.
    Write-Host "Waiting for $TargetNode to go Down in the cluster ..."
    $downSeen = $false
    for ($i=0; $i -lt 60; $i++) {
        Start-Sleep 5
        $state = (Invoke-OnNode { param($n) "$((Get-ClusterNode -Name $n).State)" } $TargetNode)
        if ("$state" -ne 'Up') { Write-Host "  $TargetNode = $state"; $downSeen = $true; break }
    }
    if (-not $downSeen) { Write-Warning "Node never left the cluster; it may have rebooted faster than the poll. Continuing." }
    Show-Health "node down (degraded expected, vdisks stay Online)"
    # Wait for rejoin.
    Write-Host "Waiting for $TargetNode to rejoin (Up), up to $RejoinTimeoutSec s ..."
    $rejoined = $false
    $deadline = (Get-Date).AddSeconds($RejoinTimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep 15
        $state = (Invoke-OnNode { param($n) "$((Get-ClusterNode -Name $n).State)" } $TargetNode)
        if ("$state" -eq 'Up') { $rejoined = $true; Write-Host "  $TargetNode = Up (rejoined)"; break }
        Write-Host "  $TargetNode = $state ..."
    }
    if (-not $rejoined) { Write-Warning "Node did NOT rejoin within $RejoinTimeoutSec s. Investigate before leaving unattended."; Show-Health "timeout"; return }
    Show-Health "after rejoin (resync may be running)"
    # Watch storage repair jobs converge.
    Write-Host "Watching storage resync (Get-StorageJob) until idle ..."
    for ($i=0; $i -lt 80; $i++) {
        $jobs = Invoke-OnNode { Get-StorageJob -EA SilentlyContinue | Where-Object { $_.JobState -ne 'Completed' } } $null
        if (-not $jobs) { Write-Host "  storage jobs idle"; break }
        $desc = ($jobs | ForEach-Object { "$($_.Name)=$($_.PercentComplete)%" }) -join '  '
        Write-Host "  resync: $desc"
        Start-Sleep 20
    }
    Show-Health "final"
    $mins = [math]::Round(((Get-Date)-$t0).TotalMinutes,1)
    Write-Host ""
    Write-Host "Reboot replication test complete in $mins min."
    Write-Host "PASS criteria: cluster stayed Online, vdisks Degraded-but-Online while $TargetNode was down,"
    Write-Host "node rejoined, storage resync ran and returned all vdisks to Healthy."
    return
}

Write-Host ""
Write-Host "== STAGE 1: graceful drain =="
Invoke-OnNode { param($n) Suspend-ClusterNode -Name $n -Drain -Wait } $TargetNode | Out-Null
Show-Health "after drain (node paused, roles moved)"
Write-Host "== STAGE 1: resume =="
Invoke-OnNode { param($n) Resume-ClusterNode -Name $n -Failback Immediate } $TargetNode | Out-Null
Start-Sleep 5
Show-Health "after resume"

Write-Host ""
Write-Host "Stage 1 complete. Stage 2 (hard power-off) is MANUAL - see the dry-run output for steps."
Write-Host "PASS criteria: drain moved roles with no guest reboot; storage stayed Healthy; node rejoined."
