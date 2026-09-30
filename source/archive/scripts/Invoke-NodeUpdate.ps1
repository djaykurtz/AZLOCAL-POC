<#
.SYNOPSIS
    Runs Windows Updates on an Azure Local node over WinRM by replicating the
    SCONFIG update wizard's WUA logic inside a SYSTEM scheduled task.

.DESCRIPTION
    The SCONFIG "Install Updates" wizard (Microsoft.ServerCore.SConfig
    \SConfig.Update.psm1) just drives the Windows Update Agent COM API:
        $s = New-Object -Com Microsoft.Update.Session
        $s.CreateUpdateSearcher().Search("IsInstalled=0 and DeploymentAction='Installation' ...")
        $s.CreateUpdateDownloader().Download()
        $s.CreateUpdateInstaller().Install()

    That COM online scan no-ops / fails under a WinRM network-logon token
    (the WUA "second hop" limitation). The wizard works because it runs as a
    LOCAL interactive/SYSTEM context. This script reproduces the wizard's exact
    Search -> Download -> Install path but executes it as a SYSTEM scheduled task,
    which gives WUA the local token it needs. Driven remotely over the existing
    PSSession; no interactive logon required.

    Search criteria matches the wizard's "All" selection verbatim.

.PARAMETER NodeFqdn
    Target node FQDN. Default azl-node-01.lab.example.com.

.PARAMETER MaxWaitMinutes
    How long to wait for the scheduled task (scan+download+install) to finish.

.PARAMETER CredFile
    DPAPI-encrypted cred file. Default matches repo convention.

.PARAMETER Username
    Local user. Default Administrator.

.PARAMETER WhatIfOnly
    Stage and show the task that would run, without registering/starting it.

.EXAMPLE
    .\scripts\Invoke-NodeUpdate.ps1 -NodeFqdn azl-node-03.lab.example.com

.EXAMPLE
    # Update all of 3/4/5/6 sequentially
    'azl-node-03','azl-node-04','azl-node-05','azl-node-06' |
      ForEach-Object { .\scripts\Invoke-NodeUpdate.ps1 -NodeFqdn "$_.lab.example.com" }
#>
[CmdletBinding()]
param(
    [string] $NodeFqdn = 'azl-node-01.lab.example.com',
    [int]    $MaxWaitMinutes = 90,
    [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
    [string] $Username = 'Administrator',
    [switch] $WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$outDir   = Join-Path $repoRoot 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Step($msg) { Write-Host "`n[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn2($m)  { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Err2($m)   { Write-Host "    FAIL: $m" -ForegroundColor Red }

if (-not $CredFile -or -not (Test-Path $CredFile)) {
    throw "CredFile not found: $CredFile  (run Sync-CredFromKeyVault.ps1 first)"
}
$short = ($NodeFqdn -split '\.')[0]
$pw    = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
$cred  = [pscredential]::new("$short\$Username", $pw)
$sopt  = New-PSSessionOption -OpenTimeout 7000 -OperationTimeout 180000

# This is the payload that runs ON the node, AS SYSTEM, via the scheduled task.
# It mirrors SConfig.Update.psm1's "All" search + download + install verbatim.
$taskName   = 'POC-WUUpdateAll'
$remoteDir  = 'C:\Windows\Temp\POC-WU'
$payloadPath = "$remoteDir\Invoke-WUAllAsSystem.ps1"
$resultPath  = "$remoteDir\wu-result.json"
$donePath    = "$remoteDir\wu-done.flag"

$payload = @'
$ErrorActionPreference = 'Stop'
$dir = 'C:\Windows\Temp\POC-WU'
$result = [ordered]@{ Started=(Get-Date).ToString('o'); Phase='init'; MicrosoftUpdateOptIn=$false; Searched=0; Downloaded=0; Installed=@(); ResultCode=$null; RebootRequired=$null; Error=$null }
try {
    # Opt into Microsoft Update (broader than Windows Update) so .NET Framework CUs
    # like KB5082417 are offered. This mirrors SConfig's Set-SCfMicrosoftUpdateOptIn.
    # MU service GUID 7971f918-a847-4430-9279-4a52d1efe18d; flags 7 = AllowPending+Online+RegisterWithAU.
    try {
        $sm = New-Object -ComObject Microsoft.Update.ServiceManager
        $null = $sm.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
        $result.MicrosoftUpdateOptIn = $true
    } catch {
        # Already registered or transient; continue with whatever services are present.
        $result.MicrosoftUpdateOptIn = "warn: $($_.Exception.Message)"
    }

    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    # Explicitly scan the Microsoft Update service (superset of Windows Update) so .NET
    # Framework CUs (e.g. KB5082417) are returned, not just WU-only content. A freshly
    # registered MU service is not picked up by the default ServerSelection until AU
    # re-syncs, so we target it directly.
    try {
        $searcher.ServerSelection = 3   # ssOthers
        $searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
    } catch { }
    # Verbatim from SConfig.Update.psm1 "All" selection
    $criteria = "IsInstalled=0 and DeploymentAction='Installation' or IsInstalled=0 and DeploymentAction='OptionalInstallation' or IsPresent=1 and DeploymentAction='Uninstallation' or IsInstalled=1 and DeploymentAction='Installation' and RebootRequired=1 or IsInstalled=0 and DeploymentAction='Uninstallation' and RebootRequired=1"
    $result.Phase = 'search'
    $found = $searcher.Search($criteria)
    $result.Searched = $found.Updates.Count

    $toGet = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i=0; $i -lt $found.Updates.Count; $i++) {
        $u = $found.Updates.Item($i)
        # Skip preview / feature upgrades, matching wizard intent (hide feature updates)
        if ($u.Title -match 'Preview|Feature update|Upgrade to Windows') { continue }
        $null = $toGet.Add($u)
    }

    if ($toGet.Count -gt 0) {
        $result.Phase = 'download'
        $dl = $session.CreateUpdateDownloader()
        $dl.Updates = $toGet
        $null = $dl.Download()
        $result.Downloaded = ($toGet | Where-Object { $_.IsDownloaded }).Count

        $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $toGet) { if ($u.IsDownloaded) { $null = $toInstall.Add($u) } }

        if ($toInstall.Count -gt 0) {
            $result.Phase = 'install'
            $inst = $session.CreateUpdateInstaller()
            $inst.Updates = $toInstall
            $ir = $inst.Install()
            $result.ResultCode = $ir.ResultCode
            $result.RebootRequired = $ir.RebootRequired
            for ($k=0; $k -lt $toInstall.Count; $k++) {
                $result.Installed += [ordered]@{ Title=$toInstall.Item($k).Title; Code=$ir.GetUpdateResult($k).ResultCode }
            }
        }
    }
    $result.Phase = 'done'
}
catch {
    $result.Error = $_.Exception.Message
    $result.Phase = 'error'
}
finally {
    $result.Finished = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $dir 'wu-result.json') -Encoding UTF8
    'done' | Set-Content -Path (Join-Path $dir 'wu-done.flag')
}
'@

