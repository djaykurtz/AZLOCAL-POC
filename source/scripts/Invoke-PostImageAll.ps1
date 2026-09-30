<#
.SYNOPSIS
  Orchestrate node01-postimage.ps1 across all six Azure Local nodes.

.DESCRIPTION
  Pulls the shared local Administrator credential from the POC SecretStore
  vault, builds a per-host PSCredential ('<shortname>\Administrator'),
  probes reachability, then runs the post-image worker against each node.

  Resilient: a failure on one node does not stop the run. Final summary
  table shows per-node status, IP, and pointer to its inventory JSON.

  Idempotent: re-running on a node that's already configured is a no-op
  except for refreshing the inventory JSON.

.PARAMETER Nodes
  Subset of node FQDNs to target. Defaults to all six in the POC.
  Accepts either FQDNs or short names; short names get '.lab.example.com'.

.PARAMETER AssignStaticIp
  If set, push the planned static IP/mask/gateway/DNS to each node.
  Omit if smart-hands already configured static at imaging time and you
  only want inventory + DNS-suffix + firewall steps. Default: $false.

.PARAMETER CredFile
  DPAPI-encrypted password file produced by Sync-CredFromKeyVault.ps1.
  Default '<repo>\.creds\azloc-local-admin.cred'. Preferred over SecretStore.

.PARAMETER VaultName
  SecretStore vault name used only if CredFile is missing. Default 'POC'.

.PARAMETER SecretName
  Credential secret name in SecretStore. Default 'azloc-local-admin'.

.PARAMETER Worker
  Path to the per-node worker script. Default '.\node01-postimage.ps1'.

.EXAMPLE
  # Run inventory-only pass against all 6 nodes
  .\Invoke-PostImageAll.ps1

.EXAMPLE
  # Run only the nodes that are up tonight, push static IPs
  .\Invoke-PostImageAll.ps1 -Nodes azl-node-02,azl-node-03 -AssignStaticIp

.NOTES
  Prereqs: run Set-DevBoxPrereqs.ps1 once (elevated) before first use.

  Network plan baked in below matches the POC plan (2026-05-27 smart-hands
  delivery): /22 on 10.10.0.0, gw 10.10.1.1, DNS 10.20.50.50 +
  10.20.10.50, host IPs 10.10.1.187..192 for nodes 01..06.
#>

