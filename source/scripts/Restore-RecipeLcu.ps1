<#
.SYNOPSIS
    Restores the Azure Local OS image recipe LCUs on a node that was
    contaminated by SConfig/Windows Update, by uninstalling the superseding
    cumulative rollups so the recipe-baseline LCUs resurface.

.DESCRIPTION
    Root cause (see decisions / repo memory): running SConfig option 6 / Windows
    Update on an Azure Local node installs newer cumulative rollups
    (OS RollupFix + .NET DotNetRollup_481) that SUPERSEDE the exact LCUs the
    signed OSImageRecipe.xml pins (e.g. KB5082417 + KB5082063). The recipe
    validation does exact-KB matching, so the node then fails
    Invoke-AzStackHciOSImageRecipeValidation even though it is "more patched".

    The recipe XML is digitally signed and cannot be edited. The supported-style
    recovery proven on node01 is to UNINSTALL the superseding rollups; the
    recipe-baseline LCUs sitting "Superseded" underneath become "Installed"
    again, and the recipe validation passes.

    This script automates that loop per node:
      1. Run the real recipe validation. If it already passes, stop.
      2. Find the newest *Installed* Package_for_RollupFix and
         Package_for_DotNetRollup_481 packages.
      3. dism /online /remove-package /norestart for each.
      4. Reboot, wait for WinRM.
      5. Re-validate. Repeat up to -MaxRounds times.

    NOTE: This does NOT run Windows Update and does NOT edit the recipe. It only
    removes superseding rollups. It is reboot-heavy (1 reboot per round).

.PARAMETER NodeFqdn
    Target node FQDN, e.g. azl-node-03.lab.example.com.

.PARAMETER MaxRounds
    Max uninstall+reboot rounds before giving up. Default 3 (node01 needed 2).

.PARAMETER RebootWaitMinutes
    Minutes to wait for the node to return after each reboot. Default 20.

.PARAMETER CredFile
    DPAPI-encrypted cred file. Default matches repo convention.

.PARAMETER Username
    Local user. Default Administrator.

.PARAMETER WhatIfOnly
    Show what would be removed without removing or rebooting.

.EXAMPLE
    .\scripts\Restore-RecipeLcu.ps1 -NodeFqdn azl-node-03.lab.example.com -WhatIfOnly

