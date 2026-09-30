<#
.SYNOPSIS
    Runs the Azure Local connectivity validator (AzStackHci.EnvironmentChecker)
    either locally on this DevBox or against one/all nodes via PSSession.

.DESCRIPTION
    Tests the outbound HTTPS endpoints that the Azure Local deployment
    wizard and Arc bootstrap require. From the node's network position
    (when run remotely) this is the same test the wizard runs during R3.

    The module is installed on demand. If the target machine has no
    Internet access (chicken-and-egg with the validator), the script
    uses Save-Module on the DevBox and pushes the bits to the node via
    Copy-Item -ToSession.

.PARAMETER Local
    Run on the DevBox only. Useful for smoke-testing the install.

.PARAMETER NodeFqdn
    Single node to test. Mutually exclusive with -AllNodes.

.PARAMETER AllNodes
    Loop azl-node-01..06.

.PARAMETER CredFile
    DPAPI-encrypted cred file. Defaults to repo-standard location.

.PARAMETER Username
    Local user. Defaults to Administrator.

.PARAMETER Service
    Optional. Limit to a specific service group, e.g. 'Arc For Servers',
    'Azure Stack HCI', 'Azure portal'. Empty = all services.

.EXAMPLE
    .\scripts\Invoke-ConnectivityValidator.ps1 -Local

.EXAMPLE
    .\scripts\Invoke-ConnectivityValidator.ps1 -NodeFqdn azl-node-01.lab.example.com

.EXAMPLE
    .\scripts\Invoke-ConnectivityValidator.ps1 -AllNodes
