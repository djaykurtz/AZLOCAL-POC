<#
.SYNOPSIS
    Definitive proof of AZLCL-DEPLOY-ADM permission structure on the AzureLocal OU.

.DESCRIPTION
    Runs three independent checks:
      A. DACL walk. Enumerates ACEs on the OU directly attributed to AZLCL-DEPLOY-ADM's SID
         vs attributed to a group AZLCL-DEPLOY-ADM is a member of. This mirrors what the
         Azure Local validator does (walks the DACL, matches on SID directly).
      B. Practical action. Attempts New-ADComputer -Credential $lcm to prove the account
         CAN actually create computer objects (via group membership), even though direct
         ACEs are missing.
      C. Write-DAC probe as AZLCL-DEPLOY-ADM. Attempts to modify the OU's DACL as the LCM
         account. Non-destructive (writes SAME SD back).
    Writes evidence JSON + a plain-text summary usable in a ticket.

.NOTES
    Read-only where possible. B and C revert immediately.
    Runs from an operator workstation with the ActiveDirectory module.
#>

param(
    [string]$OuDN     = 'OU=AzureLocal,OU=Lab-Systems,OU=EntraSync,OU=Lab,DC=corp,DC=example,DC=com',
    [string]$Server   = 'corp.example.com',
    [string]$LcmSam   = 'AZLCL-DEPLOY-ADM',
    [string]$CredFile = '.creds\azlcl-deploy-adm.cred',
    [string]$OutDir   = 'out'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidenceFile = Join-Path $OutDir "_lcm-perm-gap-$stamp.json"
$summaryFile  = Join-Path $OutDir "_lcm-perm-gap-$stamp.txt"

# --- schema GUIDs Microsoft Learn recipe requires ---
$computerClassGuid = [guid]'bf967a86-0de6-11d0-a285-00aa003049e2'
$msFVEClassGuid    = [guid]'ea715d30-8f53-40d0-bd1e-6109186d782c'

Write-Host "==== A. DACL walk on $OuDN ===="

# Get basic user first (subtree search is fine for this)
$lcmBasic = Get-ADUser -Server $Server -Identity $LcmSam
$lcmSid   = [string]$lcmBasic.SID
# tokenGroups is a *constructed* attribute -- requires Base-scope search on the DN.
# Get-ADObject doesn't accept -Identity with -SearchScope; use -LDAPFilter + -SearchBase.
$lcm      = Get-ADObject -Server $Server -SearchBase $lcmBasic.DistinguishedName `
                         -SearchScope Base -LDAPFilter '(objectClass=user)' `
                         -Properties tokenGroups
$groupSids = @($lcm.tokenGroups | ForEach-Object { [string]$_ })
Write-Host "  LCM SID:              $lcmSid"
Write-Host "  Group SIDs (recursive): $($groupSids.Count) groups (via DC tokenGroups)"

$ou = Get-ADObject -Server $Server -Identity $OuDN -Properties nTSecurityDescriptor
$sd = $ou.nTSecurityDescriptor
$aces = @($sd.Access)
Write-Host "  Total ACEs on OU:     $($aces.Count)"

# Translate every ACE trustee to a SID string
function Get-IdentitySid([System.Security.Principal.IdentityReference]$id) {
    try {
        if ($id -is [System.Security.Principal.SecurityIdentifier]) { return [string]$id }
        return $id.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch { return $null }
}

$direct  = @()
$viaGrp  = @()
$other   = @()
foreach ($ace in $aces) {
    if ($ace.AccessControlType -ne 'Allow') { continue }
    $trusteeSid = Get-IdentitySid $ace.IdentityReference
    $row = [pscustomobject]@{
        Trustee               = [string]$ace.IdentityReference
        TrusteeSid            = $trusteeSid
        Rights                = [string]$ace.ActiveDirectoryRights
        ObjectType            = [string]$ace.ObjectType
        InheritedObjectType   = [string]$ace.InheritedObjectType
        InheritanceType       = [string]$ace.InheritanceType
    }
    if     ($trusteeSid -eq $lcmSid)              { $direct += $row }
    elseif ($groupSids -contains $trusteeSid)     { $viaGrp += $row }
    else                                          { $other  += $row }
}

Write-Host "  ACEs directly for LCM SID: $($direct.Count)   <-- what the wizard looks for"
Write-Host "  ACEs via LCM group memberships: $($viaGrp.Count)"
Write-Host "  Other ACEs (unrelated):          $($other.Count)"

if ($viaGrp.Count -gt 0) {
    Write-Host ""
    Write-Host "==== The $($viaGrp.Count) ACE(s) currently granting LCM rights via GROUP membership ===="
    $viaGrp | Format-Table Trustee,Rights,ObjectType,InheritedObjectType,InheritanceType -AutoSize | Out-String -Width 220 | Write-Host
}

# Check for the three specific rights the wizard demands
function Test-RightPresent($rows, [string]$rightsMatch, $inheritedType, [string]$label) {
    $hit = $rows | Where-Object {
        $_.Rights -match $rightsMatch -and
        (-not $inheritedType -or $_.InheritedObjectType -eq [string]$inheritedType)
    }
    [pscustomobject]@{ Right = $label; Match = ($hit.Count -gt 0); AceCount = $hit.Count }
}

Write-Host ""
Write-Host "==== Right-by-right coverage ===="
$rightChecks = @(
    @{ Label='CreateChild+DeleteChild computer (Rule 1)'; Pattern='CreateChild|DeleteChild';    Inherited=$computerClassGuid },
    @{ Label='ReadProperty                    (Rule 2)'; Pattern='ReadProperty|GenericRead';    Inherited=[guid]::Empty },
    @{ Label='GenericAll on msFVE-Recovery... (Rule 3)'; Pattern='GenericAll';                  Inherited=$msFVEClassGuid }
)

$coverage = @()
foreach ($rc in $rightChecks) {
    $inh = if ($rc.Inherited -eq [guid]::Empty) { $null } else { $rc.Inherited }
    $direct_ok = Test-RightPresent $direct $rc.Pattern $inh $rc.Label
    $group_ok  = Test-RightPresent $viaGrp $rc.Pattern $inh $rc.Label
    $coverage += [pscustomobject]@{
        Right                 = $rc.Label
        Present_DirectAce     = $direct_ok.Match
        Present_ViaGroupAce   = $group_ok.Match
        WizardWouldPass       = $direct_ok.Match
    }
}
$coverage | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

Write-Host ""
Write-Host "==== B. Practical action: New-ADComputer as LCM (create+delete throwaway) ===="

if (-not (Test-Path $CredFile)) { throw "Credential file $CredFile not found." }
$lcmCred = [pscredential]::new(
    "$($Server.Split('.')[0])\$LcmSam",
    (ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim()))
)

$practicalOk    = $false
$practicalError = $null
# SAM has a 20-char cap; strip yyyyMMdd- prefix from stamp
$shortStamp = $stamp.Substring(9)
$throwaway  = "AZLTP-$shortStamp"
try {
    New-ADComputer -Server $Server -Path $OuDN -Name $throwaway -SAMAccountName $throwaway -Credential $lcmCred -ErrorAction Stop
    $practicalOk = $true
    Write-Host "  CREATE OK: $throwaway"
    Remove-ADComputer -Server $Server -Identity "CN=$throwaway,$OuDN" -Credential $lcmCred -Confirm:$false -ErrorAction Stop
    Write-Host "  DELETE OK: $throwaway"
} catch {
    $practicalError = $_.Exception.Message
    Write-Host "  FAILED: $practicalError"
}

Write-Host ""
Write-Host "==== C. Write-DAC probe as LCM (writes SAME SD back) ===="

$writeDacOk    = $false
$writeDacError = $null
try {
    Set-ADObject -Server $Server -Identity $OuDN -Replace @{ nTSecurityDescriptor = $sd } -Credential $lcmCred -ErrorAction Stop
    $writeDacOk = $true
    Write-Host "  WRITE-DAC OK (LCM can modify OU DACL)"
} catch {
    $writeDacError = $_.Exception.Message
    Write-Host "  WRITE-DAC FAILED: $writeDacError"
}

# --- Emit evidence JSON + human summary ---
$evidence = [ordered]@{
    Timestamp        = (Get-Date).ToString('o')
    OuDN             = $OuDN
    Server           = $Server
    LcmSam           = $LcmSam
    LcmSid           = $lcmSid
    LcmGroupCount    = $groupSids.Count
    OuAceTotal       = $aces.Count
    AceDirectToLcm   = $direct.Count
    AceViaLcmGroups  = $viaGrp.Count
    AceOther         = $other.Count
    RightCoverage    = $coverage
    PracticalActionOk    = $practicalOk
    PracticalActionError = $practicalError
    WriteDacOk           = $writeDacOk
    WriteDacError        = $writeDacError
    DirectAcesRaw    = $direct
    GroupAcesRaw     = $viaGrp
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding UTF8

$summary = @"
AZLCL-DEPLOY-ADM permission-gap proof
===================================
OU        : $OuDN
Server    : $Server
Timestamp : $(Get-Date -Format 'u')
LCM SID   : $lcmSid
LCM is in : $($groupSids.Count) groups (recursive, per DC)

Wizard-style DACL walk
----------------------
Total ACEs on OU               : $($aces.Count)
ACEs directly attributed to LCM: $($direct.Count)   <-- validator looks for these
ACEs granted via LCM groups    : $($viaGrp.Count)   <-- what our test used

Right-by-right coverage:
$(($coverage | Format-Table -AutoSize | Out-String).Trim())

Practical action (as LCM)
-------------------------
Create+delete computer object in OU: $(if($practicalOk){'SUCCEEDED'}else{"FAILED: $practicalError"})

Write-DAC probe (as LCM)
------------------------
Modify OU DACL: $(if($writeDacOk){'SUCCEEDED'}else{"FAILED: $writeDacError"})

Conclusion
----------
$(if($practicalOk -and -not ($coverage | Where-Object WizardWouldPass)){
"The LCM account CAN perform the practical actions Azure Local needs
(create computer objects, etc.), because rights are granted via a group
it is a member of. BUT the wizard's validator does a static DACL walk
that only matches on direct-SID ACEs, so it reports the account as
'missing' the required permissions.

To pass the wizard, someone with Write-DAC on this OU must add the
three ACEs from the Microsoft Learn recipe directly to
AZLCL-DEPLOY-ADM's SID (in addition to, or instead of, the current
group-based ACEs)."
}elseif(-not $practicalOk){
"The LCM account CANNOT perform the practical actions either. The
underlying delegation itself is broken or was removed. This must be
restored before the wizard is retried."
}else{
"LCM currently HAS direct ACEs and CAN perform actions. The
validator's complaint may be transient - retry validation."
})

Evidence JSON: $evidenceFile
"@
$summary | Set-Content -LiteralPath $summaryFile -Encoding UTF8
Write-Host ""
Write-Host "==== SUMMARY (also written to $summaryFile) ===="
Write-Host $summary
