<#
.SYNOPSIS
  Live status of everything actually running on the Azure Local cluster. Read only.

.DESCRIPTION
  The project could demonstrate that things worked once. It could not answer "what is running
  right now" without a research session. This answers that question in one command.

  Every section is independent and fails loudly. If a check cannot run you get COULD NOT CHECK
  with the reason, never a silent pass. A status board that hides its own blind spots is worse
  than no board, because it converts ignorance into false confidence.

  Five surfaces, because that is what the project actually consists of:
    1. Azure control plane   the cluster resource, billing model, trial clock
    2. Physical cluster      four nodes, storage pool, virtual disk health
    3. Arc virtual machines  power state of every VM the cluster hosts
    4. Docker host           containers on rocky-docker-01
    5. Kubernetes            AKS Arc nodes and the dashboard workload

.PARAMETER Html
  Also write an HTML page and open it. Useful when you want a glance rather than a scroll.

.PARAMETER SkipAzure
  Skip anything needing the Azure control plane, for when PIM has expired and you only care
  about what is on the wire.

.EXAMPLE
  .\Get-PocStatus.ps1

.EXAMPLE
  .\Get-PocStatus.ps1 -Html

.NOTES
  Read only. No writes, no state changes, safe to run during a presentation.
  Needs: az login, .creds\sim-example-internal-admin.cred, .creds\poc-vm-key, out\tools\kubectl.exe
#>

[CmdletBinding()]
param(
  [switch] $Html,
  [switch] $SkipAzure
)

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$rg   = 'rg-azlocal-poc-001'
$py   = Join-Path (Split-Path (Split-Path (Get-Command az -ErrorAction SilentlyContinue).Source)) 'python.exe'
$sections = [System.Collections.Generic.List[object]]::new()

function Add-Section {
  param([string]$Name, [string]$State, [object[]]$Rows, [string]$Problem)
  $sections.Add([pscustomobject]@{ Name = $Name; State = $State; Rows = $Rows; Problem = $Problem })
}