Write-Step "Connecting to $NodeFqdn"
$s = New-PSSession -ComputerName $NodeFqdn -Credential $cred -Authentication Negotiate -SessionOption $sopt -ErrorAction Stop
try {
    # Stage payload and clear prior run
    Invoke-Command -Session $s -ScriptBlock {
        param($dir, $payload, $payloadPath, $resultPath, $donePath, $taskName)
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Remove-Item $resultPath, $donePath -ErrorAction SilentlyContinue
        Set-Content -Path $payloadPath -Value $payload -Encoding UTF8 -Force
        schtasks.exe /Delete /TN $taskName /F *> $null
    } -ArgumentList $remoteDir, $payload, $payloadPath, $resultPath, $donePath, $taskName
    Write-OK "Payload staged at $payloadPath (mirrors SCONFIG wizard 'All' WUA path)"

    if ($WhatIfOnly) {
        Write-Warn2 "WhatIf: would register scheduled task '$taskName' as NT AUTHORITY\SYSTEM running:"
        Write-Host "      powershell.exe -NonInteractive -ExecutionPolicy Bypass -File $payloadPath" -ForegroundColor DarkGray
        return
    }

    Write-Step "Registering + starting SYSTEM scheduled task '$taskName'"
    $startInfo = Invoke-Command -Session $s -ScriptBlock {
        param($taskName, $payloadPath)
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$payloadPath`""
        $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 3)
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 2
        (Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo).LastTaskResult
    } -ArgumentList $taskName, $payloadPath
    Write-OK "Task started as SYSTEM (initial LastTaskResult=$startInfo)"

    # Poll for the done flag
    Write-Step "Waiting for updates (search + download + install), up to $MaxWaitMinutes min"
    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    $done = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        $poll = Invoke-Command -Session $s -ScriptBlock {
            param($donePath, $resultPath, $taskName)
            $state = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
            $flag  = Test-Path $donePath
            $partial = if (Test-Path $resultPath) { (Get-Content $resultPath -Raw) } else { $null }
            [pscustomobject]@{ TaskState=$state; Done=$flag; Result=$partial }
        } -ArgumentList $donePath, $resultPath, $taskName
        if ($poll.Done) { $done = $true; $finalJson = $poll.Result; break }
        Write-Host "    ... task=$($poll.TaskState) $((Get-Date).ToString('HH:mm:ss'))" -ForegroundColor DarkGray
    }

    if (-not $done) { throw "Update task did not complete within $MaxWaitMinutes min on $short. Check '$taskName' on the node." }

    # Persist and summarize
    $localResult = Join-Path $outDir "$short-wu-result-$ts.json"
    $finalJson | Set-Content -Path $localResult -Encoding UTF8
    $r = $finalJson | ConvertFrom-Json
    Write-OK "Update run finished: phase=$($r.Phase) searched=$($r.Searched) downloaded=$($r.Downloaded) installed=$(@($r.Installed).Count)"
    if ($r.Error) { Write-Err2 "Payload error: $($r.Error)" }
    if ($r.RebootRequired) { Write-Warn2 "Node reports RebootRequired=TRUE. Reboot before re-running Arc bootstrap." }
    Write-Host "    Result JSON: $localResult"

    # Cleanup the task (leave payload+result for audit)
    Invoke-Command -Session $s -ScriptBlock { param($t) schtasks.exe /Delete /TN $t /F *> $null } -ArgumentList $taskName
}
finally {
    if ($s) { Remove-PSSession $s -ErrorAction SilentlyContinue }
}

Write-Step "Done"
Write-OK "$short updated via SYSTEM scheduled task (SCONFIG-equivalent WUA path)."
