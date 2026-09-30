<#
.SYNOPSIS
  Save the Azure Local LCM deployment account (AZLCL-DEPLOY-ADM) password to BOTH
  a caller-selected Key Vault and a local DPAPI-encrypted file for scripted use.

.DESCRIPTION
  You type the password ONCE at a secure prompt (Read-Host -AsSecureString). It is
  never echoed, never written in plaintext to disk, and never placed on a command
  line. Two outputs are produced:

    1. Local DPAPI file (.creds\azlcl-deploy-adm.cred) - ConvertFrom-SecureString
       output, decryptable ONLY by the same Windows user on this same machine.
       Matches the existing azloc-local-admin.cred pattern; scripts load it with
       ConvertTo-SecureString (Get-Content <file> -Raw).Trim().

    2. Azure Key Vault secret (<your-key-vault> / azlcl-deploy-adm) - pushed via a
       temp file that is written without a trailing newline and shredded+deleted
       immediately, so the value never appears as a process argument.

  The .creds folder is created with inheritance broken and only the current user
  granted access.

.NOTES
  Requires az CLI logged in with Key Vault Secrets Officer (write) on the vault.
  Does NOT require elevation. Run it yourself and type the password at the prompt.
  Supply -KeyVaultName for your own authorized vault, or -SkipKeyVault for local-only use.
#>
[CmdletBinding()]
param(
  [string]$KeyVaultName,
  [string]$SecretName   = 'azlcl-deploy-adm',
  [string]$OutFile      = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azlcl-deploy-adm.cred'),
  [string]$AccountName  = 'CORP\AZLCL-DEPLOY-ADM',
  [switch]$SkipKeyVault,
  [switch]$SkipLocalFile
)
$ErrorActionPreference = 'Stop'
if (-not $SkipKeyVault -and [string]::IsNullOrWhiteSpace($KeyVaultName)) {
  throw "Specify -KeyVaultName for your authorized vault, or use -SkipKeyVault for local-only storage."
}
if ($SkipKeyVault -and $SkipLocalFile) {
  throw "Select at least one credential destination; -SkipKeyVault and -SkipLocalFile cannot both be used."
}
function Write-OK($m){ Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Step($m){ Write-Host "`n$m" -ForegroundColor Cyan }

Write-Host "Saving credential for $AccountName" -ForegroundColor Cyan

# --- Secure prompt (typed directly into this terminal; never seen elsewhere) ---
$sec1 = Read-Host -AsSecureString "Type/paste the $AccountName password"
$sec2 = Read-Host -AsSecureString "Re-enter to confirm"
# Compare without exposing plaintext beyond the compare
$b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec1)
$b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2)
try {
  $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
  $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
  if ([string]::IsNullOrEmpty($p1)) { throw "Empty password. Nothing saved." }
  if ($p1 -ne $p2) { throw "Entries did not match. Nothing saved." }
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
  Remove-Variable p2 -ErrorAction SilentlyContinue
}
Write-OK "Password captured and confirmed (length $($p1.Length))."

# --- 1. Local DPAPI file ---
if (-not $SkipLocalFile) {
  Write-Step "[1] Local DPAPI-encrypted file"
  $credDir = Split-Path -Parent $OutFile
  if (-not (Test-Path $credDir)) {
    New-Item -ItemType Directory -Path $credDir -Force | Out-Null
    # lock down: break inheritance, grant only current user
    $acl = Get-Acl $credDir
    $acl.SetAccessRuleProtection($true, $false)
    $me  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule= New-Object System.Security.AccessControl.FileSystemAccessRule($me,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $credDir -AclObject $acl
    Write-OK "Created locked .creds folder ($me only)."
  }
  ($sec1 | ConvertFrom-SecureString) | Set-Content -Path $OutFile -Encoding ASCII
  Write-OK "Wrote DPAPI ciphertext: $OutFile"
  # verify round-trip
  $check = ConvertTo-SecureString ((Get-Content $OutFile -Raw).Trim())
  $bc = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($check)
  try { $pc = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bc); if ($pc -ne $p1) { throw "Round-trip verify FAILED." } }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bc); Remove-Variable pc -ErrorAction SilentlyContinue }
  Write-OK "Round-trip decrypt verified."
}

# --- 2. Key Vault secret (via shredded temp file, no cmdline exposure) ---
if (-not $SkipKeyVault) {
  Write-Step "[2] Azure Key Vault secret  $KeyVaultName / $SecretName"
  $tmp = [IO.Path]::GetTempFileName()
  try {
    [IO.File]::WriteAllText($tmp, $p1)   # no trailing newline
    az keyvault secret set --vault-name $KeyVaultName --name $SecretName --file $tmp --encoding utf-8 --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) { throw "az keyvault secret set failed (exit $LASTEXITCODE). Check vault name + your Secrets Officer role." }
    Write-OK "Secret set: https://$KeyVaultName.vault.azure.net/secrets/$SecretName"
  } finally {
    # overwrite then delete the temp file
    try { [IO.File]::WriteAllText($tmp, ('0' * [Math]::Max(64,$p1.Length))) } catch {}
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

# scrub plaintext
Remove-Variable p1 -ErrorAction SilentlyContinue
[GC]::Collect()
$destinations = @()
if (-not $SkipKeyVault) { $destinations += 'the selected Key Vault' }
if (-not $SkipLocalFile) { $destinations += 'the local DPAPI file' }
Write-Host ("`nDone. Password saved to {0}. Plaintext scrubbed from memory." -f ($destinations -join ' and ')) -ForegroundColor Green
