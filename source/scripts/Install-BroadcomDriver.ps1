<#
.SYNOPSIS
  Install a Broadcom NetXtreme (BCM5720) OEM driver on Azure Local nodes over
  WinRM, replacing the inbox Microsoft driver on the Management NIC so the
  Azure Local network validator's InboxDriver check passes.

.DESCRIPTION
  Mirrors Install-WinOF2.ps1 but for the Broadcom management NIC. Handles three
  driver package shapes (auto-detected from -DriverPath):

    1. A folder containing .inf files (already extracted)         -> pnputil
    2. A .zip                                                      -> expand, pnputil
    3. A self-extracting / Dell DUP .exe                          -> run with -ExeSilentArgs
                                                                     (default Dell DUP: /s)

  For the pnputil path it copies the whole payload folder to the node and runs
  'pnputil /add-driver <each .inf> /install /subdirs', which force-installs the
  matching driver over the inbox one for PCI\VEN_14E4&DEV_165F (BCM5720).

  After install it re-reads the Management NIC and confirms DriverProvider is no
  longer 'Microsoft' / 'Windows'.

  Target device on our nodes (all 4):
    Broadcom NetXtreme Gigabit Ethernet
    PCI\VEN_14E4&DEV_165F&SUBSYS_0A6B1028   (Dell BCM5720)
    Inbox now: DriverProvider=Microsoft, b57nd60a.sys, 2007-06-07, v214.0.0.0

  Azure Local requires DriverProvider != Microsoft/Windows on NICs used by an
  intent (Management NIC is in the Compute_Management intent). Storage NICs
  (Port3/Port4) already pass via WinOF-2. Version is not checked, only provider.

.PARAMETER Nodes
  Node numbers, e.g. 01,02,04,06.

.PARAMETER DriverPath
  Path on this DevBox to the driver: a folder, a .zip, an .inf, or an .exe.
  Default .\drivers\broadcom (folder).

.PARAMETER ExeSilentArgs
  Silent args used only when DriverPath is an .exe. Dell Driver Update Packages
  (DUP) use '/s'. Some Broadcom InstallShield use '/s /v"/qn /norestart"'.

.PARAMETER ExpectedSha256
  Optional. If set, verify the file hash before pushing (recommended once known).

.PARAMETER Execute
  Actually copy + install. Without it, DRY-RUN: validate the local package,
  show current driver per node, and show what WOULD happen. Installs nothing.

.EXAMPLE
  # once you drop the extracted driver folder in .\drivers\broadcom
  .\scripts\Install-BroadcomDriver.ps1 -Nodes 01,02,04,06            # dry run
  .\scripts\Install-BroadcomDriver.ps1 -Nodes 01,02,04,06 -Execute   # do it

  # if Dell gave you a single .exe DUP:
  .\scripts\Install-BroadcomDriver.ps1 -DriverPath .\drivers\Network_Driver_XXXX.exe -Execute
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @('01','02','04','06'),
  [string]   $DriverPath = (Join-Path $PSScriptRoot '..\drivers\broadcom'),
  [string]   $ExeSilentArgs = '/s',
  [string]   $ExpectedSha256,
  [switch]   $Execute
)
$ErrorActionPreference = 'Stop'
function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $DriverPath)) {
  Say "Driver path NOT found: $DriverPath" Red
  Say "Drop the Broadcom BCM5720 driver here (folder of .inf, a .zip, or a Dell .exe)." Yellow
  return
}

$item = Get-Item $DriverPath
$mode = switch ($item.Extension.ToLower()) {
  '.exe' { 'exe' }
  '.zip' { 'zip' }
  '.inf' { 'inf' }
  default { if ($item.PSIsContainer) { 'folder' } else { 'unknown' } }
}
if ($mode -eq 'unknown') { Say "Unrecognized driver package type: $DriverPath" Red; return }
Say "Driver package: $($item.Name)  (type: $mode)" Cyan

# Optional hash check
if ($ExpectedSha256 -and -not $item.PSIsContainer) {
  $actual = (Get-FileHash -Path $DriverPath -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $ExpectedSha256.ToLower()) {
    Say "  SHA256 MISMATCH! expected $ExpectedSha256 got $actual" Red; return
  }
  Say "  SHA256 OK." Green
}

# Normalize local payload:
#  - folder/inf -> a folder we can copy wholesale (payload)
#  - zip        -> expand to a temp folder (payload)
#  - exe        -> copy the exe itself and run it on the node
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$localPayloadFolder = $null
$localExe = $null
switch ($mode) {
  'folder' { $localPayloadFolder = $item.FullName }
  'inf'    { $localPayloadFolder = $item.DirectoryName }
  'zip'    {
    $tmp = Join-Path $env:TEMP "bcm-payload-$stamp"
    Expand-Archive -Path $item.FullName -DestinationPath $tmp -Force
    $localPayloadFolder = $tmp
    Say "  Expanded zip to $tmp" DarkGray
  }
  'exe'    { $localExe = $item.FullName }
}

