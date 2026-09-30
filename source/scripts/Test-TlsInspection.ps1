<#
.SYNOPSIS
  Read-only TLS break-and-inspect detector for Azure Local egress.

.DESCRIPTION
  For each node, opens a raw TLS connection to the Azure Local required endpoints
  and reads the certificate the node actually receives. If the issuer is a real
  Microsoft/DigiCert CA the path is clean. If the issuer is a corporate/proxy CA
  (e.g. an internal enterprise CA or a Zscaler/Blue Coat/Palo Alto proxy) then
  break-and-inspect (HTTPS inspection) is happening on that path - which Azure
  Local does NOT support and which breaks Arc onboarding + deployment.

  Nothing is changed on the nodes. Pure read-only TCP/TLS probe + cert read.

.NOTES
  Azure Local firewall requirement (Microsoft Learn):
    "Azure Local ... doesn't support HTTPS inspection. Make sure that HTTPS
     inspection is disabled along the networking path."
#>
[CmdletBinding()]
param(
    [string[]] $Nodes = @('AZL-NODE-01','AZL-NODE-02','AZL-NODE-04','AZL-NODE-06'),
    [string]   $DnsSuffix = 'lab.example.com',
    [string]   $CredPath  = "$PSScriptRoot\..\.creds\azloc-local-admin.cred",
    [string[]] $Targets = @(
        'management.azure.com',
        'login.microsoftonline.com',
        'gbl.his.arc.azure.com',
        'guestnotificationservice.azure.com',
        'san-af-southcentralus-prod.azurewebsites.net',
        'mcr.microsoft.com'
    ),
    [string]   $OutDir = "$PSScriptRoot\..\out"
)

# Trusted PUBLIC ROOT CAs = genuine Azure/Microsoft/DigiCert trust anchors.
# An SSL-inspection proxy re-signs with a CORPORATE/vendor root (corporate IT, Zscaler, Blue Coat,
# Palo Alto, Netskope, etc.) which will NOT match any of these -> flagged.
$trustedRootPatterns = @(
    'DigiCert Global Root',
    'DigiCert Global Root G2',
    'DigiCert Global Root G3',
    'Baltimore CyberTrust Root',
    'Microsoft RSA Root Certificate Authority 2017',
    'Microsoft ECC Root Certificate Authority 2017',
    'Microsoft Identity Verification Root Certificate Authority 2020',
    'DigiCert Global Root CA'
)

$probe = {
    param($Cfg)
    $Targets = $Cfg.Targets
    $TrustedPatterns = $Cfg.TrustedPatterns

    function Get-CertIssuer {
        param([string]$TargetHost, [int]$Port = 443)
        $tcp = $null; $ssl = $null
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($TargetHost, $Port, $null, $null)
            if (-not $iar.AsyncWaitHandle.WaitOne(8000, $false)) {
                return [pscustomobject]@{ Target=$TargetHost; Ok=$false; Issuer=$null; Root=$null; Note='TCP timeout' }
            }
            $tcp.EndConnect($iar)
            # Accept any cert - we WANT to read whatever is presented, incl a proxy cert.
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ([System.Net.Security.RemoteCertificateValidationCallback]{ param($s,$c,$ch,$e) $true }))
            # Force TLS 1.2 - default SslProtocols on .NET Framework can negotiate TLS1.0 which Azure resets.
            $tls12 = [System.Security.Authentication.SslProtocols]::Tls12
            $ssl.AuthenticateAsClient($TargetHost, $null, $tls12, $false)
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]$ssl.RemoteCertificate
            # Build the chain to find the ROOT trust anchor (the definitive inspection tell).
            $root = $null
            try {
                $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                $chain.ChainPolicy.RevocationMode = 'NoCheck'
                [void]$chain.Build($cert)
                if ($chain.ChainElements.Count -gt 0) {
                    $root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Issuer
                }
            } catch { }
            return [pscustomobject]@{
                Target  = $TargetHost
                Ok      = $true
                Issuer  = $cert.Issuer
                Root    = $root
                Note    = $null
            }
        } catch {
            return [pscustomobject]@{ Target=$TargetHost; Ok=$false; Issuer=$null; Root=$null; Note=$_.Exception.Message }
        } finally {
            if ($ssl) { $ssl.Dispose() }
            if ($tcp) { $tcp.Close() }
        }
    }

    $rows = foreach ($t in $Targets) {
        $r = Get-CertIssuer -TargetHost $t
        $verdict = 'UNKNOWN'
        if (-not $r.Ok) {
            $verdict = 'NO-CONNECT'
        } elseif ($r.Root -and ($TrustedPatterns | Where-Object { $r.Root -match [regex]::Escape($_) })) {
            $verdict = 'CLEAN'
        } else {
            $verdict = 'INSPECTED?'
        }
        [pscustomobject]@{
            Target  = $r.Target
            Verdict = $verdict
            Issuer  = $r.Issuer
            Root    = $r.Root
            Note    = $r.Note
        }
    }
    $rows
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
if (-not (Test-Path $CredPath)) { throw "Credential file not found: $CredPath" }

