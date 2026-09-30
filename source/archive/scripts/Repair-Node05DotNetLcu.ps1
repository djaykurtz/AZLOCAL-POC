<#
.SYNOPSIS
    Last-resort remote fix for node05: source the recipe's .NET LCU
    (Windows11.0-KB5082417-x64-NDP481.msu == DotNetRollup 9333.2) from a stock
    freshly-imaged node, install it on node05 with the SoftwareDistribution
    "flush" trick so the standalone installer accepts the older package, then
    remove the newer 9335.3 so KB5082417 surfaces and the OS image recipe passes.

.DESCRIPTION
    Background (see repo memory): node05 was over-stripped of its .NET rollup
    chain and now has only 9335.3 (KB5094137) installed, no 9333.2 (KB5082417)
    underneath, and KB5082417 is NOT in the public catalog (it's baked into the
    Azure Local composed image). The only remaining remote path is to copy the
    loose MSU off a stock node that still has it.

    Steps:
      1. SEARCH -SourceNode for Windows11.0-KB5082417-x64-NDP481.msu (and any
         *5082417*/*NDP481* .msu). Abort cleanly if not found.
      2. Copy the MSU DevBox-side, then push to -TargetNode C:\Windows\Temp.
      3. On target: stop wuauserv/cryptSvc/bits, rename SoftwareDistribution
         (clears the "newer present" staging DB so the standalone installer lets
         the older KB install), restart services.
      4. Add-WindowsPackage the MSU offline (no WU scan). Reboot, wait.
      5. Remove the newer DotNetRollup_481 (9335.3) so 9333.2/KB5082417 becomes
         active. Reboot, wait.
      6. Run the real recipe validation; report pass/fail.

    SAFE: read-only on the source node. All writes are on the target. If the MSU
    is not found on the source, nothing is changed anywhere.

.PARAMETER SourceNode
    FQDN of a stock/freshly-imaged node likely to still hold the loose MSU
    (e.g. azl-node-02.lab.example.com).

.PARAMETER TargetNode
    FQDN of the node to repair. Default azl-node-05.lab.example.com.

.PARAMETER CredFile
    DPAPI-encrypted cred file. Default matches repo convention.

.PARAMETER Username
    Local user. Default Administrator.

.PARAMETER RebootWaitMinutes
    Minutes to wait for a node to return after reboot. Default 20.

.PARAMETER WhatIfOnly
    Only perform the search on -SourceNode and report whether the MSU exists;
    make no changes.

.EXAMPLE
    # Check first (no changes)
    .\scripts\Repair-Node05DotNetLcu.ps1 -SourceNode azl-node-02.lab.example.com -WhatIfOnly

.EXAMPLE
    .\scripts\Repair-Node05DotNetLcu.ps1 -SourceNode azl-node-02.lab.example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SourceNode,

    [string] $TargetNode = 'azl-node-05.lab.example.com',
    [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
    [string] $Username = 'Administrator',
    [int]    $RebootWaitMinutes = 20,
    [switch] $WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$mediaDir = Join-Path $repoRoot 'media'
if (-not (Test-Path $mediaDir)) { New-Item -ItemType Directory -Path $mediaDir | Out-Null }

function Write-Step($m) { Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-OK($m)   { Write-Host "    OK: $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Err2($m) { Write-Host "    FAIL: $m" -ForegroundColor Red }

if (-not $CredFile -or -not (Test-Path $CredFile)) { throw "CredFile not found: $CredFile" }
$pw = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
function Get-NodeCred([string]$fqdn) { $s=($fqdn -split '\.')[0]; [pscredential]::new("$s\$Username",$pw) }
function New-Sess([string]$fqdn,[int]$op=300000) {
    $cred=Get-NodeCred $fqdn; $opt=New-PSSessionOption -OpenTimeout 10000 -OperationTimeout $op
    $last=$null; for($i=0;$i -lt 10;$i++){ try{ return New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $opt -ErrorAction Stop }catch{ $last=$_; Start-Sleep -Seconds 20 } }; throw $last
}
function Wait-NodeBack([string]$fqdn) {
    $cred=Get-NodeCred $fqdn; Start-Sleep -Seconds 120; $good=0; $dl=(Get-Date).AddMinutes($RebootWaitMinutes)
    while((Get-Date) -lt $dl){ try{ $o=New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 60000; $t=New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $o -ErrorAction Stop; Remove-PSSession $t; $good++; if($good -ge 2){Start-Sleep -Seconds 15; return $true}; Start-Sleep -Seconds 30 }catch{ $good=0; Start-Sleep -Seconds 30 } }; return $false
}

# ---------------------------------------------------------------------------
# Step 1: find the MSU on the source node
# ---------------------------------------------------------------------------
Write-Step "Searching $SourceNode for the KB5082417 / NDP481 MSU"
$src = New-Sess $SourceNode 600000
try {
    $found = Invoke-Command -Session $src -ScriptBlock {
        $hits = Get-ChildItem 'C:\' -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '5082417' -and $_.Extension -eq '.msu' } |
                Select-Object -First 5 FullName, Length
        if (-not $hits) {
            # broaden: any NDP481 msu whose package version is 9333.2
            $hits = Get-ChildItem 'C:\' -Recurse -File -Filter '*NDP481*.msu' -ErrorAction SilentlyContinue |
                    Select-Object -First 10 FullName, Length
        }
        $hits | ForEach-Object { [pscustomobject]@{ Path=$_.FullName; MB=[math]::Round($_.Length/1MB,1) } }
    }
} finally { }

if (-not $found) {
    Write-Err2 "No KB5082417/NDP481 .msu found on $SourceNode. Node05 cannot be repaired remotely; reimage required."
    Remove-PSSession $src -ErrorAction SilentlyContinue
    return
}
Write-OK "Candidate MSU(s) on ${SourceNode}:"
$found | ForEach-Object { Write-Host "      $($_.Path) ($($_.MB) MB)" }
$srcMsu = ($found | Select-Object -First 1).Path
$msuName = Split-Path $srcMsu -Leaf

if ($WhatIfOnly) {
    Write-Warn2 "WhatIf: found MSU. Re-run without -WhatIfOnly to copy + install on $TargetNode."
    Remove-PSSession $src -ErrorAction SilentlyContinue
    return
}

# ---------------------------------------------------------------------------
# Step 2: copy MSU source -> DevBox -> target
# ---------------------------------------------------------------------------
Write-Step "Copying $msuName off $SourceNode to DevBox"
$localMsu = Join-Path $mediaDir $msuName
Copy-Item -FromSession $src -Path $srcMsu -Destination $localMsu -Force
Remove-PSSession $src -ErrorAction SilentlyContinue
Write-OK "Local copy: $localMsu ($([math]::Round((Get-Item $localMsu).Length/1MB,1)) MB)"

Write-Step "Pushing MSU to $TargetNode"
$tgt = New-Sess $TargetNode 600000
$remoteMsu = "C:\Windows\Temp\$msuName"
Copy-Item -ToSession $tgt -Path $localMsu -Destination $remoteMsu -Force
Write-OK "Staged on target: $remoteMsu"

# ---------------------------------------------------------------------------
# Step 3 + 4: flush SoftwareDistribution, Add-WindowsPackage
# ---------------------------------------------------------------------------
Write-Step "Flushing SoftwareDistribution + installing $msuName offline"
$install = Invoke-Command -Session $tgt -ScriptBlock {
    param($remoteMsu)
    foreach ($svc in 'wuauserv','cryptSvc','bits') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
    $sd = 'C:\Windows\SoftwareDistribution'
    $bak = "$sd.bak-$([datetime]::Now.ToString('yyyyMMddHHmmss'))"
    if (Test-Path $sd) { try { Rename-Item -Path $sd -NewName (Split-Path $bak -Leaf) -ErrorAction Stop } catch { } }
    foreach ($svc in 'wuauserv','cryptSvc','bits') { Start-Service -Name $svc -ErrorAction SilentlyContinue }
    $r = Add-WindowsPackage -Online -PackagePath $remoteMsu -NoRestart -ErrorAction Stop
    [pscustomobject]@{ RestartNeeded = [bool]$r.RestartNeeded }
} -ArgumentList $remoteMsu
Write-OK "MSU installed. RestartNeeded=$($install.RestartNeeded)"
Remove-PSSession $tgt -ErrorAction SilentlyContinue

Write-Step "Rebooting $TargetNode (finalize KB5082417 install)"
$tcred = Get-NodeCred $TargetNode
try { Restart-Computer -ComputerName $TargetNode -Credential $tcred -Force -ErrorAction Stop } catch { }
if (-not (Wait-NodeBack $TargetNode)) { Write-Err2 "$TargetNode did not return; investigate."; return }
Write-OK "$TargetNode back online."

# ---------------------------------------------------------------------------
# Step 5: remove the newer 9335.3 so 9333.2/KB5082417 surfaces
# ---------------------------------------------------------------------------
Write-Step "Removing newer .NET rollup (9335.3) so KB5082417 becomes active"
$tgt = New-Sess $TargetNode 600000
$rm = Invoke-Command -Session $tgt -ScriptBlock {
    $newer = Get-WindowsPackage -Online | Where-Object {
        $_.PackageName -match 'DotNetRollup_481' -and "$($_.PackageState)" -eq 'Installed'
    } | Sort-Object { [version](($_.PackageName -split '~')[-1]) } -Descending
    # Only remove the newest IF an older (9333.2) is present underneath to surface
    $hasOlder = Get-WindowsPackage -Online | Where-Object {
        $_.PackageName -match 'DotNetRollup_481' -and "$($_.PackageState)" -in 'Superseded','Staged'
    }
    if ($newer -and $hasOlder) {
        $top = $newer | Select-Object -First 1
        $out = dism /online /remove-package /packagename:$($top.PackageName) /norestart 2>&1
        [pscustomobject]@{ Removed=$top.PackageName; ExitCode=$LASTEXITCODE; HadOlder=$true }
    } else {
        [pscustomobject]@{ Removed=$null; ExitCode=$null; HadOlder=[bool]$hasOlder }
    }
}
Remove-PSSession $tgt -ErrorAction SilentlyContinue
if (-not $rm.HadOlder) {
    Write-Err2 "After install, no older 9333.2 present to surface (KB5082417 may not have registered). Inspect target."
    return
}
Write-OK "Removed $($rm.Removed) (exit $($rm.ExitCode))"

Write-Step "Rebooting $TargetNode (finalize .NET rollback)"
try { Restart-Computer -ComputerName $TargetNode -Credential $tcred -Force -ErrorAction Stop } catch { }
if (-not (Wait-NodeBack $TargetNode)) { Write-Err2 "$TargetNode did not return; investigate."; return }
Write-OK "$TargetNode back online."

# ---------------------------------------------------------------------------
# Step 6: verify recipe
# ---------------------------------------------------------------------------
Write-Step "Validating OS image recipe on $TargetNode"
$tgt = New-Sess $TargetNode 300000
$res = Invoke-Command -Session $tgt -ScriptBlock {
    Import-Module AzStackHci.EnvironmentChecker -ErrorAction SilentlyContinue
    $r = @(Invoke-AzStackHciOSImageRecipeValidation -PassThru -ErrorAction SilentlyContinue 3>$null 4>$null 5>$null 6>$null)
    $fails = @($r | Where-Object { "$($_.Status)" -eq 'FAILURE' })
    [pscustomobject]@{
        Hotfixes = ((Get-HotFix | ForEach-Object { $_.HotFixID }) -join ' ')
        Total    = $r.Count
        Failures = $fails.Count
        FailNames= (($fails | ForEach-Object { $_.Name -replace 'AzStackHci_OSImageRecipeValidation_','' }) -join ', ')
    }
}
Remove-PSSession $tgt -ErrorAction SilentlyContinue
Write-Host "    Hotfixes: $($res.Hotfixes)"
if ($res.Failures -eq 0 -and $res.Total -gt 0) {
    Write-OK "RECIPE PASSES ($($res.Total) checks, 0 failures). Next: delete stale Arc resource + Onboard-ArcMachine.ps1 -NodeFqdn $TargetNode"
} else {
    Write-Err2 "Recipe still failing ($($res.Failures)/$($res.Total): $($res.FailNames)). Reimage may be required."
}
