<#
.SYNOPSIS
    Onboards Azure Local OS machines to Azure Arc via
    Invoke-AzStackHciArcInitialization, run remotely via PSSession.

.DESCRIPTION
    Per Microsoft Learn (azloc-2605), Arc registration is OS-level and
    runs BEFORE cluster deployment. This script:

      1. Verifies az CLI is signed in to the right tenant + subscription.
      2. Acquires an ARM access token on the DevBox (one auth, multi-node fan-out).
      3. Per node: opens PSSession with DPAPI-cached local-admin cred,
         runs Invoke-AzStackHciArcInitialization (cmdlet ships with
         Azure Local OS 23H2), captures transcript.
      4. Polls Get-ArcBootstrapStatus and reports per-node outcome.

    ARM tokens live ~60-90 minutes; we re-pull per node so a slow
    onboard at node 06 doesn't fail on a stale token.

.PARAMETER NodeFqdn
    Single node FQDN. Mutually exclusive with -AllNodes.

.PARAMETER AllNodes
    Loop all 6 azl-node-0[1-6].lab.example.com nodes.

.PARAMETER WhatIfOnly
    Print the command that would run on each node without invoking it.
    (Separate from -WhatIf because the wrapped cmdlet has its own.)

.PARAMETER CredFile
    DPAPI-encrypted cred file. Default matches repo convention.

.PARAMETER Username
    Local user. Default Administrator.

.PARAMETER TenantId
    Microsoft Entra tenant ID. Default from the POC plan.

.PARAMETER SubscriptionId
    Subscription. Default from the POC plan.

.PARAMETER ResourceGroup
    RG that will hold the Arc machine resources. Default per plan.

.PARAMETER Region
    Azure region. Default southcentralus.
    NOTE: Azure Local bootstrap (2026-06-04) does NOT support westus3.
    Supported: eastus, eastus2euap, westeurope, australiaeast, southeastasia,
    centralindia, canadacentral, japaneast, southcentralus, germanywestcentral.
    southcentralus chosen as closest geographic match to the westus3 RG.

.PARAMETER TargetSolutionVersion
    Optional Azure Local target solution version for online day-0 update during
    Arc bootstrap. Example: 12.2606.1003.205.

.PARAMETER LocalPlatformPackagePath
    Optional local Platform.<version>.zip path on the remote node for limited
    connectivity/offline day-0 update. Not required for standard online flow.

.EXAMPLE
    # Dry run first
    .\scripts\Onboard-ArcMachine.ps1 -NodeFqdn azl-node-01.lab.example.com -WhatIfOnly

.EXAMPLE
    # Onboard node 01 only
    .\scripts\Onboard-ArcMachine.ps1 -NodeFqdn azl-node-01.lab.example.com

.EXAMPLE
    # Fan-out all 6 nodes
    .\scripts\Onboard-ArcMachine.ps1 -AllNodes
#>
[CmdletBinding(DefaultParameterSetName = 'AllNodes')]
param(
    [Parameter(ParameterSetName = 'OneNode', Mandatory)]
    [string] $NodeFqdn,

    [Parameter(ParameterSetName = 'AllNodes')]
    [switch] $AllNodes = $true,

    [switch] $WhatIfOnly,

    [string] $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),

    [string] $Username = 'Administrator',

    # Defaults sourced from the POC plan (do not change without updating both)
    [string] $TenantId       = '00000000-0000-0000-0000-000000000002',
    [string] $SubscriptionId = '00000000-0000-0000-0000-000000000001',
    [string] $ResourceGroup  = 'rg-azlocal-poc-001',
    # westus3 not supported by Azure Local bootstrap; southcentralus is the closest supported region.
    [string] $Region         = 'southcentralus',
    [string] $Cloud          = 'AzureCloud',
    [string] $TargetSolutionVersion,
    [string] $LocalPlatformPackagePath
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
# Step 0: Sanity: az CLI signed in to the right tenant/sub
# ---------------------------------------------------------------------------
Write-Step "Verifying az CLI context"
$ctx = az account show -o json 2>$null | ConvertFrom-Json
if (-not $ctx) { throw "az CLI not signed in. Run 'az login'." }
if ($ctx.tenantId -ne $TenantId) {
    throw ("Tenant mismatch. Expected {0}, got {1}. Run 'az login --tenant {0}'." -f $TenantId, $ctx.tenantId)
}
if ($ctx.id -ne $SubscriptionId) {
    Write-Warn2 "Subscription mismatch; switching..."
    az account set --subscription $SubscriptionId | Out-Null
}
Write-OK "Signed in as $($ctx.user.name) on $($ctx.id)"

