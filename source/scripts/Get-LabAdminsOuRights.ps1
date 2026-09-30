# Decode exactly what LAB-ADMINS can create on the NoSync Lab-Datacenter OU.
# Prints each Allow ACE for LAB-ADMINS with the ObjectType resolved to a schema class
# name, so we can tell if CreateChild covers organizationalUnit (sub-OU) or is scoped. ASCII only.
[CmdletBinding()]
param(
  [string] $Ou = 'OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
  [string] $Server = 'corp.example.com',
  [string] $Principal = 'LAB-ADMINS'
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Build a GUID -> schema class/attribute name map (only for GUIDs we encounter)
$rootDse = Get-ADRootDSE -Server $Server
$schemaNC = $rootDse.schemaNamingContext

function Resolve-Guid([guid]$g){
  if ($g -eq [guid]'00000000-0000-0000-0000-000000000000') { return 'ALL (any child type - includes OU)' }
  $bytes = ($g.ToByteArray() | ForEach-Object { '\{0:x2}' -f $_ }) -join ''
  try {
    $o = Get-ADObject -Server $Server -SearchBase $schemaNC -LDAPFilter "(schemaIDGUID=$bytes)" -Properties lDAPDisplayName -ErrorAction Stop
    if ($o) { return $o.lDAPDisplayName }
  } catch {}
  # rights GUIDs (control access rights) live in config extended-rights
  try {
    $cfg = $rootDse.configurationNamingContext
    $o2 = Get-ADObject -Server $Server -SearchBase "CN=Extended-Rights,$cfg" -LDAPFilter "(rightsGuid=$($g.ToString()))" -Properties displayName -ErrorAction Stop
    if ($o2) { return "ExtRight:$($o2.displayName)" }
  } catch {}
  return $g.ToString()
}

$grp = Get-ADGroup -Server $Server -Identity $Principal -Properties objectSid -ErrorAction Stop
$sid = $grp.objectSid.Value
"Principal   : {0}  SID={1}" -f $Principal, $sid
"====="

$ou = Get-ADOrganizationalUnit -Identity $Ou -Server $Server -Properties nTSecurityDescriptor
$aces = $ou.nTSecurityDescriptor.Access | Where-Object {
  if ($_.AccessControlType -ne 'Allow') { return $false }
  try { $aceSid = $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
  catch { $aceSid = $_.IdentityReference.Value }
  $aceSid -eq $sid
}

if (-not $aces) { "No Allow ACEs found for $Principal ($sid) on $Ou"; return }

foreach ($a in $aces) {
  "Rights      : {0}" -f $a.ActiveDirectoryRights
  "AppliesTo   : {0}" -f $a.InheritanceType
  "ObjectType  : {0}" -f (Resolve-Guid $a.ObjectType)
  "InheritOnly : {0}" -f (Resolve-Guid $a.InheritedObjectType)
  "Inherited   : {0}" -f $a.IsInherited
  "-----"
}
