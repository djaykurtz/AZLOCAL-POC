<#
.SYNOPSIS
    Repair node05's OS image recipe using a LOCALLY-downloaded KB5082417 MSU
    (obtained from the Microsoft Update Catalog) plus surfacing KB5082063.

.DESCRIPTION
    Node05 gaps vs the signed recipe (KB5082417 .NET + KB5082063 OS):
      - .NET: only 9335.3 installed, nothing older underneath -> must INSTALL the
        exact 9333.2 MSU (== KB5082417). We now HAVE that MSU from the catalog.
      - OS:   32995 installed with 32690 Superseded underneath -> removing 32995
        SURFACES 32690 (== KB5082063); no download needed.

    Sequence (Option A - remove-newer-first, then install-exact):
      Pass 1 (one reboot): remove newer .NET rollup(s) (9335.3) AND remove OS
        RollupFix 32995 (only if a Superseded/Staged OS rollup exists underneath).
      Pass 2 (one reboot): flush SoftwareDistribution, Add-WindowsPackage the
        9333.2 MSU offline (fresh, no supersession conflict).
      Validate: run the real recipe validation; report pass/fail.

    All changes are on -TargetNode. Idempotent-ish: re-running re-checks state.

.PARAMETER MsuPath
    Local path to the KB5082417 NDP481 x64 MSU. Defaults to the newest
    *kb5082417*ndp481*.msu under .\out\msu (downloaded by Get-CatalogMsu.ps1).

.PARAMETER TargetNode
    FQDN of the node to repair. Default azl-node-05.lab.example.com.

.PARAMETER CredFile / -Username / -RebootWaitMinutes
    Standard repo conventions.

.EXAMPLE
    .\scripts\Repair-Node05FromMsu.ps1