#>
[CmdletBinding(DefaultParameterSetName = 'AllNodes')]
param(
    [Parameter(ParameterSetName = 'Local')]
    [switch] $Local,

    [Parameter(ParameterSetName = 'OneNode', Mandatory)]
    [string] $NodeFqdn,

    [Parameter(ParameterSetName = 'AllNodes')]
    [switch] $AllNodes = $true,

    [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),

    [string] $Username = 'Administrator',

    [string] $Service
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

# ---------------------------------------------------------------------------
# Step 1: Ensure module is available LOCALLY (used by both Local and Remote)
# ---------------------------------------------------------------------------
Write-Step "Ensuring AzStackHci.EnvironmentChecker is installed locally"
$mod = Get-Module -ListAvailable -Name AzStackHci.EnvironmentChecker | Select-Object -First 1
if (-not $mod) {
    Write-Host "    Installing from PSGallery (CurrentUser scope)..."
    try {
        # Trust PSGallery for the session to skip prompts
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        Install-Module -Name AzStackHci.EnvironmentChecker -Scope CurrentUser -Force -AllowClobber
        $mod = Get-Module -ListAvailable -Name AzStackHci.EnvironmentChecker | Select-Object -First 1
    } catch {
        Write-Err2 "Install failed: $_"
        throw
    }
}
Write-OK "Module $($mod.Name) $($mod.Version) at $($mod.ModuleBase)"

# ---------------------------------------------------------------------------
# Step 2: LOCAL run (DevBox)
# ---------------------------------------------------------------------------
if ($Local) {
    Write-Step "Running connectivity validator LOCALLY on this DevBox"
    Import-Module AzStackHci.EnvironmentChecker -Force
    $argz = @{ PassThru = $true }
    if ($Service) { $argz['Service'] = $Service }
    $result = Invoke-AzStackHciConnectivityValidation @argz
    $jsonPath = Join-Path $outDir "_connectivity-devbox-$ts.json"
    $result | ConvertTo-Json -Depth 10 | Set-Content $jsonPath
    Write-OK "Local report -> $jsonPath"

    # Status enum is SUCCESS / FAILURE (not Succeeded / Failed as docs imply)
    $failed = @($result | Where-Object { $_.Status -notin @('SUCCESS','Succeeded') })
    Write-Host ""
    Write-Host ("Tests run: {0}  Failed: {1}" -f $result.Count, $failed.Count) -ForegroundColor Yellow
    if ($failed.Count) {
        $failed | Select-Object Name, EndPoint, Status, Severity | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    }
    return
}

# ---------------------------------------------------------------------------
# Step 3: Resolve credential for remote PSSession
# ---------------------------------------------------------------------------
if (-not (Test-Path $CredFile)) {
    throw "CredFile not found: $CredFile  (run Sync-CredFromKeyVault.ps1 first)"
}
$cipher = (Get-Content $CredFile -Raw).Trim()
$pw     = ConvertTo-SecureString $cipher

# ---------------------------------------------------------------------------
# Step 4: Save module to local stash, ready to push to nodes
# ---------------------------------------------------------------------------
$modStash = Join-Path $env:TEMP "azloc-envchecker-stash"
if (-not (Test-Path $modStash)) {
    Write-Step "Saving module bits to $modStash for push to remote nodes"
    New-Item -ItemType Directory -Path $modStash -Force | Out-Null
    Save-Module -Name AzStackHci.EnvironmentChecker -Path $modStash -Force
}
Write-OK "Module stash ready"

# ---------------------------------------------------------------------------
# Step 5: Build node list
# ---------------------------------------------------------------------------
$targets = if ($PSCmdlet.ParameterSetName -eq 'OneNode') {
    @($NodeFqdn)
} else {
    1..6 | ForEach-Object { 'azl-node-{0:D2}.lab.example.com' -f $_ }
}

$summary = @()

foreach ($fqdn in $targets) {
    $short = ($fqdn -split '\.')[0]
    Write-Step "Node: $fqdn"

    try {
        $cred = [pscredential]::new("$short\$Username", $pw)
        $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -ErrorAction Stop

        # Push module bundle (idempotent)
        $remoteModPath = 'C:\Program Files\WindowsPowerShell\Modules\AzStackHci.EnvironmentChecker'
        $alreadyThere = Invoke-Command -Session $s -ScriptBlock {
            param($p) Test-Path $p
        } -ArgumentList $remoteModPath
        if (-not $alreadyThere) {
            Write-Host "    Pushing module to node..."
            $src = Join-Path $modStash 'AzStackHci.EnvironmentChecker'
            Copy-Item -ToSession $s -Path $src -Destination 'C:\Program Files\WindowsPowerShell\Modules\' -Recurse -Force
        }

        Write-Host "    Running connectivity validator on $short..."
        $result = Invoke-Command -Session $s -ScriptBlock {
            param($svc)
            Import-Module AzStackHci.EnvironmentChecker -Force -ErrorAction Stop
            $a = @{ PassThru = $true }
            if ($svc) { $a['Service'] = $svc }
            Invoke-AzStackHciConnectivityValidation @a
        } -ArgumentList $Service

        $jsonPath = Join-Path $outDir "_connectivity-$short-$ts.json"
        $result | ConvertTo-Json -Depth 10 | Set-Content $jsonPath

        # Same Status-property filter as the local path (excludes warning passthroughs).
        $checks = @($result | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Status' -and $_.Status })
        $failed = @($checks | Where-Object { $_.Status -notin @('SUCCESS','Succeeded') })
        $summary += [pscustomobject]@{
            Node     = $short
            Tests    = $checks.Count
            Failed   = $failed.Count
            Critical = @($failed | Where-Object { $_.Severity -in @('CRITICAL','Critical') }).Count
            Report   = $jsonPath
        }

        if ($failed.Count -eq 0) { Write-OK "All $($checks.Count) tests passed" }
        else                     { Write-Warn2 "$($failed.Count)/$($checks.Count) failed (see $jsonPath)" }

        Remove-PSSession $s
    } catch {
        Write-Err2 $_.Exception.Message
        $summary += [pscustomobject]@{
            Node = $short; Tests = 0; Failed = 0; Critical = 0; Report = "ERROR: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "================ SUMMARY ================" -ForegroundColor Cyan
$summary | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$summaryPath = Join-Path $outDir "_connectivity-summary-$ts.csv"
$summary | Export-Csv -NoTypeInformation -Path $summaryPath
Write-Host "Summary CSV: $summaryPath" -ForegroundColor Cyan
