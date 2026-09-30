<#
.SYNOPSIS
  Activate the standard Azure Local POC PIM roles for the work day.

.DESCRIPTION
  Thin wrapper around Invoke-PimActivate.ps1 for the PIM-eligible roles needed
  for normal POC work: Azure Stack HCI Administrator (subscription) and
  RG-scoped User Access Administrator. Contributor is intentionally NOT listed
  here: it is a STANDING (permanent) assignment on the POC subscription, not a
  PIM-eligible role, so attempting to self-activate it always fails with
  "No eligible roles matched" and previously dragged the whole run to exit 1.
  Defaults the justification to today's work date so the command is safe to run
  from any terminal without editing a snippet.

.EXAMPLE
  .\scripts\Invoke-PocPimElevation.ps1

.EXAMPLE
  .\scripts\Invoke-PocPimElevation.ps1 -Status

.EXAMPLE
  .\scripts\Invoke-PocPimElevation.ps1 -Reason 'POC day work 18-jun'
#>

[CmdletBinding()]
param(
  [ValidateLength(5,400)]
  [string]$Reason = "POC day work $(Get-Date -Format 'dd-MMM')",

  [ValidateRange(1,8)]
  [int]$Hours = 8,

  [ValidateRange(1,3)]
  [int]$ThrottleLimit = 3,

  [switch]$Status
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$activator = Join-Path $PSScriptRoot 'Invoke-PimActivate.ps1'

if (-not (Test-Path -LiteralPath $activator)) {
  throw "PIM activator not found: $activator"
}

# PIM-ELIGIBLE roles for normal POC work. These two cover Arc VM create AND delete,
# images, and logical networks. NOTE (verified 2026-07-31): Contributor IS PIM-eligible at
# subscription scope but is NOT needed here - the two roles below are sufficient. Delete failures
# right after activation are RBAC PROPAGATION LAG on the Microsoft.AzureStackHCI RP: wait ~2-3 min
# after this routine before running az stack-hci-vm delete/create, or you get transient
# AuthorizationFailed even though the role shows Active.
$roles = @(
  @{ RoleName = 'Azure Stack HCI Administrator' }
  @{ RoleName = 'User Access Administrator'; ScopeType = 'resourcegroup' }
)

Write-Host "Azure Local POC PIM routine" -ForegroundColor Cyan
Write-Host "Repo:   $repoRoot"
if ($Status) {
  Write-Host "Mode:   status only"
} else {
  Write-Host "Reason: $Reason"
  Write-Host "Hours:  $Hours"
}

$roles | ForEach-Object -Parallel {
  $arguments = @{} + $_
  $tag = $arguments.RoleName

  if ($using:Status) {
    $arguments.Status = $true
  } else {
    $arguments.Reason = $using:Reason
    $arguments.Hours = $using:Hours
  }

  & $using:activator @arguments *>&1 |
    ForEach-Object { "[$tag] $_" }

  if ($LASTEXITCODE -ne 0) {
    throw "PIM routine failed for $tag with exit code $LASTEXITCODE."
  }
} -ThrottleLimit $ThrottleLimit