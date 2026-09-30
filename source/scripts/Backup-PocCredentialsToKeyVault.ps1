<#
.SYNOPSIS
    Backs up local DPAPI credentials and the VM SSH key into azl-cluster-01-kv.

.DESCRIPTION
    The .creds DPAPI files are encrypted to ONE user on ONE machine. If this DevBox is
    reimaged they are unrecoverable. This copies them into Key Vault so a durable second
    copy exists.

    Secret values are passed to the CLI through a temporary file, never as a command-line
    argument, so nothing lands in process listings or shell history. The temp file is
    overwritten with random bytes before deletion.

    Additive only. It does not touch the two deployment-managed secrets already in the vault
    (AZL-CLUSTER-01-AzureStackLCMUserCredential and AZL-CLUSTER-01-LocalAdminCredential).

    Requires an active Key Vault Secrets Officer role. Run scripts\Invoke-PocPimElevation.ps1 first.
#>
[CmdletBinding()]
param(
    [string]$VaultName = 'azl-cluster-01-kv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$credDir = Join-Path $repoRoot '.creds'

# secret name -> source file plus the metadata that makes the secret self-describing later.
$items = @(
    @{ Secret = 'poc-cred-sim-domain-admin'; File = 'sim-example-internal-admin.cred'; Kind = 'dpapi'
       Tags = @{ domain = 'sim.example.internal'; user = 'labadmin'; status = 'working'; purpose = 'node-winrm-admin' } }

    @{ Secret = 'poc-cred-sim-lcm'; File = 'sim-azlcl-deploy-adm.cred'; Kind = 'dpapi'
       Tags = @{ domain = 'sim.example.internal'; user = 'AZLCL-DEPLOY-ADM'; status = 'active'; purpose = 'azure-local-deployment-account' } }

    @{ Secret = 'poc-cred-node-local-admin-predeploy'; File = 'azloc-local-admin.cred'; Kind = 'dpapi'
       Tags = @{ domain = 'local'; user = 'Administrator'; status = 'stale-rotated-by-deploy'; purpose = 'preserved-for-history' } }

    @{ Secret = 'poc-cred-corp-lcm-superseded'; File = 'azlcl-deploy-adm.cred'; Kind = 'dpapi'
       Tags = @{ domain = 'corp.example.com'; user = 'AZLCL-DEPLOY-ADM'; status = 'superseded-by-sim-pivot'; purpose = 'preserved-for-history' } }

    @{ Secret = 'poc-ssh-vm-key'; File = 'poc-vm-key'; Kind = 'plaintext'
       Tags = @{ domain = 'n-a'; user = 'azureuser'; status = 'working'; purpose = 'linux-vm-ssh-private-key' } }
)

Write-Host "Credential backup -> $VaultName" -ForegroundColor Cyan
Write-Host "Source: $credDir`n"

foreach ($item in $items) {
    $sourcePath = Join-Path $credDir $item.File
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        Write-Host ("  SKIP  {0,-38} source missing: {1}" -f $item.Secret, $item.File) -ForegroundColor Yellow
        continue
    }

    $tempFile = $null
    try {
        if ($item.Kind -eq 'dpapi') {
            $secure = ConvertTo-SecureString -String ((Get-Content -LiteralPath $sourcePath -Raw).Trim())
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try   { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
        else {
            $plain = Get-Content -LiteralPath $sourcePath -Raw
        }

        $tempFile = Join-Path $env:TEMP ("kvup-" + [guid]::NewGuid().ToString('N') + ".tmp")
        # -NoNewline matters: a trailing newline would corrupt the stored password.
        Set-Content -LiteralPath $tempFile -Value $plain -NoNewline -Encoding utf8

        $acl = Get-Acl -LiteralPath $tempFile
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            [Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')))
        Set-Acl -LiteralPath $tempFile -AclObject $acl

        $tagArgs = $item.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }

        $null = az keyvault secret set `
            --vault-name $VaultName `
            --name $item.Secret `
            --file $tempFile `
            --content-type $item.Kind `
            --tags @tagArgs `
            --only-show-errors 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host ("  OK    {0,-38} <- {1}" -f $item.Secret, $item.File) -ForegroundColor Green
        }
        else {
            Write-Host ("  FAIL  {0,-38} az exit {1}" -f $item.Secret, $LASTEXITCODE) -ForegroundColor Red
        }
    }
    catch {
        Write-Host ("  ERROR {0,-38} {1}" -f $item.Secret, $_.Exception.Message) -ForegroundColor Red
    }
    finally {
        if ($plain) { Clear-Variable plain -ErrorAction SilentlyContinue }
        if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
            # Overwrite before unlink so the plaintext is not simply left in free space.
            $len = (Get-Item -LiteralPath $tempFile).Length
            if ($len -gt 0) {
                $noise = New-Object byte[] $len
                [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($noise)
                [IO.File]::WriteAllBytes($tempFile, $noise)
            }
            Remove-Item -LiteralPath $tempFile -Force
        }
    }
}

Write-Host "`nVault contents now:" -ForegroundColor Cyan
az keyvault secret list --vault-name $VaultName `
    --query "sort_by([].{name:name, updated:attributes.updated}, &name)" -o table --only-show-errors