function Write-Head {
  param([string]$Text, [string]$State)
  $colour = switch ($State) { 'OK' { 'Green' } 'DEGRADED' { 'Yellow' } 'UNKNOWN' { 'DarkGray' } default { 'Red' } }
  Write-Host ''
  Write-Host ("  " + $Text.PadRight(34)) -NoNewline
  Write-Host $State -ForegroundColor $colour
  Write-Host ("  " + ('-' * 58)) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '  AZURE LOCAL POC - WHAT IS RUNNING RIGHT NOW' -ForegroundColor Cyan
Write-Host ("  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')) -ForegroundColor DarkGray

# ---------- 1. Azure control plane ----------
if ($SkipAzure) {
  Add-Section 'Azure control plane' 'UNKNOWN' @() 'skipped by -SkipAzure'
} else {
  try {
    $raw = & $py -m azure.cli resource show -g $rg -n AZL-CLUSTER-01 `
      --resource-type Microsoft.AzureStackHCI/clusters -o json --only-show-errors 2>&1 | Out-String
    if ($raw -match 'ERROR|AuthorizationFailed') { throw ($raw -split "`n" | Select-Object -First 1) }
    $c = $raw | ConvertFrom-Json
    $trial = $c.properties.trialDaysRemaining
    $rows = @(
      [pscustomobject]@{ Item = 'Cluster'; Value = $c.name; Note = $c.properties.status }
      [pscustomobject]@{ Item = 'Billing'; Value = $c.properties.billingModel
                         Note = if ($trial) { "$trial trial days left" } else { '' } }
      [pscustomobject]@{ Item = 'Nodes reporting'; Value = $c.properties.reportedProperties.nodes.Count; Note = '' }
    )
    $state = if ($c.properties.status -like 'Connected*') { 'OK' } else { 'DEGRADED' }
    Add-Section 'Azure control plane' $state $rows $null
  } catch {
    Add-Section 'Azure control plane' 'UNKNOWN' @() ("$_" -replace '\s+', ' ')
  }
}

# ---------- 2. Physical cluster ----------
$credFile = Join-Path $root '.creds\sim-example-internal-admin.cred'
try {
  if (-not (Test-Path $credFile)) { throw "credential file missing: $credFile" }
  $pw   = ConvertTo-SecureString ((Get-Content $credFile -Raw).Trim())
  $cred = [pscredential]::new('sim\labadmin', $pw)
  $data = Invoke-Command -ComputerName 'azl-node-01.lab.example.com' -Credential $cred `
    -Authentication Negotiate -ErrorAction Stop -ScriptBlock {
      $pool = Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -ne 'Primordial' }
      [pscustomobject]@{
        Nodes = Get-ClusterNode | ForEach-Object { [pscustomobject]@{ n = $_.Name; s = "$($_.State)" } }
        Pool  = if ($pool) { [pscustomobject]@{ h = "$($pool.HealthStatus)"; o = "$($pool.OperationalStatus)"
                  free = [math]::Round(($pool.Size - $pool.AllocatedSize)/1TB, 2) } } else { $null }
        Disks = Get-VirtualDisk -ErrorAction SilentlyContinue | ForEach-Object {
                  [pscustomobject]@{ n = $_.FriendlyName; h = "$($_.HealthStatus)"; o = "$($_.OperationalStatus)" } }
        Phys  = (Get-StoragePool -ErrorAction SilentlyContinue |
                  Where-Object { $_.FriendlyName -ne 'Primordial' } |
                  Get-PhysicalDisk -ErrorAction SilentlyContinue).Count
      }
    }
  $down    = @($data.Nodes | Where-Object { $_.s -ne 'Up' })
  $badDisk = @($data.Disks | Where-Object { $_.h -ne 'Healthy' })
  $rows = @(
    [pscustomobject]@{ Item = 'Cluster nodes'
                       Value = "$(($data.Nodes | Where-Object { $_.s -eq 'Up' }).Count) of $($data.Nodes.Count) Up"
                       Note = if ($down) { 'DOWN: ' + ($down.n -join ', ') } else { ($data.Nodes.n -join ', ') } }
    [pscustomobject]@{ Item = 'Storage pool'; Value = $data.Pool.h; Note = "$($data.Pool.free) TB free" }
    [pscustomobject]@{ Item = 'Virtual disks'
                       Value = "$(($data.Disks | Where-Object { $_.h -eq 'Healthy' }).Count) of $($data.Disks.Count) Healthy"
                       Note = if ($badDisk) { 'CHECK: ' + ($badDisk.n -join ', ') } else { '' } }
    [pscustomobject]@{ Item = 'Disks in pool'; Value = $data.Phys; Note = '11 expected, one NVMe retired' }
  )
  $state = if ($down -or $badDisk -or $data.Pool.h -ne 'Healthy') { 'DEGRADED' } else { 'OK' }
  Add-Section 'Physical cluster' $state $rows $null
} catch {
  Add-Section 'Physical cluster' 'UNKNOWN' @() ("$_" -replace '\s+', ' ')
}

# ---------- 3. Arc virtual machines ----------
if (-not $SkipAzure) {
  try {
    $raw = & $py -m azure.cli stack-hci-vm list -g $rg -o json --only-show-errors 2>&1 | Out-String
    if ($raw -match '^ERROR') { throw ($raw -split "`n" | Select-Object -First 1) }
    $vms = $raw | ConvertFrom-Json
    # list nests the instance under properties.properties, unlike show. Fall back either way.
    $rows = foreach ($v in $vms) {
      $inst = if ($v.properties.properties) { $v.properties.properties } else { $v.properties }
      [pscustomobject]@{ Item  = $v.name
                         Value = if ($inst.status.powerState) { $inst.status.powerState } else { 'unknown' }
                         Note  = $v.provisioningState }
    }
    $off = @($rows | Where-Object { $_.Value -ne 'Running' })
    $vmState = if ($off) { 'DEGRADED' } else { 'OK' }
    Add-Section 'Arc virtual machines' $vmState @($rows) $null
  } catch {
    Add-Section 'Arc virtual machines' 'UNKNOWN' @() ("$_" -replace '\s+', ' ')
  }
}

# ---------- 4. Docker host ----------
$key = Join-Path $root '.creds\poc-vm-key'
try {
  if (-not (Test-Path $key)) { throw "ssh key missing: $key" }
  $out = & ssh -i $key -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=15 `
    azureuser@10.10.1.208 "docker ps --format '{{.Names}}|{{.Status}}'; echo '##'; df -h --output=target,pcent /srv 2>/dev/null | tail -1" 2>&1 | Out-String
  if ($out -match 'Connection reset|refused|timed out|No route') { throw ($out -replace '\s+', ' ') }
  $parts = $out -split '##'
  $rows = foreach ($line in ($parts[0] -split "`r?`n" | Where-Object { $_ -match '\|' })) {
    $f = $line -split '\|'
    [pscustomobject]@{ Item = $f[0]; Value = if ($f[1] -match 'Up') { 'Up' } else { 'Down' }; Note = $f[1] }
  }
  if (-not $rows) { $rows = @([pscustomobject]@{ Item = '(no containers)'; Value = 'none'; Note = '' }) }
  $bad = @($rows | Where-Object { $_.Value -ne 'Up' })
  $dockerState = if ($bad) { 'DEGRADED' } else { 'OK' }
  Add-Section 'Docker host (rocky-docker-01)' $dockerState @($rows) $null
} catch {
  Add-Section 'Docker host (rocky-docker-01)' 'UNKNOWN' @() ("$_" -replace '\s+', ' ')
}

# ---------- 5. Kubernetes ----------
$kubectl = Join-Path $root 'out\tools\kubectl.exe'
$kubecfg = Join-Path $root 'out\aks-admin.kubeconfig'
try {
  if (-not (Test-Path $kubectl)) { throw "kubectl missing: $kubectl" }
  if (-not $SkipAzure) {
    # Refresh every run. A stale kubeconfig is exactly how this went unnoticed before.
    $null | & $py -m azure.cli aksarc get-credentials -g $rg -n azl-cluster-01-aks-01 --admin `
      --file $kubecfg --overwrite-existing --only-show-errors *> $null
  }
  if (-not (Test-Path $kubecfg)) { throw 'no kubeconfig, and -SkipAzure prevented fetching one' }
  $env:KUBECONFIG = $kubecfg
  $nodesRaw = & $kubectl get nodes --no-headers --request-timeout=20s 2>&1 | Out-String
  if ($nodesRaw -match 'Unable to connect|Forbidden|error') { throw ($nodesRaw -replace '\s+', ' ') }
  $nodeLines = @($nodesRaw -split "`r?`n" | Where-Object { $_.Trim() })
  $ready = @($nodeLines | Where-Object { $_ -match '\sReady\s' }).Count
  $depRaw = & $kubectl get deploy -A --no-headers --request-timeout=20s 2>&1 | Out-String
  $deps = @($depRaw -split "`r?`n" | Where-Object { $_.Trim() })
  $notReady = @($deps | Where-Object { $_ -match '\s(\d+)/(\d+)\s' -and $Matches[1] -ne $Matches[2] })
  $dash = @($deps | Where-Object { $_ -match 'azure-local-dashboard' })
  $rows = @(
    [pscustomobject]@{ Item = 'AKS nodes'; Value = "$ready of $($nodeLines.Count) Ready"; Note = '' }
    [pscustomobject]@{ Item = 'Deployments'
                       Value = "$($deps.Count - $notReady.Count) of $($deps.Count) fully available"
                       Note = if ($notReady) { 'CHECK: ' + (($notReady | ForEach-Object { ($_ -split '\s+')[1] }) -join ', ') } else { '' } }
    [pscustomobject]@{ Item = 'Dashboard workload'
                       Value = if ($dash) { ($dash[0] -split '\s+')[2] } else { 'ABSENT' }
                       Note  = if ($dash) { 'replicas ready/desired' } else { 'the hello world is not deployed' } }
  )
  $state = if (-not $dash -or $notReady -or $ready -lt $nodeLines.Count) { 'DEGRADED' } else { 'OK' }
  Add-Section 'Kubernetes (AKS Arc)' $state $rows $null
} catch {
  Add-Section 'Kubernetes (AKS Arc)' 'UNKNOWN' @() ("$_" -replace '\s+', ' ')
}

