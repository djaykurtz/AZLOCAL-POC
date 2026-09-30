<#
.SYNOPSIS
  Determine whether AZLCL-DEPLOY-ADM is caught by the enforced deny-logon GPO
  Example-ServiceAccountLogonPolicy (SeDenyInteractiveLogonRight / SeDenyRemoteInteractiveLogonRight).

.DESCRIPTION
  Azure Local requires the LCM deployment user to have interactive logon on the cluster
  nodes. An ENFORCED domain GPO denies interactive logon to a list of SIDs and bypasses
  Block Inheritance, so it reaches the nodes. This checks whether the LCM account's own
  SID or any of its (transitive) group SIDs appears in that deny list.

.NOTES
  Read-only.
#>
[CmdletBinding()]
param(
  [string] $Server = 'corp.example.com',
  [string] $Account = 'azlcl-deploy-adm',
  [string[]] $DenyInteractiveSids = @(
    'S-1-5-21-1000000000-1000000000-1000000000-1004',
    'S-1-5-21-1000000000-1000000000-1000000000-1006',
    'S-1-5-21-1000000000-1000000000-1000000000-1003',
    'S-1-5-21-1000000000-1000000000-1000000000-1005',
    'S-1-5-21-1000000000-1000000000-1000000000-1002'
  )
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

function Resolve-Sid([string]$sid) {
  try { return ([System.Security.Principal.SecurityIdentifier]::new($sid)).Translate([System.Security.Principal.NTAccount]).Value }
  catch { }
  try { $o = Get-ADObject -Server $Server -Identity $sid -Properties name,objectClass -ErrorAction Stop; return "$($o.name) [$($o.objectClass)]" }
  catch { return '(unresolved - foreign domain)' }
}

"===== Deny-logon SID list (from Example-ServiceAccountLogonPolicy) ====="
$denyResolved = foreach ($s in $DenyInteractiveSids) {
  [pscustomobject]@{ Sid = $s; Name = (Resolve-Sid $s) }
}
$denyResolved | Format-Table -Auto | Out-String -Width 200

$u = Get-ADUser -Server $Server -Identity $Account -Properties objectSid,memberOf,distinguishedName
$acctSid = $u.objectSid.Value
"===== LCM account ====="
"Account : $($u.SamAccountName)"
"SID     : $acctSid"
"DN      : $($u.distinguishedName)"

# Transitive group SIDs via tokenGroups (constructed attr - needs a base-scope ADSI read).
$tokenSids = @()
try {
  $de = [ADSI]"LDAP://$Server/$($u.distinguishedName)"
  $de.RefreshCache('tokenGroups')
  foreach ($b in $de.Properties['tokenGroups']) {
    $tokenSids += (New-Object System.Security.Principal.SecurityIdentifier($b,0)).Value
  }
} catch { "tokenGroups read failed: $($_.Exception.Message)" }
"Transitive group count: $($tokenSids.Count)"

$mySids = @($acctSid) + $tokenSids
$hits = $DenyInteractiveSids | Where-Object { $mySids -contains $_ }

""
"===== VERDICT ====="
if ($hits) {
  Write-Host "CAUGHT: the LCM account IS covered by the deny-interactive-logon GPO via:" -ForegroundColor Red
  foreach ($h in $hits) { Write-Host "   $h  =  $(Resolve-Sid $h)" -ForegroundColor Red }
  Write-Host "=> On the cluster nodes this enforced GPO would DENY interactive logon to the LCM account." -ForegroundColor Red
  Write-Host "   Azure Local requires interactive logon -> this must be exempted (WMI filter on the" -ForegroundColor Red
  Write-Host "   enforced GPO to exclude the AzureLocal nodes, OR remove the account from the denied group)." -ForegroundColor Red
} else {
  Write-Host "CLEAR: neither the LCM account SID nor any of its group SIDs is in the deny list." -ForegroundColor Green
  Write-Host "=> The enforced deny-logon GPO does NOT block AZLCL-DEPLOY-ADM. Interactive logon is fine." -ForegroundColor Green
}

""
"(For reference, the account's transitive group SIDs:)"
$tokenSids | ForEach-Object { "  $_  =  $(Resolve-Sid $_)" }
