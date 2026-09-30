<#
.SYNOPSIS
    Recon of the sim.example.internal lab domain for Azure Local deployment.

.DESCRIPTION
    Checks everything the Azure Local wizard + LCM will need from AD, both from
    this DevBox (setup work) and from the 4 cluster nodes (domain-join work).
    All read-only. Writes evidence JSON + a plain-text summary.

    Sections:
      A. DevBox -> sim domain
         - Identity, group memberships (Domain Admins etc)
         - Domain + forest metadata, functional levels
         - DC list, FSMO roles, OS
         - Root DSE, schema version
         - DNS zone health (SRV records for _ldap, _kerberos, _gc)
         - OU tree (top 2 levels) - where would we put OU=AzureLocal?
         - GPO landscape at root - anything already inheriting?
         - Existing artifacts (any AZL-NODE-*, AzureLocal OU, SIDC-AZLCL-* users)
         - Practical: try a throwaway OU create+delete to prove Write rights

      B. Node -> sim domain (per each of 01/02/04/06 via WinRM)
         - DNS resolution: sim.example.internal A record, SRV records
         - TCP reachability to dc-01: 88, 389, 445, 636, 3268, 135
         - Time skew vs the DC (Kerberos needs <5 min)
         - Current DNS server config (do we need to change it?)

.NOTES
    Uses the sim admin cred saved via Save-LcmCredential.ps1.
    Node checks use the existing local-admin cred.
#>

param(
    [string]$SimDomain      = 'sim.example.internal',
    [string]$SimDc          = 'dc-01.lab.example.com',
    [string]$SimCredFile    = '.\.creds\sim-example-internal-admin.cred',
    [string]$SimUpn         = 'labadmin@example.com',
    [string]$LocalAdminCred = '.\.creds\azloc-local-admin.cred',
    [string[]]$Nodes        = @('azl-node-01','azl-node-02','azl-node-04','azl-node-06'),
    [string]$OutDir         = 'out'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$stamp        = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidenceFile = Join-Path $OutDir "_sim-recon-$stamp.json"

$evidence = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    SimDomain = $SimDomain
    SimDc     = $SimDc
    SectionA  = [ordered]@{}
    SectionB  = @()
}

# ------------------------------------------------------------
Write-Host "==== A. DevBox -> sim.example.internal ====" -ForegroundColor Cyan

if (-not (Test-Path $SimCredFile)) { throw "Missing sim cred file: $SimCredFile" }
$simCred = [pscredential]::new(
    $SimUpn,
    (ConvertTo-SecureString ((Get-Content $SimCredFile -Raw).Trim()))
)

Write-Host "`n-- Identity + groups (as $SimUpn) --"
try {
    $me = Get-ADUser -Server $SimDomain -Credential $simCred -Identity 'labadmin' -Properties memberOf, adminCount, DisplayName
    Write-Host "  DN         : $($me.DistinguishedName)"
    Write-Host "  DisplayName: $($me.DisplayName)"
    Write-Host "  Enabled    : $($me.Enabled)"
    Write-Host "  adminCount : $($me.adminCount)   (1 = member of a protected/admin group)"
    Write-Host "  Direct group count: $($me.memberOf.Count)"
    $me.memberOf | Sort-Object | ForEach-Object {
        $groupCn = ($_ -split ',')[0] -replace '^CN='
        Write-Host "    - $groupCn"
    }
    $evidence.SectionA.Identity = @{
        DN          = $me.DistinguishedName
        Enabled     = $me.Enabled
        AdminCount  = $me.adminCount
        DirectGroups = @($me.memberOf)
    }
} catch { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red; $evidence.SectionA.IdentityError = $_.Exception.Message }

Write-Host "`n-- Domain + forest metadata --"
try {
    $dom = Get-ADDomain -Server $SimDomain -Credential $simCred
    $frs = Get-ADForest -Server $SimDomain -Credential $simCred
    Write-Host "  DomainFQDN  : $($dom.DNSRoot)"
    Write-Host "  NetBIOS     : $($dom.NetBIOSName)"
    Write-Host "  DomainMode  : $($dom.DomainMode)"
    Write-Host "  ForestMode  : $($frs.ForestMode)"
    Write-Host "  ForestRoot  : $($frs.RootDomain)"
    Write-Host "  PDCEmulator : $($dom.PDCEmulator)"
    Write-Host "  RID Master  : $($dom.RIDMaster)"
    Write-Host "  Infra Master: $($dom.InfrastructureMaster)"
    Write-Host "  Schema Master: $($frs.SchemaMaster)"
    Write-Host "  Domain Naming Master: $($frs.DomainNamingMaster)"
    $evidence.SectionA.Domain = @{
        DNSRoot=$dom.DNSRoot; NetBIOSName=$dom.NetBIOSName; DomainMode="$($dom.DomainMode)"; ForestMode="$($frs.ForestMode)"
        PDCEmulator=$dom.PDCEmulator; RIDMaster=$dom.RIDMaster
    }
} catch { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red; $evidence.SectionA.DomainError = $_.Exception.Message }

