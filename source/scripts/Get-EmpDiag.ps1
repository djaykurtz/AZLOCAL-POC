<#
.SYNOPSIS
  Diagnose why the AzureEMP (Azure Edge Monitoring Platform) service will not start on
  an Azure Local node. AzureEMP is the gate for the AzureEdgeTelemetryAndDiagnostics
  extension enable: it launches the Observability MonAgentHost. If AzureEMP stays
  Stopped, the extension enable loops until timeout.

.DESCRIPTION
  Read-only diagnostics over WinRM as the node local admin (DPAPI cred, SAM-formatted):
    - AzureEMP service: status, start type, binary path, dependencies, service SID.
    - Service Control Manager (System log) events for AzureEMP start failures.
    - Application log errors mentioning EMP / MonAgent / Observability.
    - Running MonAgentHost processes with their image path + command line, to tell the
      security-monitoring instance apart from the Observability one.
    - AzureEMP install/log directory contents (newest files) if present.
  Makes NO changes.

.PARAMETER Node
  Short node number(s), e.g. '01'. Default 01.
#>
[CmdletBinding()]
param([string[]]$Node = @('01'))

$ErrorActionPreference = 'Stop'
$credFile = Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred'
if (-not (Test-Path $credFile)) { throw "Local admin cred not found: $credFile" }
$pw = ConvertTo-SecureString ((Get-Content $credFile -Raw).Trim())

$remote = {
    $out = New-Object System.Collections.Generic.List[string]

    $out.Add("==== AzureEMP service ====")
    $svc = Get-CimInstance Win32_Service -Filter "Name='AzureEMP'" -ErrorAction SilentlyContinue
    if ($svc) {
        $out.Add("  State      : $($svc.State)")
        $out.Add("  StartMode  : $($svc.StartMode)")
        $out.Add("  Status     : $($svc.Status)")
        $out.Add("  ExitCode   : $($svc.ExitCode)")
        $out.Add("  PathName   : $($svc.PathName)")
        $out.Add("  StartName  : $($svc.StartName)")
    } else { $out.Add("  (AzureEMP service not found)") }

    # Try starting it once and capture the exact failure (non-destructive: it's supposed to run).
    $out.Add("")
    $out.Add("==== Attempt Start-Service AzureEMP (capture error) ====")
    try {
        Start-Service -Name AzureEMP -ErrorAction Stop
        Start-Sleep -Seconds 4
        $s = Get-Service AzureEMP
        $out.Add("  after start attempt: $($s.Status)")
    } catch {
        $out.Add("  START FAILED: $($_.Exception.Message)")
    }

    $out.Add("")
    $out.Add("==== System log: Service Control Manager for AzureEMP (last 10) ====")
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'} -MaxEvents 200 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'AzureEMP|Edge Monitoring' } |
            Select-Object -First 10 |
            ForEach-Object { $out.Add(("  {0:HH:mm:ss} [{1}] {2}" -f $_.TimeCreated, $_.Id, ($_.Message -replace '\s+',' '))) }
    } catch { $out.Add("  (could not read System log: $($_.Exception.Message))") }

    $out.Add("")
    $out.Add("==== Application log errors: EMP/MonAgent/Observability (last 12) ====")
    try {
        Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3} -MaxEvents 400 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'EMP|MonAgent|Observability|EdgeMonitoring' } |
            Select-Object -First 12 |
            ForEach-Object { $out.Add(("  {0:HH:mm:ss} [{1}/{2}] {3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, ($_.Message -replace '\s+',' ').Substring(0,[Math]::Min(240,($_.Message -replace '\s+',' ').Length)))) }
    } catch { $out.Add("  (could not read Application log: $($_.Exception.Message))") }

    $out.Add("")
    $out.Add("==== MonAgentHost processes (image path + cmdline) ====")
    try {
        Get-CimInstance Win32_Process -Filter "Name='MonAgentHost.exe'" -ErrorAction SilentlyContinue |
            ForEach-Object { $out.Add("  pid $($_.ProcessId): $($_.CommandLine)") }
    } catch { $out.Add("  (could not enumerate: $($_.Exception.Message))") }

    $out.Add("")
    $out.Add("==== EMP install/log dirs (newest 15 files) ====")
    $empRoots = @('C:\Obs_1850','C:\Program Files\AzureEMP','C:\Program Files\Microsoft Monitoring Agent','C:\WindowsAzure\Resources')
    foreach ($r in $empRoots) {
        if (Test-Path $r) {
            $out.Add("  [$r]")
            Get-ChildItem -Path $r -Recurse -File -Include *.log,*.txt,*.err -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 15 |
                ForEach-Object { $out.Add(("    {0:HH:mm:ss} {1}" -f $_.LastWriteTimeUtc, $_.FullName)) }
        }
    }
    ,$out.ToArray()
}

foreach ($n in $Node) {
    $short = "azl-node-$n"; $fqdn = "$short.lab.example.com"
    $cred  = [pscredential]::new("$short\Administrator", $pw)
    $sopt  = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 120000
    Write-Host "`n===== $short ($fqdn) =====" -ForegroundColor Cyan
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $sopt -ErrorAction SilentlyContinue
    if (-not $s) { Write-Host "$short unreachable over WinRM" -ForegroundColor Red; continue }
    $lines = Invoke-Command -Session $s -ScriptBlock $remote
    $lines | ForEach-Object { Write-Host $_ }
    $outFile = Join-Path $PSScriptRoot ("..\out\_emp-diag-$short.txt")
    $lines | Set-Content $outFile
    Remove-PSSession $s
    Write-Host "saved -> $outFile" -ForegroundColor DarkGray
}