if ($localPayloadFolder) {
  $infs = Get-ChildItem -Path $localPayloadFolder -Recurse -Filter *.inf -ErrorAction SilentlyContinue
  if (-not $infs) { Say "  No .inf files found under $localPayloadFolder" Red; return }
  Say "  Found $($infs.Count) .inf file(s):" DarkGray
  $infs | ForEach-Object { Say "    $($_.FullName.Substring($localPayloadFolder.Length).TrimStart('\'))" DarkGray }
}

$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\azloc-local-admin.cred" -Raw).Trim())

foreach ($n in $Nodes) {
  $nn = '{0:00}' -f [int]$n
  $short = "azl-node-$nn"; $fqdn = "$short.lab.example.com"
  Say "`n===== $short  (mode: $(if($Execute){'EXECUTE'}else{'DRY-RUN'})) =====" Cyan
  $c = [pscredential]::new("$short\Administrator", $pw)
  $sopt = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 1800000
  try { $s = New-PSSession -ComputerName $fqdn -Credential $c -Authentication Negotiate -SessionOption $sopt -ErrorAction Stop }
  catch { Say "  UNREACHABLE: $($_.Exception.Message.Split([char]10)[0])" Red; continue }

  try {
    $before = Invoke-Command -Session $s -ScriptBlock {
      Get-NetAdapter -InterfaceDescription 'Broadcom*' -ErrorAction SilentlyContinue |
        Select-Object Name, InterfaceDescription, DriverProvider, DriverVersion, DriverFileName |
        Format-Table -Auto | Out-String
    }
    Say "  BEFORE (Broadcom adapters):" Yellow
    Say $before

    if (-not $Execute) {
      if ($localPayloadFolder) { Say "  DRY-RUN: would copy payload folder + pnputil /add-driver /install /subdirs" Magenta }
      else { Say "  DRY-RUN: would copy $($item.Name) and run: <exe> $ExeSilentArgs" Magenta }
      continue
    }

    if ($localPayloadFolder) {
      # Copy the whole payload folder to the node
      $destRoot = "C:\Windows\Temp\bcm-driver-$stamp"
      Say "  Copying payload folder to $destRoot ..."
      Invoke-Command -Session $s -ArgumentList $destRoot -ScriptBlock { param($d) New-Item -ItemType Directory -Path $d -Force | Out-Null }
      Copy-Item -Path (Join-Path $localPayloadFolder '*') -Destination $destRoot -ToSession $s -Recurse -Force

      $result = Invoke-Command -Session $s -ArgumentList $destRoot -ScriptBlock {
        param($root)
        $ErrorActionPreference = 'Continue'
        $infList = Get-ChildItem -Path $root -Recurse -Filter *.inf | Select-Object -ExpandProperty FullName
        $log = @()
        foreach ($inf in $infList) {
          $out = & pnputil.exe /add-driver "$inf" /install /subdirs 2>&1 | Out-String
          $log += "INF: $inf`n$out"
        }
        # Force a rescan so the new driver binds
        & pnputil.exe /scan-devices 2>&1 | Out-Null
        [pscustomobject]@{ Log = ($log -join "`n----`n") }
      }
      Say "  pnputil output:" DarkGray
      Say $result.Log DarkGray
    }
    else {
      # exe path
      $destExe = "C:\Windows\Temp\$($item.Name)"
      Say "  Copying $($item.Name) to $destExe ..."
      Copy-Item -Path $localExe -Destination $destExe -ToSession $s -Force
      $result = Invoke-Command -Session $s -ArgumentList $destExe, $ExeSilentArgs -ScriptBlock {
        param($exe,$args)
        $ErrorActionPreference = 'Continue'
        $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
        [pscustomobject]@{ ExitCode = $p.ExitCode }
      }
      Say "  exe exit code: $($result.ExitCode)  (Dell DUP: 0=ok, 2=ok-reboot)" DarkGray
    }

    Start-Sleep -Seconds 15
    $after = Invoke-Command -Session $s -ScriptBlock {
      Get-NetAdapter -InterfaceDescription 'Broadcom*' -ErrorAction SilentlyContinue |
        Select-Object Name, Status, DriverProvider, DriverVersion, DriverDate |
        Format-Table -Auto | Out-String
    }
    Say "  AFTER (Broadcom adapters):" Green
    Say $after
    Say "  (want DriverProvider != 'Microsoft'/'Windows'. Management NIC must keep its IP.)" Yellow

    # Explicitly confirm the Management NIC still has its mgmt IP
    $mgmt = Invoke-Command -Session $s -ScriptBlock {
      $a = Get-NetAdapter -Name 'Management' -ErrorAction SilentlyContinue
      if ($a) {
        $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ','
        "Management: Status=$($a.Status) Provider=$($a.DriverProvider) IP=$ip"
      } else { "Management NIC not found by name (may have re-enumerated - check names)" }
    }
    Say "  $mgmt" Cyan
  }
  finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
}

Say "`nDONE. Re-run validation with scripts/Invoke-ValidationRetry.ps1 once all 4 show a non-inbox provider." Cyan
