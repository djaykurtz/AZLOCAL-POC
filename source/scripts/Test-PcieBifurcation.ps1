<#
.SYNOPSIS
  Read-only PCIe bifurcation / NVMe topology inspector for Azure Local nodes.

.DESCRIPTION
  BIOS "Slot N Bifurcation Control" is NOT directly readable from Windows. For a
  PASSIVE M.2 carrier, bifurcation is instead INFERRED from PCIe topology:
    - Each populated M.2 should appear as its own NVMe controller/endpoint.
    - Each endpoint should negotiate PCIe link width x4 (a x16 slot split 4 ways).
    - If bifurcation is OFF, a passive card presents only the FIRST drive -> a
      drive-count shortfall vs. how many M.2 slots are populated.

  This script reports, per node:
    - NVMe controllers (PnP), their PCIe location (Segment/Bus/Device/Function),
      and the parent PCIe root port,
    - Current vs. Max PCIe link width + speed per NVMe function (from the device's
      PCI Express Link Control/Status, surfaced via Get-PnpDeviceProperty),
    - PhysicalDisk BusType / MediaType / Size for cross-reference,
    - A heuristic verdict on how many distinct NVMe endpoints are present and
      whether their widths look like x4-bifurcated lanes.

  Pure read-only. Run BEFORE cards arrive for a baseline, and AFTER install to
  confirm 2-4 NVMe endpoints at x4 each.

.PARAMETER ExpectedM2PerNode
  How many M.2 drives you expect populated per node after install (for the
  bifurcation verdict). Default 2 (matches ADR 0003 "2 data drives per node").
  Pre-install you can leave it; the boot drive alone will read as 1 endpoint.

.EXAMPLE
  .\scripts\Test-PcieBifurcation.ps1                      # baseline, all nodes
.EXAMPLE
  .\scripts\Test-PcieBifurcation.ps1 -ExpectedM2PerNode 2 # post-install check
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @(1,2,3,4,5,6 | ForEach-Object { "azl-node-0$_.lab.example.com" }),
  [int]      $ExpectedM2PerNode = 2,
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
    [pscustomobject]@{ Node=$short; Reachable=$false; NvmeEndpoints=0; Detail=''; Verdict='UNREACHABLE' }
    continue
  }
  try {
    Invoke-Command -Session $s -ArgumentList $ExpectedM2PerNode -ScriptBlock {
      param($expectM2)

      # PCI Express Link Capability/Status property keys (DEVPKEY PCI Express)
      $K_CurWidth = 'DEVPKEY_PciDevice_CurrentLinkWidth'
      $K_MaxWidth = 'DEVPKEY_PciDevice_MaxLinkWidth'
      $K_CurSpeed = 'DEVPKEY_PciDevice_CurrentLinkSpeed'
      $K_MaxSpeed = 'DEVPKEY_PciDevice_MaxLinkSpeed'
      $K_Location = 'DEVPKEY_Device_LocationInfo'
      $K_BusNum   = 'DEVPKEY_Device_BusNumber'
      $K_Address  = 'DEVPKEY_Device_Address'

      function Get-Prop($id, $key) {
        try { (Get-PnpDeviceProperty -InstanceId $id -KeyName $key -ErrorAction Stop).Data } catch { $null }
      }

      # NVMe controllers via PnP (class SCSIAdapter / storage; match NVMe in name or service stornvme)
      $nvme = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Class -in 'SCSIAdapter','DiskDrive','System' -and
                       ($_.FriendlyName -match 'NVM[e]?|NVM Express' -or $_.Service -eq 'stornvme') }

      # Also pull standard NVMe controllers directly
      $nvmeCtrls = Get-PnpDevice -PresentOnly -Class 'SCSIAdapter' -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'NVM' }
      $all = @($nvme) + @($nvmeCtrls) | Sort-Object InstanceId -Unique

      $rows = foreach ($d in $all) {
        $cw = Get-Prop $d.InstanceId $K_CurWidth
        $mw = Get-Prop $d.InstanceId $K_MaxWidth
        $cs = Get-Prop $d.InstanceId $K_CurSpeed
        $ms = Get-Prop $d.InstanceId $K_MaxSpeed
        $loc= Get-Prop $d.InstanceId $K_Location
        $bus= Get-Prop $d.InstanceId $K_BusNum
        [pscustomobject]@{
          Name        = $d.FriendlyName
          Location    = $loc
          Bus         = $bus
          CurWidth    = if ($cw) { "x$cw" } else { '?' }
          MaxWidth    = if ($mw) { "x$mw" } else { '?' }
          CurSpeedGTs = $cs
          MaxSpeedGTs = $ms
        }
      }

      # Physical disk cross-reference
      $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
        "{0}/{1}/{2}GB/Boot={3}" -f $_.FriendlyName, $_.BusType, [math]::Round($_.Size/1GB,0), $_.IsBoot
      }

      $nvmeCount = ($rows | Measure-Object).Count
      $x4ish = @($rows | Where-Object { $_.CurWidth -in 'x4','x2','x1' -or $_.MaxWidth -eq 'x4' }).Count

      $verdict =
        if ($nvmeCount -ge $expectM2 -and $x4ish -ge 1) {
          "OK: $nvmeCount NVMe endpoint(s); $x4ish at <=x4 (consistent with bifurcation)"
        } elseif ($nvmeCount -lt $expectM2) {
          "CHECK: only $nvmeCount NVMe endpoint(s) for $expectM2 expected M.2 -> bifurcation may be OFF or drives not seated"
        } else {
          "INFO: $nvmeCount NVMe endpoint(s)"
        }

      [pscustomobject]@{
        Node          = $env:COMPUTERNAME
        Reachable     = $true
        NvmeEndpoints = $nvmeCount
        Detail        = ($rows | ForEach-Object { "{0} [{1}] cur={2}/max={3} spd={4}" -f $_.Name,$_.Location,$_.CurWidth,$_.MaxWidth,$_.CurSpeedGTs }) -join " || "
        Disks         = ($pd -join '; ')
        Verdict       = $verdict
      }
    }
  } finally {
    Remove-PSSession $s -ErrorAction SilentlyContinue
  }
}

$results | Sort-Object Node | Format-List Node, Reachable, NvmeEndpoints, Verdict, Detail, Disks
Write-Host "`n===== ROLL-UP =====" -ForegroundColor Cyan
$results | Sort-Object Node | Format-Table Node, Reachable, NvmeEndpoints, Verdict -AutoSize -Wrap
Write-Host "`nNote: BIOS bifurcation value is not OS-readable. For a PASSIVE carrier, #NVMe endpoints == bifurcation proof:" -ForegroundColor DarkGray
Write-Host "  populate N M.2 slots -> expect N NVMe endpoints at x4 each. Shortfall => set Slot 6 = x4/x4/x4/x4 in BIOS." -ForegroundColor DarkGray
