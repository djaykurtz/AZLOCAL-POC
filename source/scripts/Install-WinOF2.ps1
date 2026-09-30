<#
.SYNOPSIS
  Install the NVIDIA/Mellanox WinOF-2 driver on Azure Local nodes over WinRM,
  replacing the inbox Microsoft driver on the ConnectX-5 ports.

.DESCRIPTION
  Copies the WinOF-2 installer from this DevBox to each node over the existing
  WinRM/PSSession channel (no SMB share or node internet access needed), verifies
  its SHA256 first, installs it silently, then re-verifies the NIC state.

  Package (confirmed from NVIDIA WinOF-2 Download Center 2026-07-13):
    File   : MLNX_WinOF2-26_4_50010_All_x64.exe   (v26.4.50010, WS 2016-2025 x64)
    Size   : 339 MB
    SHA256 : 0d89586419c6c253b0c3636a4220bcbf1d3e5c63cd4bb801f91905d2e7a093d5
    MD5    : ac58c9e2c74eb6097356cde45e80055e

  WHY: MS Learn host-network-requirements documents inbox drivers
  (DriverProvider=Microsoft) as UNSUPPORTED for Azure Local deployment. This swaps
  the passing-but-inbox driver for the supported WinOF-2 before the deploy wizard.

.PARAMETER Nodes
  Node numbers to install on, e.g. 01,02,04,06.

.PARAMETER InstallerPath
  Path to the WinOF-2 .exe on this DevBox. Default .\drivers\MLNX_WinOF2-26_4_50010_All_x64.exe

.PARAMETER Execute
  Actually copy + install. Without it, DRY-RUN: verify the local file's SHA256,
  confirm reachability, and show what WOULD be pushed. Installs nothing.

.PARAMETER ExpectedSha256
  Override the pinned SHA256 if a newer package is used.

.EXAMPLE
  .\scripts\Install-WinOF2.ps1 -Nodes 01,02,04,06                # dry run (verify + plan)
  .\scripts\Install-WinOF2.ps1 -Nodes 01,02,04,06 -Execute       # copy + install + verify
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @('01','02','04','06'),
  [string]   $InstallerPath = (Join-Path $PSScriptRoot '..\drivers\MLNX_WinOF2-26_4_50010_All_x64.exe'),
  [string]   $ExpectedSha256 = '0d89586419c6c253b0c3636a4220bcbf1d3e5c63cd4bb801f91905d2e7a093d5',
  [switch]   $Execute
)
$ErrorActionPreference = 'Stop'

# --- 0) Verify the local installer exists and matches the pinned SHA256 ---
if (-not (Test-Path $InstallerPath)) {
  Write-Host "Installer NOT found: $InstallerPath" -ForegroundColor Red
  Write-Host "Download MLNX_WinOF2-26_4_50010_All_x64.exe from NVIDIA and place it there." -ForegroundColor Yellow
  return
}
$fileName = Split-Path $InstallerPath -Leaf
Write-Host "Verifying SHA256 of $fileName ..." -ForegroundColor Cyan
$actual = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $ExpectedSha256.ToLower()) {
  Write-Host "  SHA256 MISMATCH!" -ForegroundColor Red
  Write-Host "  expected: $ExpectedSha256" -ForegroundColor Red
  Write-Host "  actual:   $actual" -ForegroundColor Red
  Write-Host "  Refusing to push a file that doesn't match. Re-download or pass -ExpectedSha256." -ForegroundColor Red
  return
}
Write-Host "  SHA256 OK." -ForegroundColor Green

$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\azloc-local-admin.cred" -Raw).Trim())

foreach ($n in $Nodes) {
  $nn = '{0:00}' -f [int]$n
  $short = "azl-node-$nn"; $fqdn = "$short.lab.example.com"
  Write-Host "`n===== $short  (mode: $(if($Execute){'EXECUTE'}else{'DRY-RUN'})) =====" -ForegroundColor Cyan
  $c = [pscredential]::new("$short\Administrator", $pw)
  $sopt = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 900000
  try { $s = New-PSSession -ComputerName $fqdn -Credential $c -Authentication Negotiate -SessionOption $sopt -ErrorAction Stop }
  catch { Write-Host "  UNREACHABLE: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Red; continue }

  try {
    # current driver provider before
    $before = Invoke-Command -Session $s -ScriptBlock {
      (Get-NetAdapter | Where-Object { $_.Name -match 'Port3|Port4' -and $_.Status -eq 'Up' } |
        Select-Object -First 1).DriverProvider
    }
    Write-Host "  Current ConnectX driver provider: $before"

    if (-not $Execute) {
      Write-Host "  DRY-RUN: would copy $fileName and install silently, then re-verify." -ForegroundColor Magenta
      continue
    }

    # 1) copy installer over the WinRM session
    $dest = "C:\Windows\Temp\$fileName"
    Write-Host "  Copying installer to $dest ..."
    Copy-Item -Path $InstallerPath -Destination $dest -ToSession $s -Force

    # 2) verify hash ON the node, then install silently
    $result = Invoke-Command -Session $s -ArgumentList $dest, $ExpectedSha256 -ScriptBlock {
      param($exe, $sha)
      $ErrorActionPreference = 'Continue'
      $h = (Get-FileHash -Path $exe -Algorithm SHA256).Hash.ToLower()
      if ($h -ne $sha.ToLower()) { return [pscustomobject]@{ Stage='hash'; Ok=$false; Detail="node hash $h != $sha" } }
      # WinOF-2 self-extracting InstallShield exe: silent install, no reboot.
      # Must be ONE argument string so the /v"..." embedded quotes survive; splitting
      # into array elements mangles the quoting and yields exit 87 (invalid parameter).
      $p = Start-Process -FilePath $exe -ArgumentList '/S /v"/qn /norestart"' -Wait -PassThru
      [pscustomobject]@{ Stage='install'; Ok=($p.ExitCode -in 0,3010); ExitCode=$p.ExitCode }
    }
    if (-not $result.Ok) { Write-Host "  INSTALL ISSUE: $($result | ConvertTo-Json -Compress)" -ForegroundColor Red }
    else { Write-Host "  Installed (exit $($result.ExitCode)). Settling..." -ForegroundColor Green; Start-Sleep -Seconds 20 }

    # 3) re-verify driver provider flipped off inbox
    $after = Invoke-Command -Session $s -ScriptBlock {
      Get-NetAdapter | Where-Object { $_.Name -match 'Port3|Port4' } |
        Select-Object Name, Status, LinkSpeed, DriverProvider, DriverVersion |
        Format-Table -Auto | Out-String
    }
    Write-Host $after
    Write-Host "  (expect DriverProvider != 'Microsoft'; ports Up @ 100 Gbps)" -ForegroundColor Yellow
  }
  finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
}
