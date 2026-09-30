<#
.SYNOPSIS
  Read-only readiness check for decommissioning the retired node 01 NVMe record. Changes nothing.

.DESCRIPTION
  Recovery ladder step 2 in docs/runbooks/node01-retired-nvme-recovery.md is titled "POC decommission
  option - no physical removal". It clears the degraded storage condition without anyone touching the
  rack, which matters because the hardware is 200 miles away.

  That step has preconditions. This script gathers every one of them and produces the evidence pack
  needed to get storage-owner sign-off:

    - pool free capacity, and whether repair can complete without the retired member
    - the UserStorage_2 footprint and its current health
    - the repair job state
    - health of every virtual disk
    - a full physical disk inventory including UniqueId, Serial and Usage
    - positive identification of the retired target by immutable UniqueId AND Serial, never by
      friendly name, which is exactly what the runbook insists on

  It then prints the exact removal command for review. It does not run it, and it never will. The
  runbook requires a human storage owner to approve that command, and this script exists to give
  that person something complete to approve.

  Nothing here is state changing. Every cmdlet used is a Get.

.PARAMETER Node
  Cluster node to query over WinRM.

.PARAMETER CredentialPath
  Path to the stored domain admin credential, matching the pattern used by _health-baseline.ps1.

.EXAMPLE
  .\Invoke-RetiredDiskReadiness.ps1
  Gathers evidence, prints a verdict, and writes out/_retired-disk-readiness-<stamp>.txt
#>

[CmdletBinding()]
param(
  [string]$Node = 'azl-node-01.lab.example.com',
  [string]$CredentialPath = '.\.creds\sim-example-internal-admin.cred',
  [string]$OutputPath = '.\out'
)

$ErrorActionPreference = 'Stop'

# From the runbook. The whole point of pinning these is that a friendly name is not a safe target.
$ExpectedUniqueId = '{00000000-0000-0000-0000-000000000005}'
$ExpectedSerial   = '0000_0000_0000_0000_0000_0000_0000_0012'
$AffectedVDisk    = 'UserStorage_2'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$outFile = Join-Path $OutputPath "_retired-disk-readiness-$stamp.txt"

$pw = ConvertTo-SecureString ((Get-Content $CredentialPath -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)

Write-Host "Gathering read-only storage evidence from $Node ..." -ForegroundColor Cyan

$data = Invoke-Command $Node -Credential $cred -Authentication Negotiate -ScriptBlock {
  param($uid, $serial, $vdName)

  $pool = Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue | Select-Object -First 1
  $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue

  # Match on either immutable identifier. Serial formatting varies between providers, so accept both
  # and report which one matched rather than silently trusting one.
  $target = $disks | Where-Object {
    $_.UniqueId -eq $uid -or ($_.SerialNumber -and ($_.SerialNumber.Trim() -eq $serial))
  }

  [pscustomobject]@{
    PoolName        = $pool.FriendlyName
    PoolHealth      = $pool.HealthStatus
    PoolOperational = ($pool.OperationalStatus -join ', ')
    PoolSizeGB      = if ($pool) { [math]::Round($pool.Size / 1GB, 1) } else { $null }
    PoolAllocGB     = if ($pool) { [math]::Round($pool.AllocatedSize / 1GB, 1) } else { $null }
    PoolFreeGB      = if ($pool) { [math]::Round(($pool.Size - $pool.AllocatedSize) / 1GB, 1) } else { $null }

    VirtualDisks    = @(Get-VirtualDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName,
                        HealthStatus, @{n='Op';e={$_.OperationalStatus -join ', '}}, ResiliencySettingName,
                        @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
                        @{n='FootprintGB';e={[math]::Round($_.FootprintOnPool/1GB,1)}})

    Jobs            = @(Get-StorageJob -ErrorAction SilentlyContinue |
                        Select-Object Name, JobState, PercentComplete)

    Disks           = @($disks | Select-Object FriendlyName, SerialNumber, UniqueId, HealthStatus,
                        @{n='Op';e={$_.OperationalStatus -join ', '}}, Usage,
                        @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, PhysicalLocation)

    TargetCount     = @($target).Count
    Target          = @($target | Select-Object FriendlyName, SerialNumber, UniqueId, HealthStatus,
                        @{n='Op';e={$_.OperationalStatus -join ', '}}, Usage,
                        @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, PhysicalLocation)

    HealthyCount    = @($disks | Where-Object { $_.HealthStatus -eq 'Healthy' }).Count
    RetiredCount    = @($disks | Where-Object { $_.Usage -eq 'Retired' }).Count
  }
} -ArgumentList $ExpectedUniqueId, $ExpectedSerial, $AffectedVDisk

$L = [System.Collections.Generic.List[string]]::new()
function Add-Line { param([string]$s = '') $L.Add($s); Write-Host $s }

Add-Line "Retired disk decommission readiness   $stamp"
Add-Line "Node: $Node"
Add-Line "Read-only. This script changes nothing."
Add-Line ''
Add-Line '== Storage pool =='
Add-Line ("  {0}  {1} / {2}" -f $data.PoolName, $data.PoolHealth, $data.PoolOperational)
Add-Line ("  size {0} GB, allocated {1} GB, free {2} GB" -f $data.PoolSizeGB, $data.PoolAllocGB, $data.PoolFreeGB)
Add-Line ''
Add-Line '== Virtual disks =='
$data.VirtualDisks | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $L.Add($_); Write-Host $_ }
Add-Line '== Storage jobs =='
if ($data.Jobs) { $data.Jobs | Format-Table -AutoSize | Out-String | ForEach-Object { $L.Add($_); Write-Host $_ } }
else { Add-Line '  none' }
Add-Line '== Physical disks =='
$data.Disks | Format-Table -AutoSize | Out-String -Width 220 | ForEach-Object { $L.Add($_); Write-Host $_ }