[CmdletBinding()]
param(
  [string[]]$Nodes,
  [switch]$AssignStaticIp,
  [string]$CredFile   = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred'),
  [string]$VaultName  = 'POC',
  [string]$SecretName = 'azloc-local-admin',
  [string]$Username   = 'Administrator',
  [string]$Worker     = (Join-Path $PSScriptRoot 'node01-postimage.ps1')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

# === Canonical node table (matches the POC plan) ============================
$NodeTable = @(
  [pscustomobject]@{ Short='azl-node-01'; Fqdn='azl-node-01.lab.example.com'; Ip='10.10.1.187' }
  [pscustomobject]@{ Short='azl-node-02'; Fqdn='azl-node-02.lab.example.com'; Ip='10.10.1.188' }
  [pscustomobject]@{ Short='azl-node-03'; Fqdn='azl-node-03.lab.example.com'; Ip='10.10.1.189' }
  [pscustomobject]@{ Short='azl-node-04'; Fqdn='azl-node-04.lab.example.com'; Ip='10.10.1.190' }
  [pscustomobject]@{ Short='azl-node-05'; Fqdn='azl-node-05.lab.example.com'; Ip='10.10.1.191' }
  [pscustomobject]@{ Short='azl-node-06'; Fqdn='azl-node-06.lab.example.com'; Ip='10.10.1.192' }
)
$NetPrefixLength = 22
$NetGateway      = '10.10.1.1'
$NetDnsServers   = @('10.20.50.50','10.20.10.50')

# === Resolve target set =====================================================
if (-not $Nodes -or $Nodes.Count -eq 0) {
  $targets = $NodeTable
} else {
  $targets = foreach ($n in $Nodes) {
    $short = ($n -split '\.')[0].ToLower()
    $match = $NodeTable | Where-Object { $_.Short -eq $short }
    if (-not $match) { throw "Unknown node '$n'. Known: $($NodeTable.Short -join ', ')" }
    $match
  }
}

# === Sanity ================================================================
if (-not (Test-Path $Worker)) { throw "Worker script not found: $Worker" }

# Resolve shared password. Prefer DPAPI file (no prompts), fall back to SecretStore.
$sharedPassword = $null
$credSource     = ''
if (Test-Path $CredFile) {
  try {
    $cipher = Get-Content -Path $CredFile -Raw -ErrorAction Stop
    $sharedPassword = ConvertTo-SecureString -String $cipher.Trim() -ErrorAction Stop
    $credSource = "DPAPI file ($CredFile)"
  } catch {
    Write-Warning "Cred file present but unreadable: $($_.Exception.Message). Falling back to SecretStore."
  }
}
if (-not $sharedPassword) {
  Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
  $baseCred = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop
  if (-not $baseCred -or -not $baseCred.Password) {
    throw "Secret '$SecretName' did not return a usable PSCredential. Run Sync-CredFromKeyVault.ps1 or Set-DevBoxPrereqs.ps1."
  }
  $sharedPassword = $baseCred.Password
  $credSource = "SecretStore $VaultName/$SecretName"
}
Write-Host ("Credential source: {0}" -f $credSource) -ForegroundColor DarkGray

# === TrustedHosts visibility check =========================================
$th = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
if ([string]::IsNullOrWhiteSpace($th)) {
  Write-Warning "TrustedHosts is empty on this DevBox. WinRM will fail. Run Set-DevBoxPrereqs.ps1 from an elevated shell first."
}

# === Per-node loop ==========================================================
$summary = @()
foreach ($t in $targets) {
  Write-Host ""
  Write-Host ("===== {0} ({1}) =====" -f $t.Fqdn, $t.Ip) -ForegroundColor Cyan

  $entry = [pscustomobject]@{
    Node      = $t.Short
    Fqdn      = $t.Fqdn
    Ip        = $t.Ip
    Reachable = $false
    Result    = ''
    Inventory = ''
    Error     = ''
  }

  # Reachability
  $tcp = $false
  try {
    $tcp = (Test-NetConnection -ComputerName $t.Fqdn -Port 5985 -WarningAction SilentlyContinue).TcpTestSucceeded
  } catch { $tcp = $false }
  $entry.Reachable = $tcp
  if (-not $tcp) {
    Write-Host ("  TCP 5985 unreachable - skipping {0}" -f $t.Fqdn) -ForegroundColor Yellow
    $entry.Result = 'SKIP-UNREACHABLE'
    $summary += $entry
    continue
  }

  # Build per-host credential (SAM format required by workgroup target)
  $cred = [pscredential]::new("$($t.Short)\$Username", $sharedPassword)

  $workerArgs = @{
    NodeFqdn             = $t.Fqdn
    LocalAdminCredential = $cred
  }
  if ($AssignStaticIp) {
    $workerArgs.StaticIPv4      = $t.Ip
    $workerArgs.PrefixLength    = $NetPrefixLength
    $workerArgs.DefaultGateway  = $NetGateway
    $workerArgs.DnsServers      = $NetDnsServers
  }

  try {
    & $Worker @workerArgs
    $entry.Result = 'OK'
    # Pick the most recent inventory JSON for this short name
    $latest = Get-ChildItem -Path (Join-Path $RepoRoot 'out') `
      -Filter ("{0}-inventory-*.json" -f $t.Short) -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { $entry.Inventory = $latest.Name }
  }
  catch {
    $entry.Result = 'FAIL'
    $entry.Error  = $_.Exception.Message
    Write-Host ("  FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }

  $summary += $entry
}

Write-Host ""
Write-Host "================ SUMMARY ================" -ForegroundColor Cyan
$summary | Format-Table Node, Fqdn, Ip, Reachable, Result, Inventory, Error -AutoSize -Wrap
