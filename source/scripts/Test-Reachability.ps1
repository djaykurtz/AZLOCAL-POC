<#
.SYNOPSIS
    Tests reachability to a curated set of endpoints from BOTH the DevBox
    and one or more lab nodes, then writes a reachability matrix to out\.

.DESCRIPTION
    Produces a single CSV + a human-readable .md table showing
    "where can what reach what", which is the foundation for any
    firewall/policy conversation we have later.

    Each endpoint is probed by:
      - DNS resolution (Resolve-DnsName)
      - TCP-443 reachability (Test-NetConnection)
      - HTTPS GET status (Invoke-WebRequest -Method Get, 10s timeout)

    HEAD is deliberately avoided because several Azure endpoints (ARM
    notably) reject HEAD with a misleading timeout/4xx.

.PARAMETER NodeFqdns
    One or more node FQDNs to probe FROM. Default: all 6.

.PARAMETER SkipDevBox
    Skip DevBox probes (just hit the nodes).

.EXAMPLE
    .\scripts\Test-Reachability.ps1 -NodeFqdns azl-node-01.lab.example.com

.EXAMPLE
    .\scripts\Test-Reachability.ps1   # all 6 nodes + devbox
#>
[CmdletBinding()]
param(
    [string[]] $NodeFqdns = (1..6 | ForEach-Object { 'azl-node-{0:D2}.lab.example.com' -f $_ }),
    [switch]   $SkipDevBox
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$outDir   = Join-Path $repoRoot 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

# Curated endpoint set: representative of every Azure Local deploy path,
# plus a few internal-only and Internet baselines. Keep this list short
# (~15) to make the matrix readable.
$endpoints = @(
    # Arc bootstrap path
    @{ Name = 'Arc HIS discovery';           Url = 'https://gbl.his.arc.azure.com/discovery';                         Tag = 'arc'  },
    @{ Name = 'Arc agent download';          Url = 'https://aka.ms/azcmagent-windows';                                 Tag = 'arc'  },
    # Azure control plane
    @{ Name = 'Azure ARM';                   Url = 'https://management.azure.com/';                                    Tag = 'azure'},
    @{ Name = 'AAD login';                   Url = 'https://login.microsoftonline.com/';                               Tag = 'azure'},
    @{ Name = 'Azure portal';                Url = 'https://portal.azure.com/';                                        Tag = 'azure'},
    # HCI/Container/AKS workload pull
    @{ Name = 'MS Container Registry';       Url = 'https://mcr.microsoft.com/v2/';                                    Tag = 'images'},
    @{ Name = 'HCI ARB images';              Url = 'https://ecpacr.azurecr.io/';                                       Tag = 'images'},
    @{ Name = 'PSGallery';                   Url = 'https://www.powershellgallery.com/';                               Tag = 'pkg'  },
    # Telemetry/observability
    @{ Name = 'Metrics ingest';              Url = 'https://global.metrics.azure.com/';                                Tag = 'telem'},
    # Generic Internet baseline
    @{ Name = 'Internet baseline (1.1.1.1)'; Url = 'https://1.1.1.1/';                                                 Tag = 'baseline'},
    # Corp/internal baselines (should ONLY succeed from corp VPN / lab net)
    @{ Name = 'Corp DNS resolver';           Url = 'http://10.20.50.50/';                                              Tag = 'corp' },
    @{ Name = 'Lab gateway HTTP';            Url = 'http://10.10.1.1/';                                              Tag = 'corp' }
)

function Test-EndpointSet {
    param([string]$Origin, $Endpoints)

    foreach ($e in $Endpoints) {
        $uri = [System.Uri]$e.Url
        $hostname = $uri.Host
        $port = if ($uri.Port -gt 0) { $uri.Port } else { if ($uri.Scheme -eq 'https') { 443 } else { 80 } }

        # DNS
        $dnsOk = $false; $dnsErr = ''
        try { $null = Resolve-DnsName $hostname -ErrorAction Stop -QuickTimeout; $dnsOk = $true }
        catch { $dnsErr = $_.Exception.Message.Split("`n")[0] }

        # TCP
        $tcpOk = $false; $tcpMs = $null
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($hostname, $port, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(5000, $false)) {
                $tcp.EndConnect($iar); $tcpOk = $true
            }
            $tcp.Close(); $sw.Stop(); $tcpMs = $sw.ElapsedMilliseconds
        } catch { }

        # HTTPS GET (only if scheme is https)
        $httpStatus = ''; $httpMs = $null
        if ($uri.Scheme -eq 'https') {
            try {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $r  = Invoke-WebRequest -Uri $e.Url -Method Get -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                $sw.Stop()
                $httpStatus = "$($r.StatusCode)"; $httpMs = $sw.ElapsedMilliseconds
            } catch {
                $code = ''
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $code = "$([int]$_.Exception.Response.StatusCode)"
                }
                # Many Azure endpoints answer 400/403/404 to anonymous GET — that proves reachability
                $httpStatus = if ($code) { "$code (resp)" } else { 'FAIL' }
                if ($sw.IsRunning) { $sw.Stop(); $httpMs = $sw.ElapsedMilliseconds }
            }
        }

        [pscustomobject]@{
            Origin   = $Origin
            Tag      = $e.Tag
            Name     = $e.Name
            Host     = $hostname
            DNS      = if ($dnsOk) { 'OK' } else { "FAIL: $dnsErr" }
            TCP443   = if ($tcpOk) { "OK ($tcpMs ms)" } else { 'FAIL' }
            HTTPS    = if ($httpStatus) { "$httpStatus" + $(if ($httpMs) { " ($httpMs ms)" } else { '' }) } else { 'n/a' }
        }
    }
}