# .creds\azloc-local-admin.cred = DPAPI-protected SecureString (ConvertFrom-SecureString output), matches repo convention.
$securePw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())

$all = New-Object System.Collections.Generic.List[object]

foreach ($node in $Nodes) {
    $short = ($node -split '\.')[0]
    $fqdn  = if ($node -like "*.*") { $node } else { "$short.$DnsSuffix" }
    $cred  = New-Object System.Management.Automation.PSCredential("$short\Administrator", $securePw)

    Write-Host "`n==== $fqdn ====" -ForegroundColor Cyan
    $sess = $null
    try {
        $sess = New-PSSession -ComputerName $fqdn -Credential $cred -ErrorAction Stop
        $cfg = [pscustomobject]@{ Targets = $Targets; TrustedPatterns = $trustedRootPatterns }
        $res = Invoke-Command -Session $sess -ScriptBlock $probe -ArgumentList $cfg
        foreach ($r in $res) {
            $color = switch ($r.Verdict) {
                'CLEAN'      { 'Green' }
                'INSPECTED?' { 'Red' }
                'NO-CONNECT' { 'Yellow' }
                default      { 'Gray' }
            }
            Write-Host ("  {0,-11} {1,-45} root={2}" -f $r.Verdict, $r.Target, $r.Root) -ForegroundColor $color
            $all.Add([pscustomobject]@{ Node=$fqdn; Target=$r.Target; Verdict=$r.Verdict; Issuer=$r.Issuer; Root=$r.Root; Note=$r.Note })
        }
    } catch {
        Write-Host "  NODE ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $all.Add([pscustomobject]@{ Node=$fqdn; Target='(node)'; Verdict='NODE-ERROR'; Issuer=$null; Root=$null; Note=$_.Exception.Message })
    } finally {
        if ($sess) { Remove-PSSession $sess }
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csv = Join-Path $OutDir "_tls-inspection-$stamp.csv"
$all | Export-Csv -NoTypeInformation -Path $csv
Write-Host "`nSaved: $csv" -ForegroundColor Cyan

$inspected = $all | Where-Object Verdict -eq 'INSPECTED?'
if ($inspected) {
    Write-Host "`n*** POSSIBLE TLS INSPECTION on these endpoints (issuer not a public MS/DigiCert CA): ***" -ForegroundColor Red
    $inspected | Sort-Object Target -Unique | ForEach-Object { Write-Host "  - $($_.Target)  root=$($_.Root)  issuer=$($_.Issuer)" -ForegroundColor Red }
    Write-Host "Fix: exempt these FQDNs from SSL inspection OR deploy the Azure Arc gateway." -ForegroundColor Red
} else {
    Write-Host "`nNo TLS inspection detected: every reachable endpoint presented a public Microsoft/DigiCert CA." -ForegroundColor Green
}
