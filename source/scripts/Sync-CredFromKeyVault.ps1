<#
.SYNOPSIS
  Pull the shared local-Administrator password from Azure Key Vault and
  cache it locally as a DPAPI-encrypted file.

.DESCRIPTION
  The cached file uses Windows DPAPI (ConvertFrom-SecureString without a
  key), so it can only be decrypted by the same Windows user on the same
  machine that wrote it. No master password needed at runtime; no
  SecretStore vault prompts.

  Source of truth is a secret in your explicitly selected Key Vault:
    https://<your-key-vault>.vault.azure.net/secrets/az-local-poc
  Rotate there, then re-run this script.

  Idempotent. Safe to re-run any time you suspect the cached file is
  stale, or after a password rotation in KV.

.PARAMETER KeyVaultName
  Source Key Vault. Required; supply the name of a vault you are authorized to read.

.PARAMETER SecretName
  Secret name in the source vault. Default 'az-local-poc'.

.PARAMETER OutFile
  Destination DPAPI ciphertext file. Default '<repo>\.creds\azloc-local-admin.cred'.

.PARAMETER AlsoSeedSecretStore
  Also write the credential to the local SecretStore POC vault (fallback path
  for legacy callers). You will be prompted to unseal the vault.

.EXAMPLE
  .\Sync-CredFromKeyVault.ps1 -KeyVaultName 'kv-lab-secrets'  # replace with your vault

.EXAMPLE
  # Refresh after rotation; also push to the legacy SecretStore vault
  .\Sync-CredFromKeyVault.ps1 -KeyVaultName 'kv-lab-secrets' -AlsoSeedSecretStore

.NOTES
  Requires: az CLI, logged in (az login) with read access to the source vault.
  Does NOT require elevation.
  The .creds folder is created with inherited NTFS ACLs broken and only the
  current user granted Read+Write.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$KeyVaultName,
  [string]$SecretName         = 'az-local-poc',
  [string]$OutFile            = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred'),
  [switch]$AlsoSeedSecretStore,
  [string]$SecretStoreVault   = 'POC',
  [string]$SecretStoreName    = 'azloc-local-admin',
  [string]$Username           = 'Administrator'
)

$ErrorActionPreference = 'Stop'

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)       { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Skip($msg)     { Write-Host "    --  $msg" -ForegroundColor DarkGray }

# 1. az auth check -----------------------------------------------------------
Write-Step '1/4' 'Verify az CLI auth'
$acct = az account show --query '{name:name, user:user.name}' -o json 2>$null | ConvertFrom-Json
if (-not $acct) { throw "Not signed in to az. Run 'az login' and retry." }
Write-OK "$($acct.user) -> $($acct.name)"

# 2. Fetch from KV -----------------------------------------------------------
Write-Step '2/4' "Read $KeyVaultName/$SecretName"
$plain = az keyvault secret show --vault-name $KeyVaultName --name $SecretName --query value -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($plain)) {
  throw "Failed to read secret from KV. Output: $plain"
}
$secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
Write-OK "Fetched (length $($plain.Length))."
$plain = $null

# 3. Write DPAPI file --------------------------------------------------------
Write-Step '3/4' "Cache DPAPI-encrypted to $OutFile"
$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Write-OK "Created $dir"

  # Lock down folder: disable inheritance, owner only
  $acl = Get-Acl $dir
  $acl.SetAccessRuleProtection($true, $false)
  $acl.Access | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
  $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
  Set-Acl -Path $dir -AclObject $acl
  Write-OK "ACL locked to $me only"
}
($secure | ConvertFrom-SecureString) | Set-Content -Path $OutFile -Encoding ascii -NoNewline
Write-OK "Wrote ciphertext ($((Get-Item $OutFile).Length) bytes)"

# 4. Optional SecretStore mirror --------------------------------------------
Write-Step '4/4' 'SecretStore mirror'
if ($AlsoSeedSecretStore) {
  Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
  $cred = [pscredential]::new($Username, $secure)
  Set-Secret -Name $SecretStoreName -Vault $SecretStoreVault -Secret $cred
  Write-OK "Updated $SecretStoreVault/$SecretStoreName"
} else {
  Write-Skip 'Skipped (use -AlsoSeedSecretStore to also write to SecretStore vault).'
}

# Burn ------------------------------------------------------------------------
$secure.Dispose()
[GC]::Collect()

Write-Host "`n== Credential cache is current. ==" -ForegroundColor Green
Write-Host "Consumers (Invoke-PostImageAll.ps1) will pick it up automatically." -ForegroundColor Green