.EXAMPLE
    .\scripts\Restore-RecipeLcu.ps1 -NodeFqdn azl-node-03.lab.example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $NodeFqdn,

    [int]    $MaxRounds = 3,
    [int]    $RebootWaitMinutes = 20,
    [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
    [string] $Username = 'Administrator',
    [switch] $WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$outDir   = Join-Path $repoRoot 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Step($m) { Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-OK($m)   { Write-Host "    OK: $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Err2($m) { Write-Host "    FAIL: $m" -ForegroundColor Red }

if (-not $CredFile -or -not (Test-Path $CredFile)) {
    throw "CredFile not found: $CredFile (run Sync-CredFromKeyVault.ps1 first)"
}
$short = ($NodeFqdn -split '\.')[0]
$pw    = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
$cred  = [pscredential]::new("$short\$Username", $pw)

function New-NodeSession {
    param([int]$OpTimeout = 300000)
    $opt = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout $OpTimeout
    # Retry transient post-reboot WinRM HTTP 12152 ("invalid or unrecognized response").
    $last = $null
    for ($i = 0; $i -lt 10; $i++) {
        try { return New-PSSession -ComputerName $NodeFqdn -Credential $cred -Authentication Negotiate -SessionOption $opt -ErrorAction Stop }
        catch { $last = $_; Start-Sleep -Seconds 20 }
    }
    throw $last
}

# Returns: [pscustomobject] Passing(bool), Failures(int), Rows(string)
function Test-Recipe {
    $s = New-NodeSession 300000
    try {
        Invoke-Command -Session $s -ScriptBlock {
            Import-Module AzStackHci.EnvironmentChecker -ErrorAction SilentlyContinue
            $res = @(Invoke-AzStackHciOSImageRecipeValidation -PassThru -ErrorAction SilentlyContinue 3>$null 4>$null 5>$null 6>$null)
            $fails = @($res | Where-Object { "$($_.Status)" -eq 'FAILURE' })
            $rows  = foreach ($x in $res) {
                if ($x.PSObject.Properties.Name -contains 'Status') {
                    '{0}={1}' -f ($x.Name -replace 'AzStackHci_OSImageRecipeValidation_',''), "$($x.Status)"
                }
            }
            [pscustomobject]@{
                Passing  = ($res.Count -gt 0 -and $fails.Count -eq 0)
                Total    = $res.Count
                Failures = $fails.Count
                Rows     = ($rows -join ' | ')
                Hotfixes = ((Get-HotFix | ForEach-Object { $_.HotFixID }) -join ' ')
            }
        }
    } finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
}

# Returns newest Installed RollupFix + DotNetRollup_481 package names, but ONLY
# when there is a Superseded package of the same family underneath (so removing
# the Installed one actually SURFACES an older recipe-baseline LCU). If nothing is
# superseded underneath, returns $null for that family to avoid stripping the last
# rollup to zero (which happened on node05 and left it with no .NET LCU at all).
function Get-SupersedingRollups {
    $s = New-NodeSession 300000
    try {
        Invoke-Command -Session $s -ScriptBlock {
            $all = Get-WindowsPackage -Online
            function Pick($pattern) {
                $fam = $all | Where-Object { $_.PackageName -match $pattern }
                $installed = $fam | Where-Object { "$($_.PackageState)" -eq 'Installed' } |
                             Sort-Object { [version](($_.PackageName -split '~')[-1]) } -Descending | Select-Object -First 1
                if (-not $installed) { return $null }
                $hasUnderneath = $fam | Where-Object { "$($_.PackageState)" -in 'Superseded','Staged' }
                if (-not $hasUnderneath) { return $null }   # nothing to surface; do not strip to zero
                return $installed.PackageName
            }
            [pscustomobject]@{
                OS  = (Pick 'Package_for_RollupFix')
                Net = (Pick 'Package_for_DotNetRollup_481')
            }
        }
    } finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
}

function Remove-Packages {
    param([string[]] $PackageNames)
    $s = New-NodeSession 600000
    try {
        Invoke-Command -Session $s -ScriptBlock {
            param($pkgs)
            foreach ($p in $pkgs) {
                if (-not $p) { continue }
                $out = dism /online /remove-package /packagename:$p /norestart 2>&1
                [pscustomobject]@{ Package = $p; ExitCode = $LASTEXITCODE; Tail = (($out | Select-Object -Last 2) -join ' ') }
            }
        } -ArgumentList (,$PackageNames)
    } finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
}

function Restart-NodeAndWait {
    try { Restart-Computer -ComputerName $NodeFqdn -Credential $cred -Force -ErrorAction Stop } catch { }
    Start-Sleep -Seconds 120
    $deadline = (Get-Date).AddMinutes($RebootWaitMinutes)
    # Require the node to actually accept a PSSession (not just Test-WSMan) twice in a
    # row, since post-CU-uninstall servicing returns HTTP 12152 on WinRM for several
    # minutes even after WS-Man starts answering.
    $good = 0
    while ((Get-Date) -lt $deadline) {
        try {
            $opt = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 60000
            $probe = New-PSSession -ComputerName $NodeFqdn -Credential $cred -Authentication Negotiate -SessionOption $opt -ErrorAction Stop
            Remove-PSSession $probe -ErrorAction SilentlyContinue
            $good++
            if ($good -ge 2) { Start-Sleep -Seconds 15; return $true }
            Start-Sleep -Seconds 30
        }
        catch { $good = 0; Start-Sleep -Seconds 30 }
    }
    return $false
}

Write-Step "Node $NodeFqdn : initial recipe validation"
$r = Test-Recipe
Write-Host "    Hotfixes: $($r.Hotfixes)"
Write-Host "    Recipe:   $($r.Rows)"
if ($r.Passing) { Write-OK "Recipe already PASSES ($($r.Total) checks, 0 failures). Nothing to do."; return }
Write-Warn2 "Recipe failing ($($r.Failures)/$($r.Total)). Beginning rollback rounds."

for ($round = 1; $round -le $MaxRounds; $round++) {
    Write-Step "Round $round/$MaxRounds : find superseding rollups"
    $roll = Get-SupersedingRollups
    Write-Host "    OS rollup:  $($roll.OS)"
    Write-Host "    NET rollup: $($roll.Net)"
    $targets = @($roll.OS, $roll.Net) | Where-Object { $_ }
    if (-not $targets) { Write-Err2 "No Installed RollupFix/DotNetRollup found to remove; cannot proceed."; break }

    if ($WhatIfOnly) {
        Write-Warn2 "WhatIf: would remove: $($targets -join ', ') then reboot."
        return
    }

    Write-Step "Round $round : removing $($targets.Count) package(s)"
    $rm = Remove-Packages -PackageNames $targets
    foreach ($x in $rm) { Write-Host "    removed $($x.Package) -> exit $($x.ExitCode)" }

    Write-Step "Round $round : rebooting $short"
    if (-not (Restart-NodeAndWait)) { Write-Err2 "$short did not return within $RebootWaitMinutes min."; return }
    Write-OK "$short back online."

    $r = Test-Recipe
    Write-Host "    Hotfixes: $($r.Hotfixes)"
    Write-Host "    Recipe:   $($r.Rows)"
    if ($r.Passing) {
        Write-OK "Recipe PASSES after round $round ($($r.Total) checks, 0 failures)."
        $r | ConvertTo-Json | Set-Content (Join-Path $outDir "$short-recipe-restored-$ts.json")
        return
    }
    Write-Warn2 "Still failing ($($r.Failures)/$($r.Total)); continuing."
}

Write-Err2 "Recipe still not passing on $short after $MaxRounds rounds. Inspect manually."
