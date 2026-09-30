<#
.SYNOPSIS
  Runs Terraform validation and plan-only checks for POC modules.

.DESCRIPTION
  Safe Terraform workflow for the Azure Local POC surface. It runs fmt,
  init with -backend=false, validate, and plan with no apply path. This is
  intended for deployment-script authoring while hardware is blocked.

.EXAMPLE
  .\scripts\Invoke-TerraformPlanOnly.ps1

.EXAMPLE
  .\scripts\Invoke-TerraformPlanOnly.ps1 -NodeCount 6
#>

[CmdletBinding()]
param(
  [string]$ModulePath = (Join-Path $PSScriptRoot '..\tests\terraform\poc-smoke'),

  [ValidateSet(4,6)]
  [int]$NodeCount = 4,

  [string]$PlanName = 'poc-smoke',

  [switch]$KeepPlanFile
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
  throw 'terraform was not found in PATH. Install Terraform to run plan-only validation.'
}

$resolvedModule = Resolve-Path -LiteralPath $ModulePath
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$outDir = Join-Path $repoRoot 'out'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$planPath = Join-Path $outDir "_terraform-$PlanName-node$NodeCount-$timestamp.tfplan"
$dataDir = Join-Path $env:TEMP "azloc-terraform-$PlanName-node$NodeCount-$timestamp"

function Invoke-TerraformStep {
  param([string]$Name, [string[]]$Arguments)
  Write-Host "`n[*] terraform $Name" -ForegroundColor Cyan
  $output = & terraform @Arguments 2>&1
  $output | Write-Host
  if ($LASTEXITCODE -ne 0) {
    throw "terraform $Name failed with exit code $LASTEXITCODE."
  }
}

$oldDataDir = $env:TF_DATA_DIR
try {
  $env:TF_DATA_DIR = $dataDir
  Invoke-TerraformStep -Name 'fmt -check' -Arguments @('-chdir={0}' -f $resolvedModule.Path, 'fmt', '-check', '-recursive')
  Invoke-TerraformStep -Name 'init -backend=false' -Arguments @('-chdir={0}' -f $resolvedModule.Path, 'init', '-backend=false', '-input=false', '-no-color')
  Invoke-TerraformStep -Name 'validate' -Arguments @('-chdir={0}' -f $resolvedModule.Path, 'validate', '-no-color')
  Invoke-TerraformStep -Name 'plan only' -Arguments @('-chdir={0}' -f $resolvedModule.Path, 'plan', '-refresh=false', '-input=false', '-lock=false', '-no-color', '-var', "node_count=$NodeCount", '-out', $planPath)

  Write-Host "`nPlan-only validation complete: $planPath" -ForegroundColor Green
  if (-not $KeepPlanFile) {
    Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
    Write-Host 'Plan file removed. Use -KeepPlanFile to retain it.' -ForegroundColor DarkGray
  }
} finally {
  $env:TF_DATA_DIR = $oldDataDir
  Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
}