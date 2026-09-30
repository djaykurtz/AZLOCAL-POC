<#
.SYNOPSIS
  Read-only NVMe enumeration probe. Compares nodes to separate a dead drive from a dead path.

.DESCRIPTION
  Written for a specific question: node 03 has three data drives installed and only two appear,
  and it stayed that way after all three were replaced with new drives. Three new drives do not
  arrive dead, so the fault is in the path rather than the media.

  The distinction this probe draws:

    Controller present, Status Error, problem code 10
      A device that enumerated and then failed. This is node 01. Replacing the drive MIGHT help,
      but only if the controller itself is on the drive rather than the carrier.

    Controller absent entirely, fewer controllers than installed drives
      Nothing enumerated at all. Bifurcation, lane allocation, or a dead M.2 socket. Replacing
      drives will not help, and this is the expected signature on node 03.

  PCIe link width is reported because it is the tell for bifurcation. A x16 slot carrying a quad
  M.2 carrier needs to be split 4x4x4x4. If it is running x8 or x16 instead, only some sockets get
  lanes and the rest are silent, which looks exactly like dead drives but is a firmware setting.

  Strictly read-only. Every call is a Get.

.PARAMETER Nodes
  Nodes to probe. Defaults to the failing node and the healthy comparison.

.EXAMPLE
  .\Invoke-NvmeEnumerationProbe.ps1
  .\Invoke-NvmeEnumerationProbe.ps1 -Nodes azl-node-03.lab.example.com
#>

[CmdletBinding()]
param(
  [string[]]$Nodes = @('azl-node-01.lab.example.com', 'azl-node-03.lab.example.com', 'azl-node-02.lab.example.com'),
  [string]$CredentialPath = '.\.creds\sim-example-internal-admin.cred',
  [string]$UserName = 'sim\labadmin',
  [string]$OutputPath = '.\out'
)

$ErrorActionPreference = 'Continue'

$pw = ConvertTo-SecureString ((Get-Content $CredentialPath -Raw).Trim())
$cred = [pscredential]::new($UserName, $pw)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$outFile = Join-Path $OutputPath "_nvme-enumeration-$stamp.txt"

$L = [System.Collections.Generic.List[string]]::new()
function Say { param([string]$s = '') $L.Add($s); Write-Host $s }

Say "NVMe enumeration probe   $stamp"
Say 'Read-only. Separates a failed device from a path that never enumerated.'

$probe = {
  $ctrls = Get-PnpDevice -Class SCSIAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'NVM|NVMe' }

  $rows = foreach ($c in $ctrls) {
    # Link width and speed are only meaningful on the PCIe function, and are absent on some
    # platforms. Missing is reported as blank rather than guessed.
    $w = (Get-PnpDeviceProperty -InstanceId $c.InstanceId -KeyName 'DEVPKEY_PciDevice_CurrentLinkWidth' -ErrorAction SilentlyContinue).Data
    $s = (Get-PnpDeviceProperty -InstanceId $c.InstanceId -KeyName 'DEVPKEY_PciDevice_CurrentLinkSpeed' -ErrorAction SilentlyContinue).Data
    $loc = (Get-PnpDeviceProperty -InstanceId $c.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data
    [pscustomobject]@{
      Status   = $c.Status
      Problem  = $c.ProblemCode
      Width    = if ($w) { "x$w" } else { '' }
      Speed    = $s
      Location = $loc
    }
  }

  [pscustomobject]@{
    Controllers   = @($rows)
    ControllerNum = @($ctrls).Count
    ErrorNum      = @($ctrls | Where-Object Status -ne 'OK').Count
    Drives        = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue |
                      Select-Object Model, SerialNumber, @{n='GB';e={[math]::Round($_.Size/1GB,1)}}, InterfaceType)
    DriveNum      = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue).Count
    PhysNum       = @(Get-PhysicalDisk -ErrorAction SilentlyContinue).Count
  }
}

foreach ($n in $Nodes) {
  Say ''
  Say ('=' * 78)
  Say "NODE  $n"
  Say ('=' * 78)

  try {
    $r = Invoke-Command -ComputerName $n -Credential $cred -Authentication Negotiate -ScriptBlock $probe -ErrorAction Stop
  }
  catch {
    Say "  UNREACHABLE: $($_.Exception.Message)"
    continue
  }

  Say ("  NVMe controllers: {0}  ({1} not OK)" -f $r.ControllerNum, $r.ErrorNum)
  Say ("  Win32_DiskDrive entries: {0}   (OS disk plus Storage Space devices, not pool members)" -f $r.DriveNum)
  Say ''
  Say '  Controllers:'
  if ($r.Controllers) {
    ($r.Controllers | Format-Table Status, Problem, Width, Speed, Location -AutoSize | Out-String -Width 200) -split "`n" |
      Where-Object { $_.Trim() } | ForEach-Object { Say "    $_" }
  } else { Say '    none found' }

  Say '  Drives:'
  ($r.Drives | Format-Table Model, SerialNumber, GB, InterfaceType -AutoSize | Out-String -Width 200) -split "`n" |
    Where-Object { $_.Trim() } | ForEach-Object { Say "    $_" }

  # Interpretation, stated as a lead rather than a conclusion.
  Say '  Reading:'
  if ($r.ErrorNum -gt 0) {
    Say '    A controller enumerated and failed to start. Device or carrier fault on that path.'
    Say '    A replacement drive may or may not help, depending on which side the fault sits.'
  }
  elseif ($r.ControllerNum -lt 3) {
    Say "    Only $($r.ControllerNum) NVMe controllers enumerated with no errors reported."
    Say '    Sockets that are populated but silent point at bifurcation, lane allocation, or a'
    Say '    dead socket. Swapping drives will not change this. Check the PCIe slot split in BIOS.'
  }
  else {
    Say '    All expected controllers present and healthy on this node.'
  }
}

Say ''
Say 'Compare the healthy node against the failing one. If the healthy node shows more'
Say 'controllers at the same link width, the difference is configuration, not hardware.'

$L -join "`n" | Set-Content -Path $outFile -Encoding utf8
Write-Host ''
Write-Host "Written to $outFile" -ForegroundColor DarkGray
