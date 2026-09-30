<#
.SYNOPSIS
  One-command per-node rollout for Azure Local storage+network readiness.
  Chains the three PROVEN steps so nodes 03-06 (returning from the 3x-NVMe
  hardware build) are prepped with a single invocation instead of hand-run
  ad-hoc commands.

.DESCRIPTION
  Orchestration only - it calls the existing single-purpose scripts so each
  operation keeps ONE source of truth:
    1. Test-NetworkPreflight.ps1  -> enable disabled Mellanox ports + verify NIC gate
    2. Clear-DataDisks.ps1        -> make data NVMe poolable (attribute-based, never OS disk)
    3. Invoke-HardwareValidator.ps1 -> full Azure Local hardware validation

  SAFETY: DRY-RUN BY DEFAULT. Without -Execute, it runs the network gate in
  report-only mode and Clear-DataDisks in dry-run (no wipe), then validation.
  With -Execute it enables disabled NICs and CLEARS the data disks (destructive
  on non-OS disks only - Clear-DataDisks guards IsBoot/IsSystem/BootFromDisk).

.PARAMETER NodeFqdn
  One or more node FQDNs to prep, e.g. azl-node-03.lab.example.com.

.PARAMETER Execute
  Perform the enabling + disk clear. Omit for a full dry-run preview.

.PARAMETER SkipValidation
  Skip the final Invoke-HardwareValidator pass (faster iteration).

.EXAMPLE
  .\scripts\Invoke-NodeStoragePrep.ps1 -NodeFqdn azl-node-03.lab.example.com            # dry run
  .\scripts\Invoke-NodeStoragePrep.ps1 -NodeFqdn azl-node-03.lab.example.com -Execute   # do it
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]] $NodeFqdn,
  [switch] $Execute,
  [switch] $SkipValidation
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$preflight = Join-Path $here 'Test-NetworkPreflight.ps1'
$cleardisk = Join-Path $here 'Clear-DataDisks.ps1'
$validator = Join-Path $here 'Invoke-HardwareValidator.ps1'
foreach ($p in @($preflight,$cleardisk,$validator)) {
  if (-not (Test-Path $p)) { throw "Required script missing: $p" }
}

foreach ($fqdn in $NodeFqdn) {
  $short = ($fqdn -split '\.')[0]
  Write-Host "`n############################################################" -ForegroundColor Cyan
  Write-Host "#  NODE STORAGE PREP: $short  (mode: $(if ($Execute) {'EXECUTE'} else {'DRY-RUN'}))" -ForegroundColor Cyan
  Write-Host "############################################################" -ForegroundColor Cyan

  # --- Step 1: network pre-flight (enable Mellanox if -Execute) ---
  Write-Host "`n--- Step 1/3: network pre-flight ---" -ForegroundColor White
  try {
    if ($Execute) { & $preflight -NodeFqdn $fqdn -EnableDisabled }
    else          { & $preflight -NodeFqdn $fqdn }
  } catch { Write-Host "  Step 1 error (continuing): $($_.Exception.Message)" -ForegroundColor Red }

  # --- Step 2: make data disks poolable ---
  Write-Host "`n--- Step 2/3: data-disk prep ---" -ForegroundColor White
  try {
    if ($Execute) { & $cleardisk -NodeFqdn $fqdn -Confirm2 }
    else          { & $cleardisk -NodeFqdn $fqdn }
  } catch { Write-Host "  Step 2 error (continuing): $($_.Exception.Message)" -ForegroundColor Red }

  # --- Step 3: hardware validation ---
  if ($SkipValidation) {
    Write-Host "`n--- Step 3/3: hardware validation SKIPPED (-SkipValidation) ---" -ForegroundColor DarkGray
  } else {
    Write-Host "`n--- Step 3/3: hardware validation ---" -ForegroundColor White
    try {
      if ($short -match 'azl-node-0(\d)') {
        & $validator -NodeNumbers ([int]$Matches[1])
      } else {
        Write-Host "  (could not derive node number from '$short'; run Invoke-HardwareValidator manually)" -ForegroundColor Yellow
      }
    } catch { Write-Host "  Step 3 error (continuing): $($_.Exception.Message)" -ForegroundColor Red }
  }

  Write-Host "`n=== $short prep complete (mode: $(if ($Execute) {'EXECUTE'} else {'DRY-RUN'})) ===" -ForegroundColor Green
}

if (-not $Execute) {
  Write-Host "`nDRY-RUN only. Re-run with -Execute to enable NICs + clear data disks." -ForegroundColor Magenta
}
