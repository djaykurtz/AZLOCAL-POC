<#
.SYNOPSIS
  Backend waiter: brings reimaged Azure Local nodes back into Azure Arc
  automatically as each one becomes reachable after a clean reimage.

.DESCRIPTION
  For each target node this script loops until the node answers WinRM, then
  runs the PROVEN clean-reimage Arc recovery (repo memory, 2026-06/07):

    1. WAIT      - poll WinRM (5985) until the node is up after imaging.
    2. OS GUARD  - assert the node is really Azure Local (OS SKU 406 /
                   EditionID ServerAzureStackHCICor). Hard-fail a wrong OS
                   (e.g. someone imaged Windows Server 2025 by mistake).
    3. RECIPE    - Invoke-AzStackHciOSImageRecipeValidation must pass
                   NATIVELY (0 failures). A clean ISO image + skipped
                   SConfig/WU passes on its own; failures here mean the
                   node was contaminated by Windows Update again -> we do
                   NOT onboard it, we flag it for Restore-RecipeLcu.
    4. DE-STALE  - delete the stale Disconnected HybridCompute/machines
                   resource so Arc bootstrap does not hit AZCM0044
                   "Resource Already Exists".
    5. ONBOARD   - call the existing Onboard-ArcMachine.ps1 for the node.
    6. VERIFY    - az resource show -> Status=Connected.

  Resilient + idempotent: one node's failure never aborts the others;
  re-running skips nodes already Connected. Safe to launch and leave
  running while the tech images 03/04/06.

.PARAMETER Nodes
  Short names or FQDNs to shepherd. Default: the three being reimaged
  (03, 04, 06). 05 is deferred; 01/02 already Connected.

.PARAMETER TimeoutMinutes
  Per-node max minutes to wait for WinRM before giving up. Default 90
  (covers a full reimage + first boot).

.PARAMETER PollSeconds
  Seconds between reachability polls. Default 30.

.PARAMETER SkipRecipeGate
  Onboard even if native recipe validation reports failures. NOT
  recommended; only for a node you will remediate by hand.

.PARAMETER WhatIfOnly
  Show what would happen (no delete, no onboard).

.EXAMPLE
  # Launch and leave running while 03/04/06 image
  .\scripts\Wait-AndArcOnboard.ps1

.EXAMPLE
  .\scripts\Wait-AndArcOnboard.ps1 -Nodes azl-node-04 -WhatIfOnly

.NOTES
  Prereqs: az login (right tenant/sub), Set-DevBoxPrereqs.ps1 once
  (TrustedHosts), .creds\azloc-local-admin.cred present.
  Reuses scripts\Onboard-ArcMachine.ps1 for the actual bootstrap.
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @('azl-node-03','azl-node-04','azl-node-06'),
  [int]      $TimeoutMinutes = 90,
  [int]      $PollSeconds = 30,
  [switch]   $SkipRecipeGate,
  [switch]   $WhatIfOnly,

  [string]   $CredFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred'),
  [string]   $Username = 'Administrator',
  [string]   $TenantId       = '00000000-0000-0000-0000-000000000002',
  [string]   $SubscriptionId = '00000000-0000-0000-0000-000000000001',
  [string]   $ResourceGroup  = 'rg-azlocal-poc-001'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir   = Join-Path $repoRoot 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$onboardScript = Join-Path $PSScriptRoot 'Onboard-ArcMachine.ps1'

function Log($m,$c='Gray'){ Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -ForegroundColor $c }

# The one OS SKU that proves Azure Local (not Windows Server 2025 = SKU 7/8).
$AzureLocalSku = 406

# --- Preflight -------------------------------------------------------------
if (-not (Test-Path $onboardScript)) { throw "Onboard-ArcMachine.ps1 not found at $onboardScript" }
if (-not (Test-Path $CredFile))      { throw "CredFile not found: $CredFile (run Sync-CredFromKeyVault.ps1)" }

