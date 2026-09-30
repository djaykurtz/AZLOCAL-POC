# Dump DENY ACEs along the parent chain of the target OU, with ObjectType decoded,
# to expose any inherited/explicit deny that could block creating a child OU. ASCII only.
[CmdletBinding()]
param(
  [string] $Server = 'corp.example.com',
  [string[]] $Chain = @(
    'OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
    'OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com',
    'OU=Lab,DC=corp,DC=example,DC=com',
    'DC=corp,DC=example,DC=com'
  )
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$rootDse  = Get-ADRootDSE -Server $Server
$schemaNC = $rootDse.schemaNamingContext
$ouGuid   = [guid]'bf967aa5-0de6-11d0-a285-00aa003049e2'

function Resolve-Guid([guid]$g){
  if ($g -eq [guid]'00000000-0000-0000-0000-000000000000') { return 'ALL(incl OU)' }
  if ($g -eq $ouGuid) { return 'organizationalUnit' }
  $bytes = ($g.ToByteArray() | ForEach-Object { '\{0:x2}' -f $_ }) -join ''
  try { $o = Get-ADObject -Server $Server -SearchBase $schemaNC -LDAPFilter "(schemaIDGUID=$bytes)" -Properties lDAPDisplayName -ErrorAction Stop
        if ($o) { return $o.lDAPDisplayName } } catch {}
  return $g.ToString()
}

foreach ($dn in $Chain) {
  "==== $dn ===="
  try {
    $obj = Get-ADObject -Identity $dn -Server $Server -Properties nTSecurityDescriptor -ErrorAction Stop
    $deny = $obj.nTSecurityDescriptor.Access | Where-Object { $_.AccessControlType -eq 'Deny' }
    if (-not $deny) { "  (no Deny ACEs)"; "" ; continue }
    foreach ($d in $deny) {
      "  {0,-45} inh={1,-5} {2,-30} ObjType={3}" -f $d.IdentityReference.Value, $d.IsInherited, $d.ActiveDirectoryRights, (Resolve-Guid $d.ObjectType)
    }
  } catch { "  ERR $($_.Exception.Message.Split([char]10)[0])" }
  ""
}
