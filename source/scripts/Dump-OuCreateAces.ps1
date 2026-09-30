[CmdletBinding()]
param(
  [string] $Ou = 'OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
  [string] $Server = 'corp.example.com'
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$rootDse  = Get-ADRootDSE -Server $Server
$schemaNC = $rootDse.schemaNamingContext
$ouGuid   = [guid]'bf967aa5-0de6-11d0-a285-00aa003049e2'

function Resolve-Guid([guid]$g){
  if ($g -eq [guid]'00000000-0000-0000-0000-000000000000') { return 'ALL-child-types(incl OU)' }
  if ($g -eq $ouGuid) { return 'organizationalUnit' }
  $bytes = ($g.ToByteArray() | ForEach-Object { '\{0:x2}' -f $_ }) -join ''
  try { $o = Get-ADObject -Server $Server -SearchBase $schemaNC -LDAPFilter "(schemaIDGUID=$bytes)" -Properties lDAPDisplayName -ErrorAction Stop
        if ($o) { return $o.lDAPDisplayName } } catch {}
  return $g.ToString()
}

$ou = Get-ADOrganizationalUnit -Identity $Ou -Server $Server -Properties nTSecurityDescriptor
$ou.nTSecurityDescriptor.Access |
  Where-Object { $_.AccessControlType -eq 'Allow' -and -not $_.IsInherited -and $_.ActiveDirectoryRights -match 'CreateChild|GenericAll' } |
  ForEach-Object {
    "{0,-52} | {1,-22} | ObjType={2}" -f $_.IdentityReference.Value, $_.ActiveDirectoryRights, (Resolve-Guid $_.ObjectType)
  }
