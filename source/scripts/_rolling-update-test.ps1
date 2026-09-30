<#
.SYNOPSIS
  Rolling update capability check for the Azure Local POC.

.DESCRIPTION
  The original acceptance criteria asked for VM Scale Sets, and the recorded reason was a more
  manageable security and patching posture rather than demand scaling. Azure Local has no VMSS
  resource, so this measures whether the equivalent outcome is reachable: replace every running
  instance of a workload without the service losing all its endpoints.

  Samples ready endpoint count continuously while a rolling restart runs. The result is the
  minimum ready count observed. Anything above zero means the service stayed answerable
  throughout.

  Read-only apart from the rollout restart itself, which is reversible and self healing.
#>
[CmdletBinding()]
param(
  [string] $Namespace  = 'azure-local-dashboard',
  [string] $Deployment = 'azure-local-dashboard',
  [string] $Service    = 'azure-local-dashboard',
  [int]    $SampleMs   = 250,
  [int]    $TimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
$started = Get-Date

function Get-ReadyCount {
  param($ns, $svc)
  $raw = kubectl -n $ns get endpointslice -l "kubernetes.io/service-name=$svc" -o json 2>$null
  if (-not $raw) { return -1 }
  $j = $raw | ConvertFrom-Json
  $n = 0
  foreach ($slice in $j.items) {
    foreach ($ep in $slice.endpoints) {
      if ($ep.conditions.ready -eq $true) { $n++ }
    }
  }
  return $n
}

Write-Host "== before ==" -ForegroundColor Cyan
kubectl -n $Namespace get deploy $Deployment -o wide
$beforePods = (kubectl -n $Namespace get pods -l "app.kubernetes.io/name=$Service" -o jsonpath='{.items[*].metadata.name}') -split ' '
Write-Host ("pods: " + ($beforePods -join ', '))
Write-Host ("ready endpoints: " + (Get-ReadyCount $Namespace $Service))

# Sampler runs in this session rather than a job, so kubectl context and PATH are inherited.
$samples = New-Object System.Collections.ArrayList
$sw = [Diagnostics.Stopwatch]::StartNew()

Write-Host "`n== rolling restart ==" -ForegroundColor Cyan
kubectl -n $Namespace rollout restart deployment/$Deployment | Out-Host

$rollout = Start-Job -ScriptBlock {
  param($ns, $dep, $kubeconfig)
  $env:KUBECONFIG = $kubeconfig
  kubectl -n $ns rollout status deployment/$dep --timeout=170s 2>&1
} -ArgumentList $Namespace, $Deployment, $env:KUBECONFIG

while ($rollout.State -eq 'Running' -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
  $n = Get-ReadyCount $Namespace $Service
  [void]$samples.Add([pscustomobject]@{ t = [math]::Round($sw.Elapsed.TotalSeconds, 2); ready = $n })
  Start-Sleep -Milliseconds $SampleMs
}

# A few trailing samples, because the last old pod can leave just after rollout status returns.
for ($i = 0; $i -lt 8; $i++) {
  $n = Get-ReadyCount $Namespace $Service
  [void]$samples.Add([pscustomobject]@{ t = [math]::Round($sw.Elapsed.TotalSeconds, 2); ready = $n })
  Start-Sleep -Milliseconds $SampleMs
}

$sw.Stop()
$statusOut = Receive-Job $rollout -Wait -AutoRemoveJob
Write-Host ($statusOut | Out-String).Trim()

$valid  = $samples | Where-Object { $_.ready -ge 0 }
$minRdy = ($valid | Measure-Object -Property ready -Minimum).Minimum
$maxRdy = ($valid | Measure-Object -Property ready -Maximum).Maximum

Write-Host "`n== after ==" -ForegroundColor Cyan
kubectl -n $Namespace get deploy $Deployment -o wide
$afterPods = (kubectl -n $Namespace get pods -l "app.kubernetes.io/name=$Service" -o jsonpath='{.items[*].metadata.name}') -split ' '
Write-Host ("pods: " + ($afterPods -join ', '))

$replaced = @($afterPods | Where-Object { $beforePods -notcontains $_ }).Count

Write-Host "`n== result ==" -ForegroundColor Green
Write-Host ("elapsed            : {0:N1}s" -f $sw.Elapsed.TotalSeconds)
Write-Host ("samples            : {0} at {1}ms" -f $valid.Count, $SampleMs)
Write-Host ("ready endpoints min: {0}" -f $minRdy)
Write-Host ("ready endpoints max: {0}" -f $maxRdy)
Write-Host ("pods replaced      : {0} of {1}" -f $replaced, $beforePods.Count)
Write-Host ("service stayed up  : {0}" -f $(if ($minRdy -ge 1) { 'YES' } else { 'NO' }))

$trace = ($valid | ForEach-Object { "$($_.t)s=$($_.ready)" }) -join '  '
Write-Host "`nready trace:`n$trace"
Write-Host ("`nstarted {0}" -f $started.ToString('yyyy-MM-dd HH:mm:ss'))
