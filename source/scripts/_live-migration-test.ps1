<#
.SYNOPSIS
  Live migration capability check. Measures workload blackout while a VM moves between hosts.

.DESCRIPTION
  This is the other half of the VMSS patching question.

  scripts\_rolling-update-test.ps1 covers the container layer. It replaces every pod of a
  workload without the service losing an endpoint. That answers "patch the application".

  This covers the machine layer. It live migrates a running VM from one Azure Local node to
  another and measures how long, if at all, the VM stops answering. That answers "patch the
  host underneath the application", which is what Cluster-Aware Updating does on every node in
  turn during an Azure Local update.

  Microsoft states the intent plainly:
    "When updating Azure Local, the process live migrates virtual machines between cluster
     member machines to ensure workloads don't experience any downtime."
    https://learn.microsoft.com/azure/azure-local/update/update-settings

  This measures whether that holds on this hardware.

.NOTES
  NOT read-only. Live migrates a running VM. Reversible by migrating back, and -ReturnHome
  does that automatically.

  Default target is the AKS worker VM, because it hosts the dashboard pods and is therefore
  the only migration on this cluster that demonstrates a workload surviving a host move.
  That also makes it the highest impact choice if the migration fails. Pick a different -VMName
  if you want a lower stakes run.

.EXAMPLE
  .\scripts\_live-migration-test.ps1 -K8sNode 'your-worker-node' -WhatIfOnly
  Shows what it would do, touches nothing.

.EXAMPLE
  .\scripts\_live-migration-test.ps1 -K8sNode 'your-worker-node' -ReturnHome
  Migrates the worker VM to another node, measures, then migrates it back.

.PARAMETER K8sNode
  Actual worker node in your authorized cluster, as listed by kubectl get nodes.
  Required so availability is not measured against a fictional example name.
#>
[CmdletBinding()]
param(
  # Defaults to the AKS worker VM. Discovered at runtime if left empty.
  [string] $VMName        = '',
  [string] $TargetNode    = '',
  [string] $ClusterHost   = 'azl-node-01.lab.example.com',
  [string] $CredFile      = '.\.creds\sim-example-internal-admin.cred',
  [string] $CredUser      = 'sim\labadmin',

  # ICMP is filtered from the workstation to the lab subnet, so availability is observed through
  # the Kubernetes API instead. The API server runs on the control plane VM on a different host,
  # so it is unaffected by migrating the worker.
  [string] $Kubeconfig    = "$env:USERPROFILE\.kube\aksarc-admin",
  [string] $Namespace     = 'azure-local-dashboard',
  [string] $Service       = 'azure-local-dashboard',
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string] $K8sNode,
  [int]    $ProbeSeconds  = 120,
  [switch] $ReturnHome,
  [switch] $WhatIfOnly
)

$ErrorActionPreference = 'Stop'

$pw   = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
$cred = [pscredential]::new($CredUser, $pw)

function Invoke-Node {
  param([scriptblock]$sb, [object[]]$Arguments)
  $p = @{ ComputerName = $ClusterHost; Credential = $cred; Authentication = 'Negotiate'; ScriptBlock = $sb }
  # -ArgumentList $null passes a literal null and breaks parameterless scriptblocks.
  if ($Arguments) { $p.ArgumentList = $Arguments }
  Invoke-Command @p
}

Write-Host "== discover ==" -ForegroundColor Cyan

$sbVms = {
  Get-ClusterGroup | Where-Object GroupType -eq 'VirtualMachine' |
    Select-Object Name, @{n='Owner';e={$_.OwnerNode.Name}}, State
}
$vms = @(Invoke-Command -ComputerName $ClusterHost -Credential $cred -Authentication Negotiate -ScriptBlock $sbVms)

if ($vms.Count -eq 0) { throw "No clustered VMs returned from $ClusterHost. Check WinRM and credentials." }

# ClusterGroupState arrives from the remote session as Int32, not as an enum name.
function Get-StateName { param($s) switch ([int]$s) { 0 {'Online'} 1 {'Offline'} 2 {'Failed'} 3 {'PartialOnline'} 4 {'Pending'} default {"State$s"} } }

$vms | ForEach-Object { '  {0,-14} {1,-9} {2}' -f $_.Owner, (Get-StateName $_.State), $_.Name }

if (-not $VMName) {
  $VMName = ($vms | Where-Object { $_.Name -like '*nodepool1*' -and [int]$_.State -eq 0 } |
             Select-Object -First 1).Name
}
if (-not $VMName) { throw 'No online worker VM found. Pass -VMName explicitly.' }

$current = ($vms | Where-Object Name -eq $VMName).Owner
$sbNodes = { Get-ClusterNode | Where-Object { [int]$_.State -eq 0 } | Select-Object -Expand Name }
$nodes   = @(Invoke-Command -ComputerName $ClusterHost -Credential $cred -Authentication Negotiate -ScriptBlock $sbNodes)

