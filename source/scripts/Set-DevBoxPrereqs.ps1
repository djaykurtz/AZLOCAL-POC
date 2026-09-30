<#
.SYNOPSIS
  One-time DevBox setup for driving Azure Local nodes over WinRM.

.DESCRIPTION
  Idempotent. Safe to re-run. Performs:
    1. Verifies the shell is elevated (required for WinRM client edits).
    2. Installs SecretManagement + SecretStore modules if missing.
    3. Registers the POC SecretStore vault if missing.
    4. Stores the shared local Administrator credential under name
       'azloc-local-admin' if not already present.
    5. Sets the WSMan TrustedHosts entry so Negotiate auth works against
       the workgroup-joined nodes (no domain trust to lean on).
    6. Ensures the WinRM service is running.

  After this script reports OK once, you never have to run it again on
  this DevBox - all subsequent runs of Invoke-PostImageAll.ps1 just work.

.PARAMETER TrustedHostsPattern
  Pattern added to WSMan client TrustedHosts. Default matches all six
  POC nodes via wildcard: azl-node-*.lab.example.com.

.PARAMETER VaultName
  Name of the SecretStore vault. Default 'POC'.

.PARAMETER SecretName
  Name of the credential secret. Default 'azloc-local-admin'.

.EXAMPLE
  # Run from an ELEVATED pwsh
  .\Set-DevBoxPrereqs.ps1

.NOTES
  Why TrustedHosts: Azure Local nodes are workgroup-joined at imaging
  time. WinRM Negotiate against a non-domain target requires either
  Kerberos (no domain trust available) or an explicit TrustedHosts
  entry. Without it Test-WSMan returns 0x8009030e.

  Why per-host cred is built in the orchestrator and not stored here:
  the SAM account format 'HOSTNAME\Administrator' is per-node, so we
  store only the shared password and rebuild PSCredential per host.
#>

[CmdletBinding()]
param(
  [string]$TrustedHostsPattern = 'azl-node-*.lab.example.com',
  [string]$VaultName           = 'POC',
  [string]$SecretName          = 'azloc-local-admin',
  [string]$CredFile            = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred')
)

$ErrorActionPreference = 'Stop'

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)       { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Skip($msg)     { Write-Host "    --  $msg" -ForegroundColor DarkGray }
function Write-Warn2($msg)    { Write-Host "    !!  $msg" -ForegroundColor Yellow }

# 1. Elevation check ---------------------------------------------------------
Write-Step '1/6' 'Verify elevation'
$elevated = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
  throw "This script must run from an ELEVATED PowerShell. Right-click pwsh -> 'Run as Administrator'."
}
Write-OK 'Running elevated.'

# 2. Modules -----------------------------------------------------------------
Write-Step '2/6' 'Ensure SecretManagement + SecretStore modules'
$needed = @('Microsoft.PowerShell.SecretManagement','Microsoft.PowerShell.SecretStore')
foreach ($m in $needed) {
  if (Get-Module -ListAvailable -Name $m) {
    Write-Skip "$m already installed."
  } else {
    Write-Host "    Installing $m ..."
    Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber
    Write-OK "$m installed."
  }
  Import-Module $m -ErrorAction Stop
}

# 3. Vault -------------------------------------------------------------------
Write-Step '3/6' "Register vault '$VaultName' if missing (fallback path only)"
if (Test-Path $CredFile) {
  Write-Skip "DPAPI cred file present ($CredFile); SecretStore vault is optional. Skipping registration."
  $vaultPresent = $false
} else {
  $vault = Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue
  if (-not $vault) {
    Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
    Write-OK "Vault '$VaultName' registered as default."
    Write-Warn2 "First Set-Secret call below will prompt you to set a vault password."
  } else {
    Write-Skip "Vault '$VaultName' already registered."
  }
  $vaultPresent = $true
}

# 4. Credential --------------------------------------------------------------
Write-Step '4/6' "Ensure shared local-Administrator credential is cached"
if (Test-Path $CredFile) {
  Write-Skip "DPAPI cred file present at $CredFile. Skipping SecretStore prompt."
  Write-Skip "To refresh from Key Vault, run: .\Sync-CredFromKeyVault.ps1 -KeyVaultName 'kv-lab-secrets' (replace with your vault)"
} elseif ($vaultPresent) {
  $existing = Get-SecretInfo -Name $SecretName -Vault $VaultName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Skip "Secret '$SecretName' already present in SecretStore."
  } else {
    Write-Warn2 "No DPAPI cred file and no SecretStore entry. Preferred path is: .\Sync-CredFromKeyVault.ps1 -KeyVaultName 'kv-lab-secrets' (replace with your vault)"
    Write-Host "    Prompting for local Administrator password (shared across all 6 nodes)..."
    $promptCred = Get-Credential -UserName 'Administrator' `
      -Message 'Enter LOCAL Administrator password used during Azure Local imaging (same on all 6 nodes)'
    Set-Secret -Name $SecretName -Vault $VaultName -Secret $promptCred
    Write-OK "Secret '$SecretName' stored."
  }
}

# 5. TrustedHosts ------------------------------------------------------------
Write-Step '5/6' "Configure WSMan TrustedHosts ('$TrustedHostsPattern')"
$current = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
$entries = if ([string]::IsNullOrWhiteSpace($current)) { @() } else { $current.Split(',') | ForEach-Object Trim }
if ($entries -contains $TrustedHostsPattern -or $entries -contains '*') {
  Write-Skip "TrustedHosts already includes '$TrustedHostsPattern' (current: '$current')."
} else {
  if ($entries.Count -eq 0) {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $TrustedHostsPattern -Force
  } else {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $TrustedHostsPattern -Concatenate -Force
  }
  Write-OK "Added. Now: '$((Get-Item WSMan:\localhost\Client\TrustedHosts).Value)'"
}

# 6. WinRM service -----------------------------------------------------------
Write-Step '6/6' 'Ensure WinRM client service is running'
$svc = Get-Service -Name WinRM -ErrorAction Stop
if ($svc.Status -ne 'Running') {
  Start-Service WinRM
  Write-OK 'WinRM started.'
} else {
  Write-Skip 'WinRM already running.'
}
if ($svc.StartType -ne 'Automatic') {
  Set-Service -Name WinRM -StartupType Automatic
  Write-OK 'WinRM StartupType set to Automatic.'
}

Write-Host "`n== DevBox prereqs OK. You can close this elevated shell. ==" -ForegroundColor Green
Write-Host "Next: from any normal pwsh, run  .\Sync-CredFromKeyVault.ps1 -KeyVaultName 'kv-lab-secrets' (replace with your vault)  then  .\Invoke-PostImageAll.ps1" -ForegroundColor Green