# ---------- render ----------
foreach ($s in $sections) {
  Write-Head $s.Name $s.State
  if ($s.Problem) {
    Write-Host "    COULD NOT CHECK: " -NoNewline -ForegroundColor Red
    Write-Host $s.Problem.Substring(0, [Math]::Min(180, $s.Problem.Length)) -ForegroundColor DarkGray
    continue
  }
  foreach ($r in $s.Rows) {
    Write-Host ("    {0,-22} {1,-26} " -f $r.Item, $r.Value) -NoNewline
    Write-Host $r.Note -ForegroundColor DarkGray
  }
}

$bad = @($sections | Where-Object { $_.State -ne 'OK' })
Write-Host ''
Write-Host ('  ' + ('=' * 58)) -ForegroundColor DarkGray
if ($bad) {
  Write-Host ("  ATTENTION: " + (($bad | ForEach-Object { "$($_.Name) [$($_.State)]" }) -join '  |  ')) -ForegroundColor Yellow
} else {
  Write-Host '  ALL FIVE SURFACES OK' -ForegroundColor Green
}
Write-Host ''

if ($Html) {
  $css = 'body{background:#0b0b0e;color:#ddd6cd;font:14px/1.5 Segoe UI,sans-serif;margin:0;padding:32px}' +
         'h1{font-size:19px;margin:0 0 4px}.t{color:#6f6a64;font-size:12px;margin-bottom:26px}' +
         'section{margin-bottom:22px}h2{font-size:13px;margin:0 0 8px;border-bottom:1px solid #26262e;padding-bottom:6px}' +
         '.s{float:right;font:11px monospace}.OK{color:#00c758}.DEGRADED{color:#edb200}.UNKNOWN{color:#7aa2e3}' +
         'table{border-collapse:collapse;width:100%}td{padding:4px 10px 4px 0;font-size:13px}' +
         'td.i{color:#a9a29a;width:220px}td.n{color:#6f6a64;font:11px monospace}' +
         '.err{color:#ff8a90;font:12px monospace}'
  $body = "<h1>Azure Local POC - what is running right now</h1><div class='t'>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')</div>"
  foreach ($s in $sections) {
    $body += "<section><h2>$($s.Name)<span class='s $($s.State)'>$($s.State)</span></h2>"
    if ($s.Problem) {
      $body += "<div class='err'>COULD NOT CHECK: $([System.Web.HttpUtility]::HtmlEncode($s.Problem))</div>"
    } else {
      $body += '<table>'
      foreach ($r in $s.Rows) {
        $body += "<tr><td class='i'>$($r.Item)</td><td>$($r.Value)</td><td class='n'>$($r.Note)</td></tr>"
      }
      $body += '</table>'
    }
    $body += '</section>'
  }
  $file = Join-Path $root 'out\poc-status.html'
  "<!doctype html><meta charset='utf-8'><title>POC status</title><style>$css</style>$body" |
    Set-Content -Path $file -Encoding utf8
  Write-Host "  wrote $file" -ForegroundColor Green
  Start-Process $file
}