#>
[CmdletBinding()]
param(
    [string] $MsuPath,
    [string] $TargetNode = 'azl-node-05.lab.example.com',
    [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
    [string] $Username = 'Administrator',
    [int]    $RebootWaitMinutes = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

function Write-Step($m) { Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-OK($m)   { Write-Host "    OK: $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Err2($m) { Write-Host "    FAIL: $m" -ForegroundColor Red }

# Resolve MSU
if (-not $MsuPath) {
    $cand = Get-ChildItem (Join-Path $repoRoot 'out\msu') -Filter '*kb5082417*ndp481*.msu' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $cand) { throw "No KB5082417 NDP481 MSU found under out\msu. Run Get-CatalogMsu.ps1 first." }
    $MsuPath = $cand.FullName
}
if (-not (Test-Path $MsuPath)) { throw "MsuPath not found: $MsuPath" }
$msuName = Split-Path $MsuPath -Leaf
Write-OK "Using MSU: $MsuPath ($([math]::Round((Get-Item $MsuPath).Length/1MB,1)) MB)"

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
$tcred = Get-NodeCred $TargetNode

# ---------------------------------------------------------------------------
# Pre-state
# ---------------------------------------------------------------------------
Write-Step "Reading current package state on $TargetNode"
$tgt = New-Sess $TargetNode
$pre = Invoke-Command -Session $tgt -ScriptBlock {
    $pk = Get-WindowsPackage -Online | Where-Object PackageName -match 'DotNetRollup_481|RollupFix'
    [pscustomobject]@{
        Hotfixes = ((Get-HotFix | ForEach-Object { $_.HotFixID }) -join ' ')
        Net      = ($pk | Where-Object PackageName -match 'DotNetRollup_481' | ForEach-Object { "$($_.PackageName.Split('~')[-1])=$($_.PackageState)" }) -join '; '
        Os       = ($pk | Where-Object PackageName -match 'RollupFix' | ForEach-Object { "$($_.PackageName.Split('~')[-1])=$($_.PackageState)" }) -join '; '
    }
}
Remove-PSSession $tgt -ErrorAction SilentlyContinue
Write-Host "    Hotfixes: $($pre.Hotfixes)"
Write-Host "    .NET:     $($pre.Net)"
Write-Host "    OS:       $($pre.Os)"

# ---------------------------------------------------------------------------
# Pass 1: remove newer .NET rollup(s) + OS 32995 (if superseded underneath)
# ---------------------------------------------------------------------------
Write-Step "Pass 1: removing newer .NET rollup + superseding OS rollup (/norestart)"
$tgt = New-Sess $TargetNode 600000
$p1 = Invoke-Command -Session $tgt -ScriptBlock {
    $removed=@()
    # .NET: remove ALL Installed DotNetRollup_481 (we will reinstall exact 9333.2)
    $net = Get-WindowsPackage -Online | Where-Object { $_.PackageName -match 'DotNetRollup_481' -and "$($_.PackageState)" -eq 'Installed' }
    foreach($p in $net){ dism /online /remove-package /packagename:$($p.PackageName) /norestart *>$null; $removed += "net:$($p.PackageName.Split('~')[-1]) (exit $LASTEXITCODE)" }
    # OS: remove newest Installed RollupFix ONLY if a Superseded/Staged one exists underneath to surface
    $osInstalled = Get-WindowsPackage -Online | Where-Object { $_.PackageName -match 'RollupFix' -and "$($_.PackageState)" -eq 'Installed' } | Sort-Object { [version](($_.PackageName -split '~')[-1]) } -Descending
    $osUnder = Get-WindowsPackage -Online | Where-Object { $_.PackageName -match 'RollupFix' -and "$($_.PackageState)" -in 'Superseded','Staged' }
    if($osInstalled -and $osUnder){ $top=$osInstalled|Select-Object -First 1; dism /online /remove-package /packagename:$($top.PackageName) /norestart *>$null; $removed += "os:$($top.PackageName.Split('~')[-1]) (exit $LASTEXITCODE)" }
    [pscustomobject]@{ Removed = ($removed -join '; ') }
}
Remove-PSSession $tgt -ErrorAction SilentlyContinue
Write-OK "Removed: $($p1.Removed)"

Write-Step "Rebooting $TargetNode (apply Pass 1 removals)"
try { Restart-Computer -ComputerName $TargetNode -Credential $tcred -Force -ErrorAction Stop } catch { }
if (-not (Wait-NodeBack $TargetNode)) { Write-Err2 "$TargetNode did not return; investigate."; return }
Write-OK "$TargetNode back online."

# ---------------------------------------------------------------------------
# Pass 2: install the exact 9333.2 MSU fresh
# ---------------------------------------------------------------------------
Write-Step "Pushing + installing $msuName (KB5082417 / 9333.2) offline"
$tgt = New-Sess $TargetNode 600000
$remoteMsu = "C:\Windows\Temp\$msuName"
Copy-Item -ToSession $tgt -Path $MsuPath -Destination $remoteMsu -Force
$inst = Invoke-Command -Session $tgt -ScriptBlock {
    param($remoteMsu)
    foreach ($svc in 'wuauserv','cryptSvc','bits') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
    $sd='C:\Windows\SoftwareDistribution'
    if (Test-Path $sd) { try { Rename-Item $sd "SoftwareDistribution.bak-$([datetime]::Now.ToString('yyyyMMddHHmmss'))" -ErrorAction Stop } catch {} }
    foreach ($svc in 'wuauserv','cryptSvc','bits') { Start-Service -Name $svc -ErrorAction SilentlyContinue }
    try {
        $r = Add-WindowsPackage -Online -PackagePath $remoteMsu -NoRestart -ErrorAction Stop
        [pscustomobject]@{ Ok=$true; RestartNeeded=[bool]$r.RestartNeeded; Err=$null }
    } catch {
        [pscustomobject]@{ Ok=$false; RestartNeeded=$false; Err=$_.Exception.Message }
    }
} -ArgumentList $remoteMsu
Remove-PSSession $tgt -ErrorAction SilentlyContinue
if (-not $inst.Ok) { Write-Err2 "Add-WindowsPackage failed: $($inst.Err)"; return }
Write-OK "MSU installed. RestartNeeded=$($inst.RestartNeeded)"

Write-Step "Rebooting $TargetNode (finalize KB5082417 install)"
try { Restart-Computer -ComputerName $TargetNode -Credential $tcred -Force -ErrorAction Stop } catch { }
if (-not (Wait-NodeBack $TargetNode)) { Write-Err2 "$TargetNode did not return; investigate."; return }
Write-OK "$TargetNode back online."

# ---------------------------------------------------------------------------
# Validate recipe
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
    Write-OK "RECIPE PASSES ($($res.Total) checks, 0 failures)."
    Write-Host "    NEXT: az resource delete -g rg-azlocal-poc-001 -n AZL-NODE-05 --resource-type Microsoft.HybridCompute/machines" -ForegroundColor Yellow
    Write-Host "          .\scripts\Onboard-ArcMachine.ps1 -NodeFqdn $TargetNode" -ForegroundColor Yellow
} else {
    Write-Err2 "Recipe still failing ($($res.Failures)/$($res.Total): $($res.FailNames)). Inspect package state."
}