$ctx = az account show -o json 2>$null | ConvertFrom-Json
if (-not $ctx)                       { throw "az CLI not signed in. Run 'az login --tenant $TenantId'." }
if ($ctx.tenantId -ne $TenantId)     { throw "Tenant mismatch. Run 'az login --tenant $TenantId'." }
if ($ctx.id -ne $SubscriptionId)     { az account set --subscription $SubscriptionId | Out-Null }
Log "az context OK: $($ctx.user.name) / $($ctx.id)" Green

$pw = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())

# Normalize targets to short + fqdn
$targets = foreach ($n in $Nodes) {
  $short = ($n -split '\.')[0].ToLower()
  [pscustomobject]@{ Short = $short; Fqdn = "$short.lab.example.com" }
}

Log ("Shepherding {0} node(s) into Arc: {1}" -f $targets.Count, ($targets.Short -join ', ')) Cyan
if ($WhatIfOnly) { Log "WHATIF mode - no deletes, no onboards." Yellow }

$summary = @()

foreach ($t in $targets) {
  $short = $t.Short; $fqdn = $t.Fqdn
  Write-Host ""
  Log "===== $fqdn =====" Cyan
  $row = [pscustomobject]@{ Node=$short; Reachable=$false; OS=''; Recipe=''; StaleDeleted=''; Onboard=''; ArcStatus=''; Note='' }

  # 0) Already Connected? skip.
  $already = az resource show -g $ResourceGroup -n $short.ToUpper() --resource-type Microsoft.HybridCompute/machines --query "properties.status" -o tsv 2>$null
  if ($already -eq 'Connected') {
    Log "$short already Connected in Arc - skipping." Green
    $row.Reachable=$true; $row.ArcStatus='Connected'; $row.Note='already-connected'; $summary += $row; continue
  }

  # 1) WAIT for WinRM
  $cred = [pscredential]::new("$short\$Username", $pw)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  $up = $false
  Log "Waiting for WinRM (timeout ${TimeoutMinutes}m, poll ${PollSeconds}s)..." Gray
  while ((Get-Date) -lt $deadline) {
    try {
      $o = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 30000
      $tmp = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $o -ErrorAction Stop
      Remove-PSSession $tmp; $up = $true; break
    } catch { Start-Sleep -Seconds $PollSeconds }
  }
  $row.Reachable = $up
  if (-not $up) { Log "$short never came up within ${TimeoutMinutes}m." Red; $row.Note='winrm-timeout'; $summary += $row; continue }
  Log "$short is up (WinRM answering)." Green

  # 2+3) OS GUARD + RECIPE in one remote call
  $probe = $null
  try {
    $o = New-PSSessionOption -OpenTimeout 12000 -OperationTimeout 300000
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $o -ErrorAction Stop
    $probe = Invoke-Command -Session $s -ScriptBlock {
      $os = Get-CimInstance Win32_OperatingSystem
      $p  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
      $recFails = $null; $recErr = ''
      try {
        Import-Module AzStackHci.EnvironmentChecker -ErrorAction Stop
        $res = @(Invoke-AzStackHciOSImageRecipeValidation -PassThru -ErrorAction SilentlyContinue 3>$null 4>$null 5>$null 6>$null)
        $recFails = @($res | Where-Object { "$($_.Status)" -eq 'FAILURE' }).Count
      } catch { $recErr = $_.Exception.Message.Split([char]10)[0] }
      [pscustomobject]@{
        SkuNum      = [int]$os.OperatingSystemSKU
        EditionID   = $p.EditionID
        ProductName = $p.ProductName
        RecipeFails = $recFails
        RecipeErr   = $recErr
      }
    }
    Remove-PSSession $s
  } catch {
    Log "Probe failed on ${short}: $($_.Exception.Message.Split([char]10)[0])" Red
    $row.Note='probe-failed'; $summary += $row; continue
  }

  $row.OS = "SKU=$($probe.SkuNum)/$($probe.EditionID)"
  if ($probe.SkuNum -ne $AzureLocalSku) {
    Log "WRONG OS on ${short}: SKU=$($probe.SkuNum) ProductName='$($probe.ProductName)'. Expected SKU $AzureLocalSku (Azure Local). NOT onboarding." Red
    $row.Note='WRONG-OS-not-azure-local'; $summary += $row; continue
  }
  Log "OS guard PASS: Azure Local SKU 406 ($($probe.ProductName))." Green

  if ($null -eq $probe.RecipeFails) {
    Log "Recipe validation could not run ($($probe.RecipeErr))." Yellow
    $row.Recipe = "unknown:$($probe.RecipeErr)"
    if (-not $SkipRecipeGate) { $row.Note='recipe-unavailable'; $summary += $row; continue }
  } elseif ($probe.RecipeFails -gt 0) {
    $row.Recipe = "FAIL($($probe.RecipeFails))"
    Log "Recipe validation FAILED ($($probe.RecipeFails) failures) on $short - node likely WU-contaminated. NOT onboarding; run Restore-RecipeLcu.ps1." Red
    if (-not $SkipRecipeGate) { $row.Note='recipe-failures-remediate-first'; $summary += $row; continue }
  } else {
    $row.Recipe = 'PASS'
    Log "Recipe validation PASS natively (clean image)." Green
  }

  if ($WhatIfOnly) {
    Log "WHATIF: would delete stale Arc resource $($short.ToUpper()) then run Onboard-ArcMachine.ps1 -NodeFqdn $fqdn" DarkGray
    $row.StaleDeleted='(whatif)'; $row.Onboard='(whatif)'; $row.Note='whatif'; $summary += $row; continue
  }

  # 4) DE-STALE
  $stale = az resource show -g $ResourceGroup -n $short.ToUpper() --resource-type Microsoft.HybridCompute/machines --query "properties.status" -o tsv 2>$null
  if ($stale) {
    Log "Deleting stale Arc resource $($short.ToUpper()) (status=$stale) to avoid AZCM0044..." Yellow
    az resource delete -g $ResourceGroup -n $short.ToUpper() --resource-type Microsoft.HybridCompute/machines 2>$null | Out-Null
    $row.StaleDeleted = "deleted($stale)"
  } else {
    $row.StaleDeleted = 'none'
  }

  # 5) ONBOARD (reuse the proven script)
  Log "Onboarding $short to Arc..." Cyan
  try {
    & $onboardScript -NodeFqdn $fqdn -TenantId $TenantId -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup 2>&1 |
      Tee-Object -FilePath (Join-Path $outDir "$short-arc-wait-onboard-$ts.log") | Out-Null
    $row.Onboard = 'ran'
  } catch {
    Log "Onboard threw on ${short}: $($_.Exception.Message.Split([char]10)[0])" Red
    $row.Onboard = 'error'; $row.Note='onboard-threw'; $summary += $row; continue
  }

  # 6) VERIFY
  Start-Sleep -Seconds 10
  $final = az resource show -g $ResourceGroup -n $short.ToUpper() --resource-type Microsoft.HybridCompute/machines --query "properties.status" -o tsv 2>$null
  $row.ArcStatus = $final
  if ($final -eq 'Connected') { Log "$short is CONNECTED to Arc." Green; $row.Note='connected' }
  else { Log "$short onboard ran but status='$final' (may need a retry / connectivity triage, exit-44 class)." Yellow; if(-not $row.Note){$row.Note='post-onboard-not-connected'} }

  $summary += $row
}

Write-Host ""
Log "================ ARC ONBOARD SUMMARY ================" Cyan
$summary | Format-Table Node,Reachable,OS,Recipe,StaleDeleted,Onboard,ArcStatus,Note -AutoSize -Wrap
$summaryPath = Join-Path $outDir "_wait-arc-onboard-$ts.json"
$summary | ConvertTo-Json -Depth 4 | Set-Content $summaryPath
Log "Summary saved: $summaryPath" DarkGray