# ---------------------------------------------------------------------------
# Step 1: Confirm cred file
# ---------------------------------------------------------------------------
if (-not (Test-Path $CredFile)) {
    throw "CredFile not found: $CredFile  (run Sync-CredFromKeyVault.ps1 first)"
}
$cipher = (Get-Content $CredFile -Raw).Trim()
$pw     = ConvertTo-SecureString $cipher

# ---------------------------------------------------------------------------
# Step 2: Build target list
# ---------------------------------------------------------------------------
$targets = if ($PSCmdlet.ParameterSetName -eq 'OneNode') {
    @($NodeFqdn)
} else {
    1..6 | ForEach-Object { 'azl-node-{0:D2}.lab.example.com' -f $_ }
}

Write-Step "Onboarding plan"
Write-Host "    Tenant:          $TenantId"
Write-Host "    Subscription:    $SubscriptionId"
Write-Host "    Resource Group:  $ResourceGroup"
Write-Host "    Region:          $Region"
Write-Host "    Cloud:           $Cloud"
if ($TargetSolutionVersion) { Write-Host "    Target Version:  $TargetSolutionVersion" }
if ($LocalPlatformPackagePath) { Write-Host "    Platform Zip:    $LocalPlatformPackagePath" }
Write-Host "    Targets:         $($targets.Count) node(s)"
$targets | ForEach-Object { Write-Host "      - $_" }

$summary = @()

