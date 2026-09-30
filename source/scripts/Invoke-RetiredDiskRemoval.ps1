<#
.SYNOPSIS
  Removes the already-retired node 01 NVMe record from SU1_Pool. State changing. Approved 2026-08-28.

.DESCRIPTION
  Recovery ladder step 2 of docs/runbooks/node01-retired-nvme-recovery.md, the POC decommission
  option with no physical removal.

  Preconditions were gathered by Invoke-RetiredDiskReadiness.ps1 and passed: pool Healthy with
  3671 GB free against a 445 GB UserStorage_2 footprint, twelve healthy members, and exactly one
  disk matching the retired identity.

  This script re-verifies the target immediately before acting and refuses on any mismatch. It
  targets the immutable UniqueId, never a friendly name, because four disks in this pool report the
  same PhysicalLocation string and three of them are healthy.

  After removal, repair rebuilds the third mirror copy of UserStorage_2 across remaining capacity.
  Keep ws2025-core-01 and rocky-docker-01 stopped and do not apply Terraform until it completes.

.PARAMETER WhatIf
  Re-verify and report, then stop without removing.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [string]$Node = 'azl-node-01.lab.example.com',
  [string]$CredentialPath = '.\.creds\sim-example-internal-admin.cred',
  [string]$UserName = 'sim\labadmin',
  [string]$UniqueId = '{00000000-0000-0000-0000-000000000005}',
  [string]$PoolName = 'SU1_Pool',
  [string]$OutputPath = '.\out'
)

$ErrorActionPreference = 'Stop'

$pw = ConvertTo-SecureString ((Get-Content $CredentialPath -Raw).Trim())
$cred = [pscredential]::new($UserName, $pw)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$outFile = Join-Path $OutputPath "_retired-disk-removal-$stamp.txt"

$doIt = -not $WhatIfPreference

$result = Invoke-Command -ComputerName $Node -Credential $cred -Authentication Negotiate -ScriptBlock {
  param($uid, $pool, $execute)

  $out = [System.Collections.Generic.List[string]]::new()
  function W { param($s) $out.Add([string]$s) }

  $d = @(Get-PhysicalDisk | Where-Object UniqueId -eq $uid)

  W '== Pre-check =='
  if ($d.Count -ne 1) { W "ABORT: matched $($d.Count) disks, expected exactly 1."; return $out }
  if ($d[0].Usage -ne 'Retired') { W "ABORT: Usage is '$($d[0].Usage)', expected 'Retired'."; return $out }
  if ($d[0].HealthStatus -eq 'Healthy') { W 'ABORT: target reports Healthy. Refusing.'; return $out }

  W ("  {0}" -f $d[0].FriendlyName)
  W ("  Serial   {0}" -f $d[0].SerialNumber)
  W ("  UniqueId {0}" -f $d[0].UniqueId)
  W ("  Usage {0}   Health {1}   Op {2}" -f $d[0].Usage, $d[0].HealthStatus, ($d[0].OperationalStatus -join ','))

  if (-not $execute) { W ''; W 'WhatIf: stopping before removal.'; return $out }

  W ''
  W "== Removing from $pool =="
  try {
    Remove-PhysicalDisk -PhysicalDisks $d[0] -StoragePoolFriendlyName $pool -Confirm:$false -ErrorAction Stop
    W '  Remove-PhysicalDisk completed without error.'
  } catch {
    W "  FAILED: $($_.Exception.Message)"
    return $out
  }

  W ''
  W '== Post-check =='
  $p = Get-StoragePool -IsPrimordial $false
  W ("  Pool {0}: {1} / {2}, free {3} GB" -f $p.FriendlyName, $p.HealthStatus,
      ($p.OperationalStatus -join ','), [math]::Round(($p.Size - $p.AllocatedSize)/1GB, 1))

  Get-VirtualDisk | Sort-Object FriendlyName | ForEach-Object {
    W ("  {0,-26} {1,-8} {2}" -f $_.FriendlyName, $_.HealthStatus, ($_.OperationalStatus -join ','))
  }

  $j = @(Get-StorageJob)
  if ($j) { $j | ForEach-Object { W ("  job {0}  {1}  {2}%" -f $_.Name, $_.JobState, $_.PercentComplete) } }
  else { W '  no storage jobs running' }

  W ("  physical disks: {0}   still retired: {1}" -f @(Get-PhysicalDisk).Count,
      @(Get-PhysicalDisk | Where-Object Usage -eq 'Retired').Count)

  $out
} -ArgumentList $UniqueId, $PoolName, $doIt

$result | ForEach-Object { Write-Host $_ }
$result -join "`n" | Set-Content -Path $outFile -Encoding utf8
Write-Host ''
Write-Host "Written to $outFile" -ForegroundColor DarkGray
