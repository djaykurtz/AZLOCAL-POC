<#
.SYNOPSIS
  Make Azure Local data disks poolable using the PROVEN diskpart method
  (clear readonly + clean + Update-StorageProviderCache). Handles the two
  states Clear-DataDisks.ps1 cannot: stuck read-only flag, and RAW disks.

.DESCRIPTION
  Clear-DataDisks.ps1's Set-Disk/Clear-Disk path fails on:
    - read-only-locked disks ("The disk is read only")  [node 01 state]
    - raw/uninitialized disks ("has not been initialized") [nodes 04/06 state]
  This script uses diskpart, which handles both, exactly as proven on nodes
  01 and 02 earlier. It selects DATA disks by ATTRIBUTE (never hardcoded
  numbers), guards the OS/boot disk, and refreshes the Storage Spaces cache
  (the step that flips CanPool=True).

.PARAMETER Nodes
  Node numbers, e.g. 01,04,06.

.PARAMETER MaxDataDiskGB
  Upper size bound for a data disk (default 550; data=477GB, boot=954GB).

.PARAMETER Execute
  Actually clear. Without it, dry-run (report the selected disks only).

.EXAMPLE
  .\scripts\Clear-DataDisksDiskpart.ps1 -Nodes 01,04,06            # dry run
  .\scripts\Clear-DataDisksDiskpart.ps1 -Nodes 01,04,06 -Execute   # clear
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @('01'),
  [int]      $MaxDataDiskGB = 550,
  [switch]   $Execute
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\azloc-local-admin.cred" -Raw).Trim())

foreach ($n in $Nodes) {
  $nn = '{0:00}' -f [int]$n
  $short = "azl-node-$nn"; $fqdn = "$short.lab.example.com"
  Write-Host "`n===== $short  (mode: $(if($Execute){'EXECUTE'}else{'DRY-RUN'})) =====" -ForegroundColor Cyan
  $c = [pscredential]::new("$short\Administrator", $pw)
  $sopt = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 300000
  try { $s = New-PSSession -ComputerName $fqdn -Credential $c -Authentication Negotiate -SessionOption $sopt -ErrorAction Stop }
  catch { Write-Host "  UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red; continue }

  try {
    Invoke-Command -Session $s -ArgumentList $MaxDataDiskGB, [bool]$Execute -ScriptBlock {
      param($maxGB, $doClear)
      $ErrorActionPreference = 'Continue'

      # 1) Identify OS/boot disk(s) independently — never touch these.
      $osNums = @((Get-Disk | Where-Object { $_.IsBoot -or $_.IsSystem }).Number)
      "OS/boot disk number(s) PROTECTED: $($osNums -join ', ')"

      # 2) Select data disks by ATTRIBUTE (non-boot, non-system, <=maxGB, NVMe).
      $data = Get-Disk | Where-Object {
        -not $_.IsBoot -and -not $_.IsSystem -and ($_.Number -notin $osNums) -and
        (($_.Size/1GB) -le $maxGB) -and ($_.BusType -eq 'NVMe')
      } | Sort-Object Number
      if (-not $data) { "No eligible data disks found."; return }

      # HARD SAFETY: abort if any OS disk leaked in.
      if ($data | Where-Object { $_.Number -in $osNums }) { Write-Error "ABORT: OS disk in target set"; return }

      "Data disks selected: $((@($data.Number)) -join ', ')"
      if (-not $doClear) { "DRY-RUN — no changes. Re-run with -Execute."; return }

      # 3) Build diskpart script dynamically from selected numbers.
      $lines = @('san policy=OnlineAll')
      foreach ($d in $data) {
        $lines += "select disk $($d.Number)"
        $lines += 'attributes disk clear readonly'
        $lines += 'online disk noerr'
        $lines += 'clean'
      }
      $lines += 'exit'
      $tmp = Join-Path $env:TEMP 'dp_clear.txt'
      Set-Content -Path $tmp -Value ($lines -join "`r`n") -Encoding Ascii
      (diskpart /s $tmp) 2>&1 | Out-String
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue

      # 4) The step that flips CanPool.
      Update-StorageProviderCache -DiscoveryLevel Full -ErrorAction SilentlyContinue
      Update-HostStorageCache -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 5

      "=== poolable disks now ==="
      Get-PhysicalDisk | Sort-Object DeviceId |
        Format-Table DeviceId,FriendlyName,BusType,@{n='GB';e={[math]::Round($_.Size/1GB,0)}},CanPool,CannotPoolReason -Auto | Out-String
      "CanPool count: $((@(Get-PhysicalDisk | Where-Object CanPool)).Count)"
    }
  }
  finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
}