foreach ($fqdn in $targets) {
    $short = ($fqdn -split '\.')[0]
    Write-Step "Node: $fqdn"

    if ($WhatIfOnly) {
        Write-Host @"
    WOULD RUN on $($short):
      Invoke-AzStackHciArcInitialization ``
          -TenantId '$TenantId' ``
          -SubscriptionId '$SubscriptionId' ``
          -ResourceGroup '$ResourceGroup' ``
          -Region '$Region' ``
          -Cloud '$Cloud' ``
          -ArmAccessToken <pulled-just-before-this-call>$(if ($TargetSolutionVersion) { " ```n          -TargetSolutionVersion '$TargetSolutionVersion'" })$(if ($LocalPlatformPackagePath) { " ```n          -LocalPlatformPackagePath '$LocalPlatformPackagePath'" })
"@ -ForegroundColor DarkGray
        $summary += [pscustomobject]@{ Node = $short; Result = 'DRY-RUN'; Status = ''; Log = '' }
        continue
    }

    # Per-node fresh token (ARM audience, ~60 min TTL)
    Write-Host "    Pulling fresh ARM token..."
    $token = (az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv 2>$null)
    if (-not $token) {
        Write-Err2 "Failed to obtain ARM access token; skipping $short"
        $summary += [pscustomobject]@{ Node = $short; Result = 'TOKEN-FAIL'; Status = ''; Log = '' }
        continue
    }

    $logPath = Join-Path $outDir "$short-arc-onboard-$ts.log"
    try {
        $cred = [pscredential]::new("$short\$Username", $pw)
        $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -ErrorAction Stop

        $rawResult = Invoke-Command -Session $s -ScriptBlock {
            param($Tenant, $Sub, $RG, $Region, $Cloud, $Token, $TargetVersion, $PlatformPackagePath)

            # Streamed transcript so we capture everything
            $logFile = "$env:TEMP\arc-init-$([guid]::NewGuid()).log"
            Start-Transcript -Path $logFile -Force | Out-Null
            try {
                # Cmdlet ships with Azure Local OS 23H2 (AzsHCI.ARCinstaller module).
                # Verify before calling so we get a clean error message.
                if (-not (Get-Command Invoke-AzStackHciArcInitialization -ErrorAction SilentlyContinue)) {
                    throw "Invoke-AzStackHciArcInitialization not found. Is this Azure Local OS 23H2?"
                }

                $arcInitParams = @{
                    TenantId       = $Tenant
                    SubscriptionId = $Sub
                    ResourceGroup  = $RG
                    Region         = $Region
                    Cloud          = $Cloud
                    ArmAccessToken = $Token
                }
                if ($TargetVersion) { $arcInitParams.TargetSolutionVersion = $TargetVersion }
                if ($PlatformPackagePath) { $arcInitParams.LocalPlatformPackagePath = $PlatformPackagePath }

                Invoke-AzStackHciArcInitialization @arcInitParams

                # Pull final bootstrap status if available
                $status = $null
                if (Get-Command Get-ArcBootstrapStatus -ErrorAction SilentlyContinue) {
                    $status = (Get-ArcBootstrapStatus).Response.Status
                }
                # Wrap return in a property bag with a unique marker so the
                # caller can filter it out of the (noisy) cmdlet output stream.
                [pscustomobject]@{ __ArcOnboardResult = $true; OK = $true;  Status = $status; LogFile = $logFile; Error = $null }
            } catch {
                [pscustomobject]@{ __ArcOnboardResult = $true; OK = $false; Status = $null;    LogFile = $logFile; Error = $_.Exception.Message }
            } finally {
                Stop-Transcript | Out-Null
            }
        } -ArgumentList $TenantId, $SubscriptionId, $ResourceGroup, $Region, $Cloud, $token, $TargetSolutionVersion, $LocalPlatformPackagePath

        # The cmdlet writes a lot of status output that ends up in $rawResult
        # alongside our return object. Pick out the marked object.
        $bootstrapResult = $rawResult |
            Where-Object { $_ -and $_.PSObject.Properties.Name -contains '__ArcOnboardResult' } |
            Select-Object -Last 1
        if (-not $bootstrapResult) {
            # Fallback: pick any pscustomobject with our shape
            $bootstrapResult = $rawResult |
                Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'LogFile' } |
                Select-Object -Last 1
        }

        # Pull the transcript back to DevBox
        if ($bootstrapResult -and $bootstrapResult.LogFile) {
            Copy-Item -FromSession $s -Path $bootstrapResult.LogFile -Destination $logPath -ErrorAction SilentlyContinue
        }

        if ($bootstrapResult.OK) {
            Write-OK "Bootstrap returned. Status: $($bootstrapResult.Status). Log: $logPath"
            $summary += [pscustomobject]@{ Node = $short; Result = 'OK'; Status = $bootstrapResult.Status; Log = $logPath }
        } else {
            Write-Err2 "Bootstrap failed: $($bootstrapResult.Error). Log: $logPath"
            $summary += [pscustomobject]@{ Node = $short; Result = 'FAIL'; Status = ''; Log = $logPath }
        }

        Remove-PSSession $s
    } catch {
        Write-Err2 "PSSession or run failed: $($_.Exception.Message)"
        $summary += [pscustomobject]@{ Node = $short; Result = 'PSSESSION-FAIL'; Status = ''; Log = $logPath }
    }
}

Write-Host ""
Write-Host "================ SUMMARY ================" -ForegroundColor Cyan
$summary | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$summaryPath = Join-Path $outDir "_arc-onboard-summary-$ts.csv"
$summary | Export-Csv -NoTypeInformation -Path $summaryPath
Write-Host "Summary CSV: $summaryPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: verify in portal -> RG '$ResourceGroup' -> Machine - Azure Arc resources" -ForegroundColor Cyan
