# Read-only: who has create/authority rights on the Azure Local candidate OUs.
# Lists ACEs granting CreateChild / GenericAll / Write* (the rights that let a principal
# create OUs/objects or re-delegate) on each target OU. ASCII only.
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
$out = Join-Path $PSScriptRoot '..\out\_ou-delegation.txt'
$lines = New-Object System.Collections.Generic.List[string]
function Log($m){ $lines.Add($m); Write-Host $m }

$interesting = 'CreateChild|GenericAll|WriteDacl|WriteOwner|WriteProperty'
foreach ($dn in $Ou) {
  Log ("==== {0} ====" -f $dn)
  try {
    $o = Get-ADOrganizationalUnit -Identity $dn -Server $Server -Properties nTSecurityDescriptor -ErrorAction Stop
    $aces = $o.nTSecurityDescriptor.Access |
      Where-Object { $_.AccessControlType -eq 'Allow' -and $_.ActiveDirectoryRights -match $interesting }
    $aces |
      Select-Object @{n='Identity';e={$_.IdentityReference}},
                    @{n='Rights';e={$_.ActiveDirectoryRights}},
                    @{n='Inherited';e={$_.IsInherited}} |
      Sort-Object Identity -Unique |
      ForEach-Object { Log ("  {0,-55} {1,-12} {2}" -f $_.Identity, $_.Inherited, $_.Rights) }
  } catch {
    Log ("  ERR {0}" -f $_.Exception.Message.Split([char]10)[0])
  }
  Log ''
}
Set-Content -Path $out -Value $lines -Encoding utf8
Write-Host "WROTE $out"
