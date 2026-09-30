<#
.SYNOPSIS
  Verify the Azure Local deployment account (AZLCL-DEPLOY-ADM) has the permissions
  it needs over the AzureLocal OU - both by reading the ACL and by a live,
  reversible create/delete of a throwaway computer object AS the account.

.DESCRIPTION
  Two checks:
    1. ACL read (uses your credentials): resolves the LCM account SID and lists
       the delegated ACEs on the OU (create/delete child, read, msFVE full control).
    2. Live bind test (uses the LCM credential from .creds\azlcl-deploy-adm.cred):
       New-ADComputer as the LCM account under the OU, confirm it lands, then
       Remove-ADComputer. This is exactly what deployment does, so success here
       proves the delegation is in place. Network (LDAP) bind - not affected by
       the interactive deny-logon control.

  The test computer object is clearly named and deleted immediately.

.NOTES
  Read-mostly; the only write is a throwaway computer object that is removed.
#>
[CmdletBinding()]
param(
  [string] $Server  = 'corp.example.com',
  [string] $OU      = 'OU=AzureLocal,OU=Lab-Systems,OU=EntraSync,OU=Lab,DC=corp,DC=example,DC=com',
  [string] $Account = 'CORP\AZLCL-DEPLOY-ADM',
  [string] $SamForSid = 'azlcl-deploy-adm',
  [string] $CredFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azlcl-deploy-adm.cred'),
  [string] $TestName = 'AZLTEST-PERMCHK',
  [switch] $SkipLiveTest
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop
function OK($m){ Write-Host "  OK   $m" -ForegroundColor Green }
function BAD($m){ Write-Host "  FAIL $m" -ForegroundColor Red }
function INFO($m){ Write-Host "  ..   $m" -ForegroundColor DarkGray }

"===== OU permission verification for $Account ====="
"OU: $OU"

# --- 0. OU exists ---
try { $null = Get-ADObject -Server $Server -Identity $OU -ErrorAction Stop; OK "OU exists." }
catch { BAD "OU not found: $($_.Exception.Message)"; return }

# --- 1. ACL read: find the LCM account ACEs ---
"`n[1] ACL check (delegated ACEs on the OU)"
$acctSid = (Get-ADUser -Server $Server -Identity $SamForSid -Properties objectSid).objectSid.Value
# also collect the account's transitive group SIDs (rights may be granted via a group, not a direct ACE)
$groupSids = @()
try {
  $dn = (Get-ADUser -Server $Server -Identity $SamForSid).DistinguishedName
  $de = [ADSI]"LDAP://$Server/$dn"; $de.RefreshCache('tokenGroups')
  foreach ($b in $de.Properties['tokenGroups']) { $groupSids += (New-Object System.Security.Principal.SecurityIdentifier($b,0)).Value }
} catch {}
$idSet = @($acctSid) + $groupSids
# Non-domain-joined box: read the security descriptor directly (no AD: drive).
$sd = (Get-ADObject -Server $Server -Identity $OU -Properties nTSecurityDescriptor).nTSecurityDescriptor
$mine = $sd.Access | Where-Object {
  $ir = $_.IdentityReference
  $sid = if ($ir -is [System.Security.Principal.SecurityIdentifier]) { $ir.Value } else { try { $ir.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { $null } }
  ($idSet -contains $sid) -or ($ir.Value -match 'AZLCL-DEPLOY-ADM')
}
if (-not $mine) {
  BAD "No ACEs found for $Account on the OU. Delegation not applied yet (CR pending?)."
} else {
  $computerGuid = 'bf967a86-0de6-11d0-a285-00aa003049e2'
  $msfveGuid    = 'ea715d30-8f53-40d0-bd1e-6109186d782c'
  $hasCreate = $mine | Where-Object { $_.ActiveDirectoryRights -match 'CreateChild|GenericAll' }
  $hasDelete = $mine | Where-Object { $_.ActiveDirectoryRights -match 'DeleteChild|GenericAll' }
  $hasRead   = $mine | Where-Object { $_.ActiveDirectoryRights -match 'ReadProperty|GenericRead|GenericAll' }
  # msFVE is covered either by a dedicated msFVE-scoped ACE, OR by GenericAll on descendant computer
  # objects (msFVE-RecoveryInformation objects are children of the computer objects, and GenericAll
  # on a computer includes creating child objects of any class under it).
  $hasMsfve  = $mine | Where-Object {
    ($_.ObjectType -eq $msfveGuid -or $_.InheritedObjectType -eq $msfveGuid) -or
    ($_.ActiveDirectoryRights -match 'GenericAll' -and $_.InheritedObjectType -eq $computerGuid)
  }
  if ($hasCreate) { OK "Create computer objects present" } else { BAD "Create (computer) MISSING" }
  if ($hasDelete) { OK "Delete computer objects present" } else { BAD "Delete (computer) MISSING" }
  if ($hasRead)   { OK "Read properties present" } else { INFO "Read properties not explicitly found (may be covered elsewhere)" }
  if ($hasMsfve)  { OK "BitLocker (msFVE-RecoveryInformation) escrow covered (via GenericAll on descendant computers or a dedicated ACE)" } else { BAD "msFVE-RecoveryInformation coverage MISSING - BitLocker escrow may fail" }
  "`n  Raw ACEs for the account:"
  $mine | Select-Object @{n='Rights';e={$_.ActiveDirectoryRights}}, AccessControlType, @{n='ObjectType';e={$_.ObjectType}}, @{n='InheritedObjectType';e={$_.InheritedObjectType}}, InheritanceType | Format-Table -Auto | Out-String -Width 200
}

# --- 2. Live create/delete AS the LCM account ---
if ($SkipLiveTest) { "`n[2] Live create/delete test SKIPPED (-SkipLiveTest)."; return }
"`n[2] Live create/delete of a throwaway computer object AS $Account"
if (-not (Test-Path $CredFile)) { BAD "Cred file missing: $CredFile"; return }
$pw   = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
$cred = [pscredential]::new($Account, $pw)
$testDn = "CN=$TestName,$OU"
try {
  # clean any leftover from a prior run (as the LCM account)
  $existing = Get-ADComputer -Server $Server -Credential $cred -Filter "Name -eq '$TestName'" -SearchBase $OU -ErrorAction SilentlyContinue
  if ($existing) { Remove-ADComputer -Server $Server -Credential $cred -Identity $existing.DistinguishedName -Confirm:$false; INFO "Removed a leftover $TestName from a prior run." }

  New-ADComputer -Server $Server -Credential $cred -Name $TestName -SamAccountName $TestName -Path $OU -Enabled $false -ErrorAction Stop
  OK "CREATE computer object succeeded as the LCM account."
  $chk = Get-ADComputer -Server $Server -Credential $cred -Identity $testDn -ErrorAction Stop
  OK "Object confirmed present: $($chk.DistinguishedName)"
  Remove-ADComputer -Server $Server -Credential $cred -Identity $testDn -Confirm:$false -ErrorAction Stop
  OK "DELETE computer object succeeded as the LCM account."
  Write-Host "`nRESULT: LCM account CAN create and delete computer objects in the OU. Delegation is LIVE." -ForegroundColor Green
} catch {
  BAD "Live test failed: $($_.Exception.Message)"
  Write-Host "`nRESULT: LCM account CANNOT yet create/delete in the OU. If the CR delegation is still pending, this is expected - re-run after it applies." -ForegroundColor Yellow
  # best-effort cleanup with our own creds in case create half-succeeded
  try { $stray = Get-ADComputer -Server $Server -Filter "Name -eq '$TestName'" -SearchBase $OU -ErrorAction SilentlyContinue; if ($stray) { Remove-ADComputer -Server $Server -Identity $stray.DistinguishedName -Confirm:$false -ErrorAction SilentlyContinue; INFO "Cleaned up stray test object with your credentials." } } catch {}
}
