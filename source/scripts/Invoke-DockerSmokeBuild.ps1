<#
.SYNOPSIS
  Builds the POC smoke Dockerfile locally without pushing or deploying.

.DESCRIPTION
  Local-only Docker build test for the Azure Local POC container surface.
  It validates Dockerfile build plumbing and base image reachability without
  pushing to a registry or deploying to Kubernetes.

.EXAMPLE
  .\scripts\Invoke-DockerSmokeBuild.ps1
#>

[CmdletBinding()]
param(
  [string]$DockerfilePath = (Join-Path $PSScriptRoot '..\tests\docker\smoke\Dockerfile'),
  [string]$Tag = 'azloc-poc-smoke:local',
  [switch]$NoCache
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'docker was not found in PATH. Install/start Docker to run local build validation.'
}

$dockerfile = Resolve-Path -LiteralPath $DockerfilePath
$context = Split-Path -Parent $dockerfile.Path
$dockerArgs = @('build', '--file', $dockerfile.Path, '--tag', $Tag)
if ($NoCache) { $dockerArgs += '--no-cache' }
$dockerArgs += $context

Write-Host "Docker build-only validation" -ForegroundColor Cyan
Write-Host "Dockerfile: $($dockerfile.Path)"
Write-Host "Context:    $context"
Write-Host "Tag:        $Tag"

$output = & docker @dockerArgs 2>&1
$output | Write-Host
if ($LASTEXITCODE -ne 0) {
  throw "docker build failed with exit code $LASTEXITCODE."
}

Write-Host "`nBuild-only validation complete. Image was built locally and not pushed or deployed." -ForegroundColor Green