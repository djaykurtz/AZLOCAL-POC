<#
.SYNOPSIS
  Diagnose Observability agent (MonAgentHost) startup on an Azure Local node:
  test the attestation + telemetry ingest endpoints it needs, and surface the agent's own
  startup log. This targets the failure where the AzureEdgeTelemetryAndDiagnostics
  enable times out with "MonAgentHost process is not running" even though AzureEMP runs.

.DESCRIPTION
  Read-only over WinRM as node local admin. For each endpoint: DNS resolve + TCP 443.
  Also finds and tails the EMP/MonAgentHost logs under the Obs working dirs / GMACache.
  Makes no changes.

.PARAMETER Node
  Short node number(s). Default 04.
#>
[CmdletBinding()]
param([string[]]$Node = @('04'))

$ErrorActionPreference = 'Stop'
$credFile = Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred'
if (-not (Test-Path $credFile)) { throw "Local admin cred not found: $credFile" }
$pw = ConvertTo-SecureString ((Get-Content $credFile -Raw).Trim())

$remote = {
    $out = New-Object System.Collections.Generic.List[string]

    # Endpoints the Observability / monitoring agent needs.
    $endpoints = @(
        'microsoftaik.azure.net',                         # AIK / device attestation (seen failing)
        'gcs.prod.monitoring.core.windows.net',           # monitoring config service (GCS)
        'global.prod.microsoftmetrics.com',               # metrics ingest
        'login.microsoftonline.com',                      # AAD token
        'login.windows.net'                               # AAD token (legacy)
    )
    $out.Add("==== Endpoint reachability (DNS + TCP 443) ====")
    foreach ($e in $endpoints) {
        $dns = $null; $tcp = $null
        try { $dns = (Resolve-DnsName -Name $e -Type A -ErrorAction Stop | Where-Object {$_.IPAddress} | Select-Object -First 1).IPAddress } catch { $dns = "DNS-FAIL: $($_.Exception.Message)" }
        try { $tcp = (Test-NetConnection -ComputerName $e -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { $tcp = "ERR" }
        $out.Add(("  {0,-45} dns={1,-18} tcp443={2}" -f $e, $dns, $tcp))
    }

    $out.Add("")
    $out.Add("==== MonAgentHost / EMP processes ====")
    Get-CimInstance Win32_Process -Filter "Name='MonAgentHost.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { $out.Add("  MonAgentHost pid $($_.ProcessId): $($_.CommandLine)") }
    $emp = Get-Service AzureEMP -ErrorAction SilentlyContinue
    $out.Add("  AzureEMP service: $(if($emp){$emp.Status}else{'not-installed'})")

    $out.Add("")
    $out.Add("==== Newest MonAgent / EMP logs (tail) ====")
    $roots = @('C:\GMACache','C:\Obs_1923','C:\Obs_1850','C:\WindowsAzure\Resources')
    $logs = foreach ($r in $roots) {
        if (Test-Path $r) {
            Get-ChildItem -Path $r -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'MonAgent|Elm|EdgeMonitoring|Emp' -and $_.Extension -in '.log','.txt' }
        }
    }
    foreach ($f in ($logs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 6)) {
        $out.Add("")
        $out.Add(">>> $($f.FullName) [$($f.LastWriteTimeUtc.ToString('HH:mm:ss')) UTC]")
        try { Get-Content -LiteralPath $f.FullName -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { $out.Add("    $_") } } catch {}
    }
    ,$out.ToArray()
}

foreach ($n in $Node) {
    $short = "azl-node-$n"; $fqdn = "$short.lab.example.com"
    $cred  = [pscredential]::new("$short\Administrator", $pw)
    $sopt  = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 120000
    Write-Host "`n===== $short ($fqdn) =====" -ForegroundColor Cyan
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $sopt -ErrorAction SilentlyContinue
    if (-not $s) { Write-Host "$short unreachable" -ForegroundColor Red; continue }
    $lines = Invoke-Command -Session $s -ScriptBlock $remote
    $lines | ForEach-Object { Write-Host $_ }
    $lines | Set-Content (Join-Path $PSScriptRoot ("..\out\_obs-conn-$short.txt"))
    Remove-PSSession $s
}
