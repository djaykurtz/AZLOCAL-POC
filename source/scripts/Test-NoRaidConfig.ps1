<#
.SYNOPSIS
  Read-only RAID/VMD/VROC sweep across all Azure Local nodes.

.DESCRIPTION
  For each reachable node, reports anything that would make an NVMe drive
  enumerate as BusType=RAID instead of NVMe (which Azure Local S2D rejects):
    - PhysicalDisks whose BusType is RAID
    - Any disk/controller exposing a RAID bus
    - Intel VMD / VROC / RST storage controllers (PnP)
    - Storage controllers reporting a RAID-y FriendlyName
    - StorageReliabilityCounter / VirtualDisk / StoragePool remnants
  Pure read-only: only Get-* calls, no changes.

.EXAMPLE
  .\scripts\Test-NoRaidConfig.ps1
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @(1,2,3,4,5,6 | ForEach-Object { "azl-node-0$_.lab.example.com" }),
  [string]   $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
  [string]   $Username = 'Administrator'
)

$ErrorActionPreference = 'Stop'
if (-not $CredFile -or -not (Test-Path $CredFile)) { throw "CredFile not found: $CredFile" }
$pw = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())

$results = foreach ($fqdn in $Nodes) {
  $short = ($fqdn -split '\.')[0]
  $cred  = [pscredential]::new("$short\$Username", $pw)
  $opt   = New-PSSessionOption -OpenTimeout 8000 -OperationTimeout 120000
  try {
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $opt -ErrorAction Stop
  } catch {
    [pscustomobject]@{ Node=$short; Reachable=$false; RaidDisks=''; VmdVroc=''; RaidControllers=''; Pools=''; Verdict='UNREACHABLE' }
    continue
  }
  try {
    Invoke-Command -Session $s -ScriptBlock {
      # 1. Physical disks by BusType
      $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue
      $raidDisks = $pd | Where-Object { "$($_.BusType)" -eq 'RAID' } |
        ForEach-Object { "{0}[{1}/{2}/{3}GB/Boot={4}]" -f $_.DeviceId, $_.FriendlyName, $_.BusType, [math]::Round($_.Size/1GB,0), $_.IsBoot }

      # 2. Intel VMD / VROC / RST controllers via PnP
      $vmd = Get-PnpDevice -Class 'SCSIAdapter','System' -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'Volume Management Device|VMD|VROC|Rapid Storage|RAID' } |
        Select-Object -ExpandProperty FriendlyName -Unique

      # 3. Storage controllers reporting RAID-y names
      $ctrl = Get-CimInstance Win32_SCSIController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'RAID|VMD|VROC|Rapid Storage|Volume Management' } |
        Select-Object -ExpandProperty Name -Unique

      # 4. Any leftover storage pools / virtual disks (S2D remnants)
      $pools = Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { -not $_.IsPrimordial } |
        Select-Object -ExpandProperty FriendlyName
      $vdisks = Get-VirtualDisk -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FriendlyName

      # 5. All BusTypes present (context)
      $busSummary = ($pd | Group-Object BusType | ForEach-Object { "{0}x{1}" -f $_.Count, $_.Name }) -join ', '

      $hasRaid = [bool]($raidDisks -or $ctrl)
      $hasVmd  = [bool]$vmd

      [pscustomobject]@{
        Node            = $env:COMPUTERNAME
        Reachable       = $true
        BusSummary      = $busSummary
        RaidDisks       = ($raidDisks -join '; ')
        VmdVroc         = (($vmd + $ctrl | Select-Object -Unique) -join '; ')
        Pools           = ((@($pools) + @($vdisks)) -join '; ')
        Verdict         = if ($hasRaid -or $hasVmd) { 'RAID/VMD PRESENT' } else { 'CLEAN (no RAID/VMD)' }
      }
    }
  } finally {
    Remove-PSSession $s -ErrorAction SilentlyContinue
  }
}

$results | Sort-Object Node | Format-List Node, Reachable, Verdict, BusSummary, RaidDisks, VmdVroc, Pools
Write-Host "`n===== ROLL-UP =====" -ForegroundColor Cyan
$results | Sort-Object Node | Format-Table Node, Reachable, Verdict, BusSummary -AutoSize