Write-Host "`n-- DCs in domain --"
try {
    $dcs = Get-ADDomainController -Server $SimDomain -Credential $simCred -Filter *
    $dcRows = $dcs | Select-Object Name, HostName, IPv4Address, OperatingSystem, Site, @{n='IsGC';e={$_.IsGlobalCatalog}}, @{n='IsRO';e={$_.IsReadOnly}}
    $dcRows | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
    $evidence.SectionA.DCs = @($dcRows)
} catch { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red; $evidence.SectionA.DCError = $_.Exception.Message }

Write-Host "`n-- OU tree (top 2 levels under domain root) --"
try {
    $ous = Get-ADOrganizationalUnit -Server $SimDomain -Credential $simCred -Filter * -Properties Name,DistinguishedName
    $rootDN = "DC=$(($SimDomain -split '\.') -join ',DC=')"
    $topLevel = $ous | Where-Object {
        $parent = ($_.DistinguishedName -replace '^OU=[^,]+,','')
        $parent -eq $rootDN
    }
    Write-Host "  Top-level OUs (children of $rootDN):"
    foreach ($ou in $topLevel) {
        Write-Host "    OU=$($ou.Name)"
        Get-ADOrganizationalUnit -Server $SimDomain -Credential $simCred -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter * | ForEach-Object {
            Write-Host "      +-- OU=$($_.Name)"
        }
    }
    $evidence.SectionA.TopLevelOUs = @($topLevel | Select-Object Name,DistinguishedName)
    $evidence.SectionA.AllOUsCount = $ous.Count
    # Check if OU=AzureLocal already exists somewhere
    $existingAL = $ous | Where-Object Name -eq 'AzureLocal'
    if ($existingAL) {
        Write-Host "  NOTE: existing OU=AzureLocal found:"
        $existingAL | ForEach-Object { Write-Host "    $($_.DistinguishedName)" }
        $evidence.SectionA.ExistingAzureLocalOUs = @($existingAL | Select-Object DistinguishedName)
    }
} catch { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red; $evidence.SectionA.OUError = $_.Exception.Message }

Write-Host "`n-- Existing artifacts (AZL-NODE-* / *AZLCL* / AzureLocal) --"
try {
    $existing = Get-ADObject -Server $SimDomain -Credential $simCred `
        -LDAPFilter '(|(name=AZL-NODE-*)(name=AZL-CLUSTER*)(name=*AZLCL*)(name=AZLCL-DEPLOY-*))' `
        -Properties Name,ObjectClass,DistinguishedName
    if ($existing) {
        $existing | Select-Object Name,ObjectClass,DistinguishedName | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
        $evidence.SectionA.ExistingArtifacts = @($existing | Select-Object Name,ObjectClass,DistinguishedName)
    } else {
        Write-Host "  (none - clean slate)"
        $evidence.SectionA.ExistingArtifacts = @()
    }
} catch { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red }

Write-Host "`n-- Root-linked GPOs (would inherit down without block-inheritance) --"
try {
    $rootDNlink = (Get-ADDomain -Server $SimDomain -Credential $simCred).DistinguishedName
    $rootObj = Get-ADObject -Server $SimDomain -Credential $simCred -Identity $rootDNlink -Properties gPLink
    if ($rootObj.gPLink) {
        Write-Host "  Root gPLink raw: $($rootObj.gPLink)"
        # parse [LDAP://cn={GUID},...][flags] repeated
        $links = [regex]::Matches($rootObj.gPLink, '\[LDAP://(cn=\{[^\}]+\},[^\]]+);(\d+)\]')
        foreach ($m in $links) {
            $gpoDn = $m.Groups[1].Value
            $flags = [int]$m.Groups[2].Value
            $enforced = ($flags -band 2) -ne 0
            try {
                $gpo = Get-ADObject -Server $SimDomain -Credential $simCred -Identity $gpoDn -Properties displayName
                Write-Host ("    - {0}   Enforced={1}" -f $gpo.displayName, $enforced)
            } catch { Write-Host "    - $gpoDn (name lookup failed)" }
        }
    } else {
        Write-Host "  (no gPLink at domain root = clean, nothing inheriting)"
    }
} catch { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red }

