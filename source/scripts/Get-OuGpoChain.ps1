<#
.SYNOPSIS
  Discover the GPO links that apply down the OU chain to the future Azure Local OU,
  flagging which are ENFORCED (these bypass Block Inheritance and still hit the nodes).

.DESCRIPTION
  Uses ONLY the ActiveDirectory module (GroupPolicy RSAT not required). Reads the
  gPLink / gPOptions attributes on each container from the domain root down to the
  target parent OU, parses the link flags, and resolves each GPO GUID to its name.

  gPLink flag values per link:  0 = enabled,           1 = disabled,
                                2 = enabled+ENFORCED,  3 = disabled+enforced
  gPOptions on a container: 1 = Block Policy Inheritance is set at that container.

  After Block Inheritance is enabled on the new AzureLocal OU, the EFFECTIVE set of
  GPOs on the cluster nodes = every ENFORCED link found anywhere up this chain, plus
  any GPO linked directly to the AzureLocal OU. Those Enforced GPOs are what we must
  review for Azure Local compatibility.

.NOTES
  Read-only. ASCII only.
#>
[CmdletBinding()]
param(
  [string] $Server = 'corp.example.com',
  # Parent OU where OU=AzureLocal will be created (walk up from here to the domain root).
  [string] $StartOU = 'OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
  [string] $OutDir = "$PSScriptRoot\..\out"
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

# Build the container chain: StartOU, its parents, up to the domain root (DC=...).
function Get-ParentDn([string]$dn) {
  $i = $dn.IndexOf(',')
  if ($i -lt 0) { return $null }
  return $dn.Substring($i + 1)
}
$chain = @()
$cur = $StartOU
while ($cur -and ($cur -match '^(OU|DC)=')) {
  $chain += $cur
  # stop once we've added the pure domain root (first token is DC=)
  if ($cur -match '^DC=') { break }
  $cur = Get-ParentDn $cur
}

$gpoCache = @{}
function Resolve-GpoName([string]$guid) {
  if ($gpoCache.ContainsKey($guid)) { return $gpoCache[$guid] }
  $name = $guid
  try {
    $dom = ($StartOU -split ',DC=',2)[1]; $domDn = 'DC=' + $dom
    $o = Get-ADObject -Server $Server -Identity "CN={$guid},CN=Policies,CN=System,$domDn" -Properties displayName -ErrorAction Stop
    if ($o.displayName) { $name = $o.displayName }
  } catch { }
  $gpoCache[$guid] = $name
  $name
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($dn in $chain) {
  $obj = Get-ADObject -Server $Server -Identity $dn -Properties gPLink,gPOptions -ErrorAction SilentlyContinue
  $blocked = ($obj.gPOptions -eq 1)
  if ([string]::IsNullOrWhiteSpace($obj.gPLink)) {
    $rows.Add([pscustomobject]@{ Container=$dn; BlockInherit=$blocked; GPO='(none linked)'; Enabled=$null; Enforced=$null })
    continue
  }
  # gPLink is like: [LDAP://cn={GUID},cn=policies,...;FLAGS][LDAP://...;FLAGS]
  $matches = [regex]::Matches($obj.gPLink, '\[LDAP://cn=\{([0-9A-Fa-f\-]+)\}[^;]*;(\d)\]')
  foreach ($m in $matches) {
    $guid  = $m.Groups[1].Value
    $flag  = [int]$m.Groups[2].Value
    $rows.Add([pscustomobject]@{
      Container    = $dn
      BlockInherit = $blocked
      GPO          = (Resolve-GpoName $guid)
      Enabled      = ($flag -band 1) -eq 0
      Enforced     = ($flag -band 2) -eq 2
    })
  }
}

"===== GPO link chain (domain root -> target OU) =====" 
$rows | Format-Table Container,BlockInherit,GPO,Enabled,Enforced -Auto | Out-String -Width 200

$enforced = $rows | Where-Object { $_.Enforced -eq $true -and $_.Enabled -eq $true }
""
"===== ENFORCED + enabled GPOs (these BYPASS Block Inheritance -> WILL apply to the AzureLocal nodes) ====="
if ($enforced) {
  $enforced | Select-Object GPO,Container -Unique | Format-Table -Auto | Out-String -Width 200
  "ACTION: get the settings of the above GPO(s) and review for Azure Local conflicts."
} else {
  "None. After Block Inheritance is set on OU=AzureLocal, NO inherited GPO reaches the nodes."
  "(Only a GPO linked DIRECTLY to OU=AzureLocal would apply - and we plan none.)"
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$csv = Join-Path $OutDir ("_ou-gpo-chain-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$rows | Export-Csv -NoTypeInformation -Path $csv
"Saved: $csv"
