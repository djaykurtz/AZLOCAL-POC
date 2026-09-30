<#
.SYNOPSIS
  Tail the AzureEdgeTelemetryAndDiagnostics (Observability / MonAgentHost / AzureEMP)
  extension logs on an Azure Local node over WinRM, so we can watch a retry live.

.DESCRIPTION
  The extension enable timed out waiting on MonAgentHost + AzureEMP to start. This
  script connects to the node as the local Administrator (DPAPI cred, SAM-formatted),
  locates the extension's handler status + its own working-dir logs, and prints the
  newest lines. In -Follow mode it re-polls on an interval and prints only new lines,
  giving a live tail during a portal "Retry installation".

  Log locations covered (from the failure output + standard Arc/extension paths):
    - C:\Packages\Plugins\Microsoft.AzureStack.Observability.TelemetryAndDiagnostics\*  (handler + Status\*.status)
    - C:\ProgramData\GuestConfig\extension_logs\*Observability*Telemetry*             (Arc handler logs)
    - C:\Obs_1850                                                                       (extension working dir seen in error)
    - C:\WindowsAzure\Logs\Plugins                                                      (legacy plugin logs)

  Read-only on the node (Get-ChildItem / Get-Content only). No changes made.

.PARAMETER Node
  Short node number(s), e.g. '01'. Default 01 (the seed machine).

.PARAMETER Follow
  Keep polling and print new lines until -Iterations is reached.

.PARAMETER Iterations
  Number of poll cycles in -Follow mode. Default 40.

.PARAMETER IntervalSeconds
  Seconds between polls in -Follow mode. Default 15.

.EXAMPLE
  .\scripts\Tail-ExtensionLog.ps1                       # one snapshot of node 01
  .\scripts\Tail-ExtensionLog.ps1 -Follow               # live tail node 01 (~10 min)
#>
[CmdletBinding()]
param(
    [string[]]$Node = @('01'),
    [switch]$Follow,
    [int]$Iterations = 40,
    [int]$IntervalSeconds = 15
)

$ErrorActionPreference = 'Stop'
$credFile = Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred'
if (-not (Test-Path $credFile)) { throw "Local admin cred not found: $credFile" }
$pw = ConvertTo-SecureString ((Get-Content $credFile -Raw).Trim())

# The remote scriptblock: enumerate candidate log dirs, return files modified after $since.
$remote = {
    param($sinceUtc)
    $roots = @(
        'C:\Packages\Plugins\Microsoft.AzureStack.Observability.TelemetryAndDiagnostics',
        'C:\ProgramData\GuestConfig\extension_logs',
        'C:\Obs_1850',
        'C:\WindowsAzure\Logs\Plugins'
    )
    $since = [datetime]::Parse($sinceUtc).ToUniversalTime()

    # Snapshot of the key process/service state the extension waits on.
    $svc = foreach ($n in 'AzureStackObservability','AzureEMP','MonAgentHost') {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        "{0,-26} {1}" -f $n, ($(if ($s) { $s.Status } else { 'not-installed' }))
    }
    $proc = foreach ($p in 'MonAgentHost','AzureEMP','FleetDiagnosticsAgent','AzureEdgeCrashDumpCollection') {
        $r = Get-Process -Name $p -ErrorAction SilentlyContinue
        "{0,-30} {1}" -f $p, ($(if ($r) { 'running (pid ' + ($r.Id -join ',') + ')' } else { 'NOT running' }))
    }

    $files = foreach ($root in $roots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.log','.txt','.status','.json' -and $_.LastWriteTimeUtc -gt $since }
        }
    }

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("---- SERVICES ----")
    $svc  | ForEach-Object { $out.Add($_) }
    $out.Add("---- PROCESSES ----")
    $proc | ForEach-Object { $out.Add($_) }
    $out.Add("---- LOG FILES modified since $($since.ToString('HH:mm:ss')) UTC ----")

    foreach ($f in ($files | Sort-Object LastWriteTimeUtc)) {
        $out.Add("")
        $out.Add(">>> $($f.FullName)  [$($f.LastWriteTimeUtc.ToString('HH:mm:ss')) UTC]")
        try {
            $tail = Get-Content -LiteralPath $f.FullName -Tail 25 -ErrorAction SilentlyContinue
            $tail | ForEach-Object { $out.Add("    $_") }
        } catch { $out.Add("    (could not read: $($_.Exception.Message))") }
    }
    if (-not $files) { $out.Add("(no log files changed in this window)") }
    ,$out.ToArray()
}

foreach ($n in $Node) {
    $short = "azl-node-$n"; $fqdn = "$short.lab.example.com"
    $cred  = [pscredential]::new("$short\Administrator", $pw)
    $sopt  = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 120000
    Write-Host "`n===== $short ($fqdn) =====" -ForegroundColor Cyan
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $sopt -ErrorAction SilentlyContinue
    if (-not $s) { Write-Host "$short unreachable over WinRM" -ForegroundColor Red; continue }

    $outFile = Join-Path $PSScriptRoot ("..\out\_ext-tail-$short.txt")
    # Baseline window: look back 10 minutes on first pass so we see the failing run.
    $since = [datetime]::UtcNow.AddMinutes(-10)

    $loops = if ($Follow) { $Iterations } else { 1 }
    for ($i = 1; $i -le $loops; $i++) {
        $stamp = [datetime]::UtcNow.ToString('HH:mm:ss')
        Write-Host "--- poll $i/$loops @ $stamp UTC ---" -ForegroundColor DarkGray
        $lines = Invoke-Command -Session $s -ScriptBlock $remote -ArgumentList $since.ToString('o')
        $lines | ForEach-Object { Write-Host $_ }
        ("[$stamp UTC] poll $i") | Add-Content $outFile
        $lines | Add-Content $outFile
        # Next window starts from just before this poll so we only get new lines.
        $since = [datetime]::UtcNow.AddSeconds(-($IntervalSeconds + 5))
        if ($Follow -and $i -lt $loops) { Start-Sleep -Seconds $IntervalSeconds }
    }
    Remove-PSSession $s
    Write-Host "saved -> $outFile" -ForegroundColor DarkGray
}
