<#
.SYNOPSIS
  Runs the minimum AKS-on-Azure-Local POC smoke test.

.DESCRIPTION
  Uses the active kubectl context to prove the AKS layer can schedule,
  expose, scale, and self-heal a simple workload. This script is intended
  for after the Azure Local cluster and AKS cluster exist. It does not
  create the AKS cluster.

  The default image is hosted on Microsoft Container Registry so the test
  exercises an endpoint already present in the Azure Local firewall plan.

.EXAMPLE
  .\scripts\Invoke-AksSmokeValidation.ps1

.EXAMPLE
  .\scripts\Invoke-AksSmokeValidation.ps1 -ServiceType ClusterIP

.EXAMPLE
  .\scripts\Invoke-AksSmokeValidation.ps1 -Cleanup
#>

[CmdletBinding()]
param(
  [string]$Namespace = 'azloc-poc-smoke',
  [string]$Name = 'hello-azloc',
  [string]$Image = 'mcr.microsoft.com/azuredocs/aci-helloworld:latest',
  [ValidateSet('LoadBalancer','ClusterIP','NodePort')]
  [string]$ServiceType = 'LoadBalancer',
  [ValidateRange(1,10)]
  [int]$Replicas = 2,
  [ValidateRange(60,900)]
  [int]$TimeoutSeconds = 300,
  [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$outDir = Join-Path $repoRoot 'out'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $outDir "_aks-smoke-$timestamp.txt"

function Write-Step($message) { Write-Host "`n[*] $message" -ForegroundColor Cyan }
function Write-Ok($message) { Write-Host "    OK: $message" -ForegroundColor Green }
function Write-WarnLine($message) { Write-Host "    WARN: $message" -ForegroundColor Yellow }

function Invoke-Kubectl {
  param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)
  $output = & kubectl @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    $text = ($output | Out-String).Trim()
    throw "kubectl $($Arguments -join ' ') failed: $text"
  }
  $output
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
  throw 'kubectl was not found in PATH. Install kubectl and select the AKS kubeconfig before running this script.'
}

$log = [System.Collections.Generic.List[string]]::new()
function Add-Log($line) {
  $log.Add($line)
  $line | Write-Host
}

if ($Cleanup) {
  Write-Step "Deleting namespace $Namespace"
  & kubectl delete namespace $Namespace --ignore-not-found=true
  if ($LASTEXITCODE -ne 0) { throw "kubectl cleanup failed." }
  Write-Ok 'Cleanup requested and completed.'
  return
}

Write-Step 'Confirm kubectl context and cluster nodes'
$context = (Invoke-Kubectl -Arguments @('config', 'current-context') | Out-String).Trim()
$nodes = Invoke-Kubectl -Arguments @('get', 'nodes', '-o', 'wide')
Write-Ok "Context: $context"
$nodes | Out-String | Write-Host

Write-Step "Apply smoke workload in namespace $Namespace"
$manifest = @"
apiVersion: v1
kind: Namespace
metadata:
  name: $Namespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $Name
  namespace: $Namespace
  labels:
    app: $Name
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $Name
  template:
    metadata:
      labels:
        app: $Name
    spec:
      containers:
      - name: web
        image: $Image
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: $Name
  namespace: $Namespace
spec:
  type: $ServiceType
  selector:
    app: $Name
  ports:
  - name: http
    port: 80
    targetPort: 80
"@

$manifestPath = Join-Path $env:TEMP "azloc-aks-smoke-$timestamp.yaml"
$manifest | Out-File -FilePath $manifestPath -Encoding ascii -Force
try {
  Invoke-Kubectl -Arguments @('apply', '-f', $manifestPath) | Write-Host
} finally {
  Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
}

Invoke-Kubectl -Arguments @('-n', $Namespace, 'rollout', 'status', "deployment/$Name", '--timeout', "${TimeoutSeconds}s") | Write-Host
Write-Ok 'Initial deployment is ready.'

Write-Step "Scale workload to $Replicas replicas"
Invoke-Kubectl -Arguments @('-n', $Namespace, 'scale', 'deployment', $Name, '--replicas', $Replicas) | Write-Host
Invoke-Kubectl -Arguments @('-n', $Namespace, 'rollout', 'status', "deployment/$Name", '--timeout', "${TimeoutSeconds}s") | Write-Host
Write-Ok 'Scaled deployment is ready.'

Write-Step 'Delete one pod and confirm Kubernetes recreates it'
$firstPod = (Invoke-Kubectl -Arguments @('-n', $Namespace, 'get', 'pods', '-l', "app=$Name", '-o', "jsonpath={.items[0].metadata.name}") | Out-String).Trim()
if ($firstPod) {
  Invoke-Kubectl -Arguments @('-n', $Namespace, 'delete', 'pod', $firstPod) | Write-Host
  Invoke-Kubectl -Arguments @('-n', $Namespace, 'rollout', 'status', "deployment/$Name", '--timeout', "${TimeoutSeconds}s") | Write-Host
  Write-Ok "Deleted pod $firstPod and deployment returned to ready."
} else {
  Write-WarnLine 'No pod name found to delete; skipping pod-recreation check.'
}

Write-Step 'Capture service and endpoint evidence'
$svcWide = Invoke-Kubectl -Arguments @('-n', $Namespace, 'get', 'service', $Name, '-o', 'wide')
$podsWide = Invoke-Kubectl -Arguments @('-n', $Namespace, 'get', 'pods', '-l', "app=$Name", '-o', 'wide')
$events = Invoke-Kubectl -Arguments @('-n', $Namespace, 'get', 'events', '--sort-by=.lastTimestamp')

$serviceJson = Invoke-Kubectl -Arguments @('-n', $Namespace, 'get', 'service', $Name, '-o', 'json') | ConvertFrom-Json
$ingress = @($serviceJson.status.loadBalancer.ingress)
$url = $null
if ($ServiceType -eq 'LoadBalancer' -and $ingress.Count -gt 0) {
  $address = if ($ingress[0].ip) { $ingress[0].ip } else { $ingress[0].hostname }
  if ($address) { $url = "http://$address/" }
}

$httpResult = 'not-tested'
if ($url) {
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    $httpResult = "HTTP $($response.StatusCode) from $url"
    Write-Ok $httpResult
  } catch {
    $httpResult = "HTTP probe failed for $url : $($_.Exception.Message.Split("`n")[0])"
    Write-WarnLine $httpResult
  }
} elseif ($ServiceType -eq 'LoadBalancer') {
  Write-WarnLine 'LoadBalancer service has no external IP/hostname yet. Check VIP pool and service controller after this run.'
}

Add-Log "Azure Local AKS smoke validation"
Add-Log "Timestamp:  $timestamp"
Add-Log "Context:    $context"
Add-Log "Namespace:  $Namespace"
Add-Log "Workload:   $Name"
Add-Log "Image:      $Image"
Add-Log "Service:    $ServiceType"
Add-Log "Replicas:   $Replicas"
Add-Log "HTTP:       $httpResult"
Add-Log ''
Add-Log 'Nodes:'
$nodes | ForEach-Object { Add-Log $_ }
Add-Log ''
Add-Log 'Service:'
$svcWide | ForEach-Object { Add-Log $_ }
Add-Log ''
Add-Log 'Pods:'
$podsWide | ForEach-Object { Add-Log $_ }
Add-Log ''
Add-Log 'Recent namespace events:'
$events | ForEach-Object { Add-Log $_ }

$log | Set-Content -Path $reportPath -Encoding ascii
Write-Host "`nSaved: $reportPath" -ForegroundColor Green