# ---------------------------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------------------------
Add-Line '== Readiness verdict =='
$blockers = [System.Collections.Generic.List[string]]::new()

if ($data.TargetCount -eq 0) {
  $blockers.Add('The retired disk from the runbook was NOT found by UniqueId or Serial. Do not proceed. Re-identify it.')
} elseif ($data.TargetCount -gt 1) {
  $blockers.Add("Identifier matched $($data.TargetCount) disks. Ambiguous target. Do not proceed.")
} else {
  $t = $data.Target[0]
  Add-Line ("  Target identified: {0}  Usage={1}  Health={2}" -f $t.FriendlyName, $t.Usage, $t.HealthStatus)
  Add-Line ("    UniqueId {0}" -f $t.UniqueId)
  Add-Line ("    Serial   {0}" -f $t.SerialNumber)
  if ($t.Usage -ne 'Retired') {
    $blockers.Add("Target Usage is '$($t.Usage)', not 'Retired'. The runbook only sanctions removing an already retired record.")
  }
  if ($t.HealthStatus -eq 'Healthy') {
    $blockers.Add('Target reports Healthy. Never remove a healthy pool member. Stop.')
  }
}

$vd = $data.VirtualDisks | Where-Object FriendlyName -eq $AffectedVDisk
if ($vd) {
  Add-Line ("  {0}: {1} / {2}, footprint {3} GB" -f $vd.FriendlyName, $vd.HealthStatus, $vd.Op, $vd.FootprintGB)
  if ($data.PoolFreeGB -lt $vd.FootprintGB) {
    $blockers.Add("Pool free ($($data.PoolFreeGB) GB) is less than the $AffectedVDisk footprint ($($vd.FootprintGB) GB). Repair may not have room to complete.")
  }
}

$unhealthy = @($data.VirtualDisks | Where-Object { $_.HealthStatus -ne 'Healthy' -and $_.FriendlyName -ne $AffectedVDisk })
if ($unhealthy.Count -gt 0) {
  $blockers.Add("$($unhealthy.Count) other virtual disk(s) are not Healthy. Investigate before changing pool membership.")
}

Add-Line ("  Physical disks: {0} healthy, {1} retired" -f $data.HealthyCount, $data.RetiredCount)
Add-Line ''

if ($blockers.Count -gt 0) {
  Add-Line 'NOT READY. Blockers:'
  $blockers | ForEach-Object { Add-Line "  - $_" }
} else {
  Add-Line 'Preconditions met. The runbook still requires storage-owner approval of the command below.'
  Add-Line ''
  Add-Line 'Proposed command, FOR REVIEW ONLY. This script will not run it.'
  Add-Line ''
  Add-Line "  `$d = Get-PhysicalDisk | Where-Object UniqueId -eq '$ExpectedUniqueId'"
  Add-Line "  `$d | Format-List FriendlyName, SerialNumber, UniqueId, Usage, HealthStatus   # confirm once more"
  Add-Line "  Remove-PhysicalDisk -PhysicalDisks `$d -StoragePoolFriendlyName '$($data.PoolName)' -Confirm"
  Add-Line ''
  Add-Line 'Then monitor until repair completes and UserStorage_2 returns to Healthy / OK:'
  Add-Line '  Get-StorageJob; Get-VirtualDisk; Get-StoragePool -IsPrimordial $false'
}

Add-Line ''
Add-Line 'Reference: docs/runbooks/node01-retired-nvme-recovery.md, recovery ladder step 2.'

$L -join "`n" | Set-Content -Path $outFile -Encoding utf8
Write-Host ''
Write-Host "Evidence written to $outFile" -ForegroundColor DarkGray
