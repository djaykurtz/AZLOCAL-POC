<#
.SYNOPSIS
  Runs client-side dry-run checks for POC Kubernetes manifests.

.DESCRIPTION
  Validates Kubernetes manifest shape without applying anything to a cluster.
  Uses kubectl apply --dry-run=client --validate=false so it can run before
  the AKS-on-Azure-Local cluster exists.

.EXAMPLE
  .\scripts\Test-KubernetesManifests.ps1
#>

[CmdletBinding()]
param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot '..\tests\kubernetes\smoke')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
  throw 'kubectl was not found in PATH. Install kubectl to run Kubernetes dry-run validation.'
}

$resolvedPath = Resolve-Path -LiteralPath $ManifestPath

Write-Host "Kubernetes client dry-run validation" -ForegroundColor Cyan
Write-Host "Manifest path: $($resolvedPath.Path)"
Write-Host 'Mode: client-side dry-run only; no resources are applied.'

$output = & kubectl apply --dry-run=client --validate=false -f $resolvedPath.Path 2>&1
$output | Write-Host
if ($LASTEXITCODE -ne 0) {
  throw "kubectl client dry-run failed with exit code $LASTEXITCODE."
}

Write-Host "`nKubernetes manifest dry-run complete. Nothing was deployed." -ForegroundColor Green