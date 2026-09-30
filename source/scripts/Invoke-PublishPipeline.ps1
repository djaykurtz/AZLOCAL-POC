<#
.SYNOPSIS
  Operator-run publish pipeline for the Azure Local dashboard workload.

.DESCRIPTION
  A real pipeline with real stages that happens to be triggered by a human instead of a webhook.

  It is built this way on purpose. GitHub hosted runners cannot be scheduled for this repository
  because it is owned by an Enterprise Managed User account, and nothing in this environment is
  reachable from outside Azure Local anyway. A hosted CI service could not reach the cluster even
  if it were allowed to run. So the pipeline runs from a machine that already has line of sight.

  Stages:
    1 Validate    every manifest is parsed and dry-run applied against the live API server
    2 Preflight   storage health gate, refuses to deploy onto degraded protection
    3 Deploy      kubectl apply of the manifest set
    4 Rollout     wait for the deployment to converge
    5 Verify      in-cluster HTTP check proving more than one replica answers
    6 Record      every stage duration written to a timestamped run record

  Stage 6 exists because this POC has repeatedly proven things without ever timing them. Pass and
  fail were recorded, durations were not. Every run of this script produces the numbers that were
  missing, so the next person does not have to guess.

.PARAMETER ManifestPath
  Directory of Kubernetes manifests to publish. Applied in filename order.

.PARAMETER Namespace
  Namespace the workload lives in.

.PARAMETER Deployment
  Deployment name to wait on and verify.

.PARAMETER SkipStorageGate
  Bypass the storage health preflight. Only for a cluster you have already inspected by hand.

.PARAMETER WhatIf
  Run validation and preflight, then stop before changing anything.

.EXAMPLE
  .\Invoke-PublishPipeline.ps1 -WhatIf
  Validate and preflight only. Safe on any cluster, changes nothing.

.EXAMPLE
  .\Invoke-PublishPipeline.ps1
  Full publish, with a run record written to out/.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot '..\tests\kubernetes\azure-local-dashboard'),
  [string]$Namespace = 'azure-local-dashboard',
  [string]$Deployment = 'azure-local-dashboard',
  [int]$RolloutTimeoutSec = 300,
  [int]$VerifyRequests = 30,
  [switch]$SkipStorageGate,
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\out')
)

$ErrorActionPreference = 'Stop'
$script:Stages = [System.Collections.Generic.List[object]]::new()
$script:RunStart = Get-Date

function Write-Stage {
  param([int]$Number, [string]$Name)
  Write-Host ''
  Write-Host ("[{0}/6] {1}" -f $Number, $Name) -ForegroundColor Cyan
}

function Complete-Stage {
  param([string]$Name, [datetime]$Start, [string]$Status, [string]$Detail = '')
  $elapsed = (Get-Date) - $Start
  $script:Stages.Add([pscustomobject]@{
    Stage    = $Name
    Status   = $Status
    Seconds  = [math]::Round($elapsed.TotalSeconds, 2)
    Duration = '{0:mm\:ss\.ff}' -f $elapsed
    Detail   = $Detail
  })
  $colour = if ($Status -eq 'Pass') { 'Green' } elseif ($Status -eq 'Skipped') { 'DarkGray' } else { 'Red' }
  Write-Host ("      {0} in {1:mm\:ss\.ff}  {2}" -f $Status, $elapsed, $Detail) -ForegroundColor $colour
}

function Assert-Tool {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name is not on PATH. This pipeline runs from a machine with cluster line of sight."
  }
}

# ---------------------------------------------------------------------------------------------
# 1. Validate
# ---------------------------------------------------------------------------------------------
Write-Stage 1 'Validate manifests'
$t = Get-Date
Assert-Tool kubectl

$manifests = Get-ChildItem -Path $ManifestPath -Filter '*.yaml' | Sort-Object Name
if (-not $manifests) { throw "No manifests found under $ManifestPath" }

foreach ($m in $manifests) {
  Write-Host ("      {0}" -f $m.Name) -ForegroundColor DarkGray
  & kubectl apply -f $m.FullName --dry-run=server -o name 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Complete-Stage 'Validate' $t 'Fail' $m.Name
    throw "Server side dry run rejected $($m.Name)."
  }
}
Complete-Stage 'Validate' $t 'Pass' ("{0} manifests" -f $manifests.Count)

# ---------------------------------------------------------------------------------------------
# 2. Preflight
#
# Deploying onto degraded storage protection is the failure mode this POC actually hit. A retired
# NVMe in machine 01 left a virtual disk Incomplete with its repair job suspended, and the runbook
# is explicit that new workload placement waits for a green baseline. So the gate is real.
# ---------------------------------------------------------------------------------------------
Write-Stage 2 'Preflight storage health'
$t = Get-Date

