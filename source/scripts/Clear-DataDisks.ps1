<#
.SYNOPSIS
  Clear ONLY the Azure Local data disks (non-boot NVMe) on a node so they become
  poolable (CanPool=True). NEVER touches the OS/boot/system disk.

.DESCRIPTION
  Guardrails (a disk is cleared ONLY if ALL are true):
    - IsBoot        = False
    - IsSystem      = False
    - BootFromDisk  = False
    - Size          <= MaxDataDiskGB (default 550 -> matches 477GB PM9A1 data drives)
    - BusType        = NVMe
    - OperationalStatus = Online
  Anything failing these is SKIPPED. If the candidate set is empty, aborts.
  Requires -Confirm2 to actually clear; without it, it only REPORTS what it would do.

.PARAMETER NodeFqdn
  Target node. Default azl-node-01.lab.example.com.

.PARAMETER MaxDataDiskGB
  Upper size bound for a data disk. Default 550 (data drives are 477GB; boot is 954GB).

.PARAMETER Confirm2
  Actually perform Clear-Disk. Omit for a dry run (report only).

.EXAMPLE
  .\scripts\Clear-DataDisks.ps1 -NodeFqdn azl-node-01.lab.example.com            # dry run
.EXAMPLE
  .\scripts\Clear-DataDisks.ps1 -NodeFqdn azl-node-01.lab.example.com -Confirm2  # wipe data disks
#>
[CmdletBinding()]
param(
  [string] $NodeFqdn = 'azl-node-01.lab.example.com',
  [int]    $MaxDataDiskGB = 550,
  [switch] $Confirm2,
  [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
  [string] $Username = 'Administrator'
)

$ErrorActionPreference = 'Stop'
if (-not $CredFile -or -not (Test-Path $CredFile)) { throw "CredFile not found: $CredFile" }
$pw = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
$short = ($NodeFqdn -split '\.')[0]
$cred  = [pscredential]::new("$short\$Username", $pw)
$opt   = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 300000
$s = New-PSSession -ComputerName $NodeFqdn -Credential $cred -Authentication Negotiate -SessionOption $opt

try {
  $result = Invoke-Command -Session $s -ArgumentList $MaxDataDiskGB, [bool]$Confirm2 -ScriptBlock {
    param($maxGB, $doClear)

    $all = Get-Disk | ForEach-Object {
      $d = $_
      $sizeGB = [math]::Round($d.Size/1GB,0)
      $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq $d.Number }
      [pscustomobject]@{
        Number      = $d.Number
        Name        = $d.FriendlyName
        SizeGB      = $sizeGB
        IsBoot      = [bool]$d.IsBoot
        IsSystem    = [bool]$d.IsSystem
        BootFromDisk= [bool]$d.BootFromDisk
        BusType     = "$($d.BusType)"
        OpStatus    = "$($d.OperationalStatus)"
        PartStyle   = "$($d.PartitionStyle)"
        NumPart     = ($d | Get-Partition -ErrorAction SilentlyContinue | Measure-Object).Count
      }
    }

    # STRICT data-disk predicate. Fails safe.
    $candidates = $all | Where-Object {
      -not $_.IsBoot -and -not $_.IsSystem -and -not $_.BootFromDisk -and
      $_.SizeGB -le $maxGB -and $_.BusType -eq 'NVMe' -and $_.OpStatus -eq 'Online'
    }

    $cleared = @()
    if ($doClear) {
      foreach ($c in $candidates) {
        # Re-fetch and re-verify guardrails immediately before destructive op
        $disk = Get-Disk -Number $c.Number
        if ($disk.IsBoot -or $disk.IsSystem -or $disk.BootFromDisk) { continue }   # belt & suspenders
        if ([math]::Round($disk.Size/1GB,0) -gt $maxGB) { continue }
        # Clear leftover pool flags: read-only + offline block Clear-Disk
        if ($disk.IsReadOnly) { Set-Disk -Number $c.Number -IsReadOnly $false -ErrorAction SilentlyContinue }
        if ($disk.IsOffline)  { Set-Disk -Number $c.Number -IsOffline  $false -ErrorAction SilentlyContinue }
        Clear-Disk -Number $c.Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        $cleared += $c.Number
      }
    }

    [pscustomobject]@{
      Node       = $env:COMPUTERNAME
      AllDisks   = $all
      Candidates = ($candidates | ForEach-Object { "disk$($_.Number) $($_.Name) $($_.SizeGB)GB $($_.BusType) parts=$($_.NumPart)" })
      Cleared    = $cleared
      PostState  = if ($doClear) {
        Get-PhysicalDisk | Where-Object { -not $_.IsBoot } | ForEach-Object {
          "disk? $($_.FriendlyName) $([math]::Round($_.Size/1GB,0))GB CanPool=$($_.CanPool) reason=$($_.CannotPoolReason)"
        }
      } else { @() }
    }
  }

  Write-Host "== Node: $($result.Node) ==" -ForegroundColor Cyan
  Write-Host "`nAll disks seen:" -ForegroundColor DarkGray
  $result.AllDisks | Format-Table Number,Name,SizeGB,IsBoot,IsSystem,BootFromDisk,BusType,OpStatus,PartStyle,NumPart -AutoSize

  Write-Host "Data-disk candidates (safe to clear):" -ForegroundColor Yellow
  if ($result.Candidates) { $result.Candidates | ForEach-Object { "  $_" } } else { Write-Host "  (none matched guardrails)" -ForegroundColor Red }

  if ($Confirm2) {
    Write-Host "`nCleared disk numbers: $($result.Cleared -join ', ')" -ForegroundColor Green
    Write-Host "Post-clear pool state:" -ForegroundColor Green
    $result.PostState | ForEach-Object { "  $_" }
  } else {
    Write-Host "`nDRY RUN — nothing changed. Re-run with -Confirm2 to clear the candidates above." -ForegroundColor Magenta
  }
} finally {
  Remove-PSSession $s -ErrorAction SilentlyContinue
}
