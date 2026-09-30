param([string]$NodeFqdn = 'azl-node-01.lab.example.com')

$ErrorActionPreference = 'Stop'
$short = ($NodeFqdn -split '\.')[0]

$cipher = (Get-Content (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred') -Raw).Trim()
$pw     = ConvertTo-SecureString $cipher
$cred   = [pscredential]::new("$short\Administrator", $pw)
$s      = New-PSSession -ComputerName $NodeFqdn -Credential $cred -Authentication Negotiate

$result = Invoke-Command -Session $s -ScriptBlock {
    $urls = @(
        'https://gbl.his.arc.azure.com/discovery',
        'https://management.azure.com/',
        'https://login.microsoftonline.com/',
        'https://mcr.microsoft.com/v2/',
        'https://www.powershellgallery.com/',
        'https://1.1.1.1/'
    )
    foreach ($u in $urls) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $r  = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $sw.Stop()
            [pscustomobject]@{ Url = $u; Status = "$($r.StatusCode)"; Ms = $sw.ElapsedMilliseconds; Err = '' }
        } catch {
            [pscustomobject]@{ Url = $u; Status = 'FAIL'; Ms = $null; Err = ($_.Exception.Message.Split("`n")[0]) }
        }
    }
}
Remove-PSSession $s

$repoOut = Join-Path $PSScriptRoot '..\out'
$outPath = Join-Path $repoOut "_smoke-$short-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
$result | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Set-Content $outPath
Get-Content $outPath
"`nSaved: $outPath"