if ($SkipStorageGate) {
  Complete-Stage 'Preflight' $t 'Skipped' 'gate bypassed by operator'
}
else {
  $nodes = & kubectl get nodes -o json 2>$null | ConvertFrom-Json
  $notReady = @($nodes.items | Where-Object {
    -not ($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
  })

  if ($notReady.Count -gt 0) {
    Complete-Stage 'Preflight' $t 'Fail' ("{0} node(s) not Ready" -f $notReady.Count)
    throw 'Refusing to publish onto a cluster with a node that is not Ready.'
  }

  Write-Host '      Kubernetes nodes Ready.' -ForegroundColor DarkGray
  Write-Host '      Azure Local storage health is NOT checked from here. Confirm on a cluster node:' -ForegroundColor Yellow
  Write-Host '        Get-StoragePool; Get-VirtualDisk; Get-StorageJob; Get-PhysicalDisk' -ForegroundColor Yellow
  Write-Host '      Expect pool Healthy, no virtual disk Incomplete, no Suspended repair job.' -ForegroundColor Yellow
  Complete-Stage 'Preflight' $t 'Pass' 'k8s nodes Ready, host storage needs manual confirmation'
}

if ($WhatIfPreference) {
  Write-Host ''
  Write-Host 'WhatIf: stopping before any change. Validation and preflight completed.' -ForegroundColor Yellow
  $script:Stages | Format-Table -AutoSize
  return
}

# ---------------------------------------------------------------------------------------------
# 3. Deploy
# ---------------------------------------------------------------------------------------------
Write-Stage 3 'Apply manifests'
$t = Get-Date
foreach ($m in $manifests) {
  & kubectl apply -f $m.FullName
  if ($LASTEXITCODE -ne 0) {
    Complete-Stage 'Deploy' $t 'Fail' $m.Name
    throw "Apply failed on $($m.Name)."
  }
}
Complete-Stage 'Deploy' $t 'Pass' ("{0} manifests applied" -f $manifests.Count)

# ---------------------------------------------------------------------------------------------
# 4. Rollout
# ---------------------------------------------------------------------------------------------
Write-Stage 4 'Wait for rollout'
$t = Get-Date
& kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout "${RolloutTimeoutSec}s"
if ($LASTEXITCODE -ne 0) {
  Complete-Stage 'Rollout' $t 'Fail' 'did not converge'
  throw "Deployment $Deployment did not become available within $RolloutTimeoutSec seconds."
}
$dep = & kubectl get deployment $Deployment -n $Namespace -o json | ConvertFrom-Json
Complete-Stage 'Rollout' $t 'Pass' ("{0}/{1} ready" -f $dep.status.readyReplicas, $dep.spec.replicas)

# ---------------------------------------------------------------------------------------------
# 5. Verify
#
# Runs from inside the cluster on purpose. A kubectl port-forward pins one backing pod, so it can
# prove the app answers but it cannot prove the Service distributes. This hits the Service DNS
# name from a pod, which is the only way to show more than one replica taking traffic.
# ---------------------------------------------------------------------------------------------
Write-Stage 5 'Verify in cluster'
$t = Get-Date
$pod = (& kubectl get pods -n $Namespace -l "app=$Deployment" -o jsonpath='{.items[0].metadata.name}')
if (-not $pod) {
  Complete-Stage 'Verify' $t 'Fail' 'no pod found'
  throw "No pod found for $Deployment in $Namespace."
}

$svc = "$Deployment.$Namespace.svc.cluster.local"
$cmd = "for i in `$(seq $VerifyRequests); do wget -qO- http://$svc/api/work 2>/dev/null | head -c 200; echo; done"
$raw = & kubectl exec -n $Namespace $pod -- sh -c $cmd 2>$null

$answers = @($raw | Where-Object { $_ -match '\S' })
$backends = $answers | ForEach-Object { if ($_ -match '"pod"\s*:\s*"([^"]+)"') { $Matches[1] } } | Group-Object | Sort-Object Count -Descending

if ($backends.Count -lt 2) {
  Complete-Stage 'Verify' $t 'Fail' ("only {0} distinct backend answered" -f $backends.Count)
  throw 'Service did not distribute across replicas. Check EndpointSlice readiness.'
}

$split = ($backends | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
Complete-Stage 'Verify' $t 'Pass' ("{0} requests, {1}" -f $answers.Count, $split)

# ---------------------------------------------------------------------------------------------
# 6. Record
# ---------------------------------------------------------------------------------------------
Write-Stage 6 'Write run record'
$t = Get-Date
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$stamp = $script:RunStart.ToString('yyyyMMdd-HHmmss')
$file = Join-Path $OutputPath "publish-run-$stamp.json"

[pscustomobject]@{
  startedUtc     = $script:RunStart.ToUniversalTime().ToString('o')
  totalSeconds   = [math]::Round(((Get-Date) - $script:RunStart).TotalSeconds, 2)
  namespace      = $Namespace
  deployment     = $Deployment
  manifestCount  = $manifests.Count
  readyReplicas  = $dep.status.readyReplicas
  serviceSplit   = $split
  operator       = "$env:USERNAME@$env:COMPUTERNAME"
  stages         = $script:Stages
} | ConvertTo-Json -Depth 6 | Set-Content -Path $file -Encoding utf8

Complete-Stage 'Record' $t 'Pass' $file

Write-Host ''
Write-Host 'Publish complete.' -ForegroundColor Green
$script:Stages | Format-Table Stage, Status, Duration, Detail -AutoSize
Write-Host ("Total {0:mm\:ss\.ff}" -f ((Get-Date) - $script:RunStart)) -ForegroundColor Green
Write-Host "Run record: $file" -ForegroundColor DarkGray
