# Resolve the delegated (non-inherited) principal SIDs that hold CreateChild/GenericAll
# directly on the Azure Local candidate OUs, to human names for the access ticket. ASCII only.
[CmdletBinding()]
param(
  [string[]] $Ou = @(
    'OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
    'OU=Lab-Datacenter,OU=DomainSync,OU=Lab,DC=corp,DC=example,DC=com'
  ),
  [string] $Server = 'corp.example.com'
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$out = Join-Path $PSScriptRoot '..\out\_ou-delegation-names.txt'
$lines = New-Object System.Collections.Generic.List[string]
function Log($m){ $lines.Add($m); Write-Host $m }

function Resolve-Sid([string]$sid){
  # Try .NET translate first (works for built-ins + resolvable domains)
  try { return ([System.Security.Principal.SecurityIdentifier]$sid).Translate([System.Security.Principal.NTAccount]).Value } catch {}
  # Fall back to AD lookup by objectSid on the NA server
  try { $g = Get-ADObject -Server $Server -LDAPFilter "(objectSid=$sid)" -Properties samAccountName,name,objectClass -ErrorAction Stop
        if ($g) { return ("{0} ({1})" -f $g.name, $g.objectClass) } } catch {}
  return "<unresolved>"
}

$want = 'CreateChild|GenericAll'
foreach ($dn in $Ou) {
  Log ("==== {0} ====" -f $dn)
  $o = Get-ADOrganizationalUnit -Identity $dn -Server $Server -Properties nTSecurityDescriptor -ErrorAction Stop
  $aces = $o.nTSecurityDescriptor.Access |
    Where-Object { $_.AccessControlType -eq 'Allow' -and $_.ActiveDirectoryRights -match $want }
  $seen = @{}
  foreach ($a in $aces) {
    $id = $a.IdentityReference.Value
    if ($seen.ContainsKey($id)) { continue }
    $seen[$id] = $true
    $name = if ($id -like 'S-1-*') { Resolve-Sid $id } else { $id }
    Log ("  {0,-58} inh={1,-5} {2}" -f $name, $a.IsInherited, $a.ActiveDirectoryRights)
  }
  Log ''
}
Set-Content -Path $out -Value $lines -Encoding utf8
Write-Host "WROTE $out"