if (-not $TargetNode) {
  $TargetNode = $nodes | Where-Object { $_ -ne $current } | Select-Object -First 1
}

Write-Host "`nVM      : $VMName"
Write-Host "from    : $current"
Write-Host "to      : $TargetNode"
Write-Host "probe   : k8s api, endpoints for $Service and Ready on $K8sNode"

if ($WhatIfOnly) { Write-Host "`nWhatIfOnly set. Nothing was changed." -ForegroundColor Yellow; return }

# Ping runs in a job so the migration and the probe overlap.
Write-Host "`n== migrating ==" -ForegroundColor Cyan
$probe = Start-Job -ScriptBlock {
  param($kubeconfig, $ns, $svc, $node, $seconds)
  $env:KUBECONFIG = $kubeconfig
  # Emit each sample as it is taken. Accumulating and returning at the end loses everything
  # if the job is stopped before the loop finishes.
  $end = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $end) {
    $t = Get-Date
    $ready = -1
    $raw = kubectl -n $ns get endpointslice -l "kubernetes.io/service-name=$svc" -o json 2>$null
    if ($raw) {
      $j = $raw | ConvertFrom-Json
      $ready = 0
      foreach ($s in $j.items) { foreach ($e in $s.endpoints) { if ($e.conditions.ready -eq $true) { $ready++ } } }
    }
    $nr = kubectl get node $node -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>$null
    [pscustomobject]@{ at = $t; ready = $ready; node = "$nr" }
  }
} -ArgumentList $Kubeconfig, $Namespace, $Service, $K8sNode, $ProbeSeconds

Start-Sleep -Seconds 3
$sw = [Diagnostics.Stopwatch]::StartNew()
Invoke-Node { param($n, $t) Move-ClusterVirtualMachineRole -Name $n -Node $t -MigrationType Live | Out-Null } @($VMName, $TargetNode)
$sw.Stop()
Write-Host ("live migration returned after {0:N1}s" -f $sw.Elapsed.TotalSeconds)

Start-Sleep -Seconds 4
$samples = @(Receive-Job $probe)
Stop-Job $probe -ErrorAction SilentlyContinue | Out-Null
$samples += @(Receive-Job $probe -ErrorAction SilentlyContinue)
Remove-Job $probe -Force -ErrorAction SilentlyContinue | Out-Null

if ($samples.Count -eq 0) {
  Write-Host "`nPROBE COLLECTED NOTHING. Migration may have succeeded but availability was not measured." -ForegroundColor Red
}

$bad     = @($samples | Where-Object { $_.ready -lt 1 -or $_.node -ne 'True' })
$minRdy  = if ($samples.Count) { ($samples | Measure-Object -Property ready -Minimum).Minimum } else { -1 }
$notRdy  = @($samples | Where-Object { $_.node -ne 'True' }).Count
$gap     = 0.0
if ($bad.Count -gt 0) {
  $gap = ([datetime]($bad[-1].at) - [datetime]($bad[0].at)).TotalSeconds
}

$after = (Invoke-Command -ComputerName $ClusterHost -Credential $cred -Authentication Negotiate -ScriptBlock $sbVms |
  Where-Object Name -eq $VMName)

Write-Host "`n== result ==" -ForegroundColor Green
Write-Host ("migration call     : {0:N1}s" -f $sw.Elapsed.TotalSeconds)
Write-Host ("now owned by       : {0} ({1})" -f $after.Owner, (Get-StateName $after.State))
Write-Host ("api samples        : {0}" -f $samples.Count)
Write-Host ("min ready endpoints: {0}" -f $minRdy)
Write-Host ("node not Ready in  : {0} samples" -f $notRdy)
Write-Host ("disturbed window   : {0:N1}s" -f $gap)
Write-Host ("workload survived  : {0}" -f $(if ($samples.Count -eq 0) { 'NOT MEASURED' } elseif ($bad.Count -eq 0) { 'YES, Kubernetes never saw a disruption' } else { 'SEE TRACE' }))

if ($samples.Count) {
  $trace = ($samples | ForEach-Object { "{0:HH:mm:ss}|r{1}|{2}" -f $_.at, $_.ready, $_.node }) -join '  '
  Write-Host "`ntrace (time|readyEndpoints|nodeReady):`n$trace"
}

if ($ReturnHome) {
  Write-Host "`n== returning to $current ==" -ForegroundColor Cyan
  Invoke-Node { param($n, $t) Move-ClusterVirtualMachineRole -Name $n -Node $t -MigrationType Live | Out-Null } @($VMName, $current)
  $back = (Invoke-Command -ComputerName $ClusterHost -Credential $cred -Authentication Negotiate -ScriptBlock $sbVms |
    Where-Object Name -eq $VMName)
  Write-Host ("now owned by       : {0} ({1})" -f $back.Owner, (Get-StateName $back.State))
}
