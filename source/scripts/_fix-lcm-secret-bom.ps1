# Rewrite LCM secret without UTF-8 BOM
$LcmDpapiFile = '.\.creds\sim-azlcl-deploy-adm.cred'
$LcmSam = 'AZLCL-DEPLOY-ADM'
$vault = 'azl-cluster-01-kv'
$secName = 'AZL-CLUSTER-01-AzureStackLCMUserCredential-00000000-0000-0000-0000-000000000007'

$sec = ConvertTo-SecureString ((Get-Content $LcmDpapiFile -Raw).Trim())
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try {
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $blob = "${LcmSam}:${pw}"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($blob))
    $tempFile = Join-Path $env:TEMP "kvfix-$(Get-Date -Format 'HHmmss').tmp"
    [IO.File]::WriteAllText($tempFile, $b64, [Text.Encoding]::ASCII)
    try {
        az keyvault secret set --vault-name $vault --name $secName --file $tempFile --output none
        if ($LASTEXITCODE -eq 0) { Write-Host "KV secret rewritten (ASCII, no BOM)." } else { throw "KV rewrite failed" }
    } finally {
        [IO.File]::WriteAllBytes($tempFile, (New-Object byte[] 4096))
        Remove-Item -Force $tempFile
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if ($pw)   { $pw   = 'x'*$pw.Length;   Remove-Variable pw   -ErrorAction SilentlyContinue }
    if ($blob) { $blob = 'x'*$blob.Length; Remove-Variable blob -ErrorAction SilentlyContinue }
    if ($b64)  { $b64  = 'x'*$b64.Length;  Remove-Variable b64  -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "==== Verify ===="
$s = az keyvault secret show --vault-name $vault --name $secName --output json | ConvertFrom-Json
"  value length: $($s.value.Length)"
$firstByte = [int]([Text.Encoding]::UTF8.GetBytes($s.value.Substring(0,1))[0])
"  first byte code: $firstByte  (should NOT be 239 which is BOM byte)"
"  first 40 chars: $($s.value.Substring(0,[Math]::Min(40,$s.value.Length)))"
