# Fully decode LAB-ADMINS's ACEs on the OU: rights + ObjectType + InheritedObjectType
# + InheritanceType, so we can tell if "GenericAll"/"CreateChild" is scoped to computer
# objects (not OUs). ASCII only.
[CmdletBinding()]
param(
  [string] $Ou = 'OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
  [string] $Server = 'corp.example.com'
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$rootDse  = Get-ADRootDSE -Server $Server
$schemaNC = $rootDse.schemaNamingContext

function Resolve-Guid([guid]$g){
  if ($g -eq [guid]'00000000-0000-0000-0000-000000000000') { return '<any/all>' }
  $bytes = ($g.ToByteArray() | ForEach-Object { '\{0:x2}' -f $_ }) -join ''
  try { $o = Get-ADObject -Server $Server -SearchBase $schemaNC -LDAPFilter "(schemaIDGUID=$bytes)" -Properties lDAPDisplayName -ErrorAction Stop
        if ($o) { return $o.lDAPDisplayName } } catch {}
  return $g.ToString()
}

$ou = Get-ADOrganizationalUnit -Identity $Ou -Server $Server -Properties nTSecurityDescriptor
$aces = $ou.nTSecurityDescriptor.Access | Where-Object {
  ($_.IdentityReference.Value -match '1927434') -or ($_.IdentityReference.Value -match 'LAB-ADMINS')
}
if (-not $aces) { "No LAB-ADMINS ACEs matched."; return }

foreach ($a in $aces) {
  "Type        : {0}" -f $a.AccessControlType
  "Rights      : {0}" -f $a.ActiveDirectoryRights
  "CreateChild-of (ObjectType)      : {0}" -f (Resolve-Guid $a.ObjectType)
  "Applies-to-descendants-of-class  : {0}" -f (Resolve-Guid $a.InheritedObjectType)
  "InheritanceType                  : {0}" -f $a.InheritanceType
  "Inherited   : {0}" -f $a.IsInherited
  "======"
}
