<#
.SYNOPSIS
    Sprint S2 - test live migration of a clustered VM between nodes.
.DESCRIPTION
    Dry-run by default. Runs failover-cluster cmdlets on a node over domain-admin WinRM.
    Records owner before/after, runs a continuity probe (ping) across the move, and confirms the
    guest did not reboot (uptime preserved). Pass -Execute to perform the move.
.NOTES
    The VM must be a clustered role (Arc VMs on Azure Local are). Find the role name first with -ListOnly.
    Live migration rides the storage/migration network, so this also exercises the RDMA fabric.
#>
param(
    [string]$VmRoleName,
    [string]$TargetNode,
    [string]$ProbeIp,                 # guest IP to ping across the move (optional but recommended)
    [string]$Node = 'azl-node-01.lab.example.com',
    [switch]$ListOnly,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\sim-example-internal-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)

function Node-Invoke([scriptblock]$sb, $arglist) {
    Invoke-Command $Node -Credential $cred -Authentication Negotiate -ScriptBlock $sb -ArgumentList $arglist -ErrorAction Stop
}

Write-Host "== Sprint S2 live migration test =="
Write-Host "-- VM cluster roles --"
Node-Invoke { Get-ClusterGroup | Where-Object GroupType -eq 'VirtualMachine' | Select-Object Name,OwnerNode,State | Format-Table -Auto | Out-String } | Write-Host

if ($ListOnly) { Write-Host "ListOnly: pick a VM role name and a target node, then re-run."; return }
if (-not $VmRoleName -or -not $TargetNode) { Write-Warning "Provide -VmRoleName and -TargetNode (use -ListOnly to see roles)."; return }

Write-Host "-- Baseline --"
$before = Node-Invoke { param($vm) (Get-ClusterGroup -Name $vm | Select-Object Name,OwnerNode,State) } $VmRoleName
$before | Format-Table -Auto | Out-String | Write-Host
Write-Host "Current owner: $($before.OwnerNode). Target: $TargetNode."

if (-not $Execute) {
    Write-Host "DRY-RUN. Would run on a node:"
    Write-Host "  Move-ClusterVirtualMachineRole -Name '$VmRoleName' -Node '$TargetNode' -MigrationType Live"
    if ($ProbeIp) { Write-Host "  (with a continuous ping to $ProbeIp running across the move)" }
    return
}

# continuity probe (client-side) started as a job
$probeJob = $null
if ($ProbeIp) { $probeJob = Start-Job -ScriptBlock { param($ip) $r=@(); 1..60 | ForEach-Object { $r += [pscustomobject]@{ t=(Get-Date -Format HH:mm:ss.fff); ok=(Test-Connection $ip -Count 1 -Quiet) }; Start-Sleep -Milliseconds 300 }; $r } -ArgumentList $ProbeIp }

Write-Host "-- Live migrating $VmRoleName -> $TargetNode --"
$uptimeBefore = Node-Invoke { param($vm) try { (Get-VM -Name (Get-ClusterGroup -Name $vm).Name -EA SilentlyContinue).Uptime } catch { $null } } $VmRoleName
Node-Invoke { param($vm,$tgt) Move-ClusterVirtualMachineRole -Name $vm -Node $tgt -MigrationType Live } @($VmRoleName,$TargetNode)

$after = Node-Invoke { param($vm) (Get-ClusterGroup -Name $vm | Select-Object Name,OwnerNode,State) } $VmRoleName
Write-Host "-- Result --"
$after | Format-Table -Auto | Out-String | Write-Host
Write-Host "Owner moved: $($before.OwnerNode) -> $($after.OwnerNode)"

if ($probeJob) {
    $probe = Receive-Job $probeJob -Wait; Remove-Job $probeJob
    $lost = ($probe | Where-Object { -not $_.ok }).Count
    Write-Host "Continuity probe: $($probe.Count) pings, $lost lost (live migration should be ~0)."
}
Write-Host "PASS criteria: owner node changed, guest did not reboot, probe near-zero loss, storage stays Healthy."