$all = @()

# ----- DevBox probe -----
if (-not $SkipDevBox) {
    Write-Host "`n[*] Probing from DevBox..." -ForegroundColor Cyan
    $all += Test-EndpointSet -Origin 'devbox' -Endpoints $endpoints
}

# ----- Per-node probe via PSSession -----
$credFile = Join-Path $repoRoot '.creds\azloc-local-admin.cred'
if (-not (Test-Path $credFile)) {
    throw "CredFile not found: $credFile (run Sync-CredFromKeyVault.ps1 first)"
}
$cipher = (Get-Content $credFile -Raw).Trim()
$pw     = ConvertTo-SecureString $cipher

foreach ($fqdn in $NodeFqdns) {
    $short = ($fqdn -split '\.')[0]
    Write-Host "`n[*] Probing from $short..." -ForegroundColor Cyan
    try {
        $cred = [pscredential]::new("$short\Administrator", $pw)
        $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -ErrorAction Stop

        # Push the endpoint list + function down to the node
        $rows = Invoke-Command -Session $s -ArgumentList $endpoints, $short -ScriptBlock {
            param($Endpoints, $Origin)
            $results = @()
            foreach ($e in $Endpoints) {
                $uri  = [System.Uri]$e.Url
                $hostname = $uri.Host
                $port = if ($uri.Port -gt 0) { $uri.Port } else { if ($uri.Scheme -eq 'https') { 443 } else { 80 } }

                $dnsOk = $false; $dnsErr = ''
                try { $null = Resolve-DnsName $hostname -ErrorAction Stop -QuickTimeout; $dnsOk = $true }
                catch { $dnsErr = $_.Exception.Message.Split("`n")[0] }

                $tcpOk = $false; $tcpMs = $null
                try {
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $iar = $tcp.BeginConnect($hostname, $port, $null, $null)
                    if ($iar.AsyncWaitHandle.WaitOne(5000, $false)) { $tcp.EndConnect($iar); $tcpOk = $true }
                    $tcp.Close(); $sw.Stop(); $tcpMs = $sw.ElapsedMilliseconds
                } catch { }

                $httpStatus = ''; $httpMs = $null
                if ($uri.Scheme -eq 'https') {
                    try {
                        $sw = [Diagnostics.Stopwatch]::StartNew()
                        $r  = Invoke-WebRequest -Uri $e.Url -Method Get -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        $sw.Stop(); $httpStatus = "$($r.StatusCode)"; $httpMs = $sw.ElapsedMilliseconds
                    } catch {
                        $code = ''
                        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                            $code = "$([int]$_.Exception.Response.StatusCode)"
                        }
                        $httpStatus = if ($code) { "$code (resp)" } else { 'FAIL' }
                        if ($sw.IsRunning) { $sw.Stop(); $httpMs = $sw.ElapsedMilliseconds }
                    }
                }

                $results += [pscustomobject]@{
                    Origin = $Origin
                    Tag    = $e.Tag
                    Name   = $e.Name
                    Host   = $hostname
                    DNS    = if ($dnsOk) { 'OK' } else { "FAIL: $dnsErr" }
                    TCP443 = if ($tcpOk) { "OK ($tcpMs ms)" } else { 'FAIL' }
                    HTTPS  = if ($httpStatus) { "$httpStatus" + $(if ($httpMs) { " ($httpMs ms)" } else { '' }) } else { 'n/a' }
                }
            }
            $results
        }
        $all += $rows
        Remove-PSSession $s
    } catch {
        Write-Host "    FAIL: $($_.Exception.Message)" -ForegroundColor Red
        $all += [pscustomobject]@{
            Origin = $short; Tag = 'meta'; Name = 'PSSession'; Host = $fqdn
            DNS = ''; TCP443 = ''; HTTPS = "FAIL: $($_.Exception.Message.Split([char]10)[0])"
        }
    }
}

# ----- Write outputs -----
$csvPath = Join-Path $outDir "_reachability-$ts.csv"
$mdPath  = Join-Path $outDir "_reachability-$ts.md"

$all | Export-Csv -NoTypeInformation -Path $csvPath

# Markdown matrix pivoted by endpoint x origin (HTTPS column only, short)
$origins   = $all.Origin   | Select-Object -Unique
$endpoints2 = $all | Group-Object Name | ForEach-Object { $_.Name }

$md = @()
$md += "# Reachability matrix ($ts)"
$md += ""
$md += "Detail CSV: ``out/_reachability-$ts.csv``"
$md += ""
$md += "## HTTPS GET (status / error)"
$md += ""
$header = "| Endpoint | " + ($origins -join ' | ') + " |"
$sep    = "|" + (("---|") * ($origins.Count + 1))
$md += $header
$md += $sep
foreach ($ep in $endpoints2) {
    $row = "| $ep |"
    foreach ($o in $origins) {
        $cell = ($all | Where-Object { $_.Name -eq $ep -and $_.Origin -eq $o }).HTTPS
        if (-not $cell) { $cell = '' }
        $row += " $cell |"
    }
    $md += $row
}
$md -join "`n" | Set-Content $mdPath

Write-Host "`nMatrix written:" -ForegroundColor Cyan
Write-Host "  CSV: $csvPath"
Write-Host "  MD:  $mdPath"
Write-Host "`nQuick view:"
$all | Select-Object Origin, Name, DNS, TCP443, HTTPS | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