Write-Host "`n-- Practical Write test: create + delete throwaway OU under domain root --"
$testOuName = "AZL-WRITEPROBE-$stamp"
$testOuDn = "OU=$testOuName,$($dom.DistinguishedName)"
$writeOk = $false
try {
    New-ADOrganizationalUnit -Server $SimDomain -Credential $simCred -Name $testOuName `
        -Path $dom.DistinguishedName -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop
    Write-Host "  CREATE OK: $testOuDn"
    Remove-ADOrganizationalUnit -Server $SimDomain -Credential $simCred -Identity $testOuDn -Confirm:$false -ErrorAction Stop
    Write-Host "  DELETE OK: $testOuDn"
    $writeOk = $true
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $evidence.SectionA.WriteProbeError = $_.Exception.Message
}
$evidence.SectionA.WriteProbeOk = $writeOk

# ------------------------------------------------------------
Write-Host "`n==== B. Node -> sim.example.internal (via WinRM) ====" -ForegroundColor Cyan

if (-not (Test-Path $LocalAdminCred)) { throw "Missing local admin cred: $LocalAdminCred" }
$localSec = ConvertTo-SecureString ((Get-Content $LocalAdminCred -Raw).Trim())

foreach ($n in $Nodes) {
    Write-Host "`n-- $n --"
    $c = [pscredential]::new("$n\Administrator", $localSec)
    $nodeResult = [ordered]@{ Node = $n }
    try {
        $r = Invoke-Command -ComputerName "$n.lab.example.com" -Credential $c -Authentication Negotiate -ScriptBlock {
            param($SimDomain, $SimDc)
            $result = [ordered]@{}

            # Current DNS config
            $result.CurrentDns = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | ForEach-Object {
                @{ Interface = $_.InterfaceAlias; Servers = @($_.ServerAddresses) }
            })

            # A record
            try { $result.DomainA = @((Resolve-DnsName $SimDomain -Type A -ErrorAction Stop).IPAddress) } catch { $result.DomainAError = $_.Exception.Message }

            # SRV records
            $srvs = "_ldap._tcp.dc._msdcs.$SimDomain","_kerberos._tcp.$SimDomain","_gc._tcp.$SimDomain"
            $result.SRV = @{}
            foreach ($s in $srvs) {
                try {
                    $recs = Resolve-DnsName $s -Type SRV -ErrorAction Stop | Where-Object { $_.Type -eq 'SRV' }
                    $result.SRV[$s] = @($recs | ForEach-Object { "$($_.NameTarget):$($_.Port)" })
                } catch { $result.SRV[$s] = "ERR: $($_.Exception.Message)" }
            }

            # DC A record
            try { $result.DcA = @((Resolve-DnsName $SimDc -Type A -ErrorAction Stop).IPAddress) } catch { $result.DcAError = $_.Exception.Message }

            # TCP reachability to DC
            $ports = 88,389,445,636,3268,135
            $result.DcPorts = @{}
            foreach ($p in $ports) {
                $tc = Test-NetConnection -ComputerName $SimDc -Port $p -WarningAction SilentlyContinue -InformationLevel Quiet
                $result.DcPorts["$p"] = [bool]$tc
            }

            # Time skew vs DC (w32tm stripchart)
            try {
                $stripe = & w32tm /stripchart /computer:$SimDc /dataonly /samples:1 2>&1 | Select-String 'ms$' | Select-Object -First 1
                $result.DcSkew = "$stripe".Trim()
            } catch { $result.DcSkew = "ERR: $($_.Exception.Message)" }

            $result.NodeTimeUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $result
        } -ArgumentList $SimDomain, $SimDc

        # Print
        Write-Host "  CurrentDNS      : $(($r.CurrentDns | ForEach-Object { "$($_.Interface): $($_.Servers -join ',')" }) -join ' | ')"
        Write-Host "  $SimDomain (A) : $(($r.DomainA -join ',') ?? 'FAIL')"
        Write-Host "  $SimDc (A)     : $(($r.DcA -join ',') ?? 'FAIL')"
        foreach ($k in $r.SRV.Keys) {
            $v = $r.SRV[$k]
            $show = if ($v -is [array]) { $v -join ' ; ' } else { $v }
            Write-Host "  SRV $k : $show"
        }
        Write-Host "  DC TCP ports    :"
        foreach ($p in ($r.DcPorts.Keys | Sort-Object)) {
            $mark = if ($r.DcPorts[$p]) { 'OK' } else { 'FAIL' }
            Write-Host ("    {0,5} -> {1}" -f $p, $mark)
        }
        Write-Host "  Time skew vs DC : $($r.DcSkew)"
        $nodeResult.Result = $r
    } catch {
        Write-Host "  UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
        $nodeResult.Error = $_.Exception.Message
    }
    $evidence.SectionB += $nodeResult
}

$evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidenceFile -Encoding UTF8
Write-Host "`n==== Evidence written to $evidenceFile ====" -ForegroundColor Green
