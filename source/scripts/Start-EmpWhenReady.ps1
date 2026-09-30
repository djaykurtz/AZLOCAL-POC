<#
.SYNOPSIS
  Watch all four Azure Local nodes during the AzureEdgeTelemetryAndDiagnostics
  reinstall and start the AzureEMP service the moment it appears stopped.

.DESCRIPTION
  The extension "enable" phase only POLLS for AzureEMP to be running - it never starts
  it. AzureEMP is installed as demand-start (Manual) and nothing starts it, so enable
  loops until timeout. This watcher repeatedly checks each node; when the AzureEMP
  service exists and is not Running, it sets it to Automatic and starts it. Once the
  EMP-launched MonAgentHost comes up, the extension enable detects success and completes.

  Non-destructive: only starts a service that is designed to run and set its start type.

.PARAMETER Nodes
  Short node numbers. Default 01,02,04,06.

.PARAMETER Iterations
  Poll cycles. Default 20.

.PARAMETER IntervalSeconds
  Seconds between cycles. Default 20.
#>
[CmdletBinding()]
param(
    [string[]]$Nodes = @('01','02','04','06'),
    [int]$Iterations = 20,
    [int]$IntervalSeconds = 20
)

$ErrorActionPreference = 'Stop'
$credFile = Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred'
if (-not (Test-Path $credFile)) { throw "Local admin cred not found: $credFile" }
$pw = ConvertTo-SecureString ((Get-Content $credFile -Raw).Trim())

$remote = {
    $svc = Get-Service -Name AzureEMP -ErrorAction SilentlyContinue
    if (-not $svc) { return 'ABSENT' }
    if ($svc.Status -eq 'Running') { return 'RUNNING' }
    # Present but not running: make it Automatic and start it.
    try {
        Set-Service -Name AzureEMP -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name AzureEMP -ErrorAction Stop
        return 'STARTED'
    } catch {
        return "START_FAILED: $($_.Exception.Message)"
    }
}

$done = @{}
for ($i = 1; $i -le $Iterations; $i++) {
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line = "[$stamp] "
    foreach ($n in $Nodes) {
        if ($done[$n] -eq $true) { $line += "$n=RUNNING  "; continue }
        $short = "azl-node-$n"; $fqdn = "$short.lab.example.com"
        $cred  = [pscredential]::new("$short\Administrator", $pw)
        $sopt  = New-PSSessionOption -OpenTimeout 8000 -OperationTimeout 60000
        $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $sopt -ErrorAction SilentlyContinue
        if (-not $s) { $line += "$n=UNREACH  "; continue }
        $r = Invoke-Command -Session $s -ScriptBlock $remote
        Remove-PSSession $s
        if ($r -eq 'RUNNING' -or $r -eq 'STARTED') { $done[$n] = $true }
        $line += "$n=$r  "
    }
    Write-Host $line
    $line | Add-Content (Join-Path $PSScriptRoot '..\out\_emp-watch.txt')
    if (($Nodes | Where-Object { $done[$_] -ne $true }).Count -eq 0) {
        Write-Host "All nodes: AzureEMP running." -ForegroundColor Green
        break
    }
    if ($i -lt $Iterations) { Start-Sleep -Seconds $IntervalSeconds }
}
