<#
.SYNOPSIS
    Cut Azure Local wizard's AD dependency from corp AD to sim.example.internal lab AD.

.DESCRIPTION
    Executes phases B (AD writes), C (verify AD), D (update Azure
    deploymentSettings), E (re-run validation) from
    docs/runbooks/sim-domain-cutover-plan.txt.

    Idempotent: detects existing OU/user/ACEs and updates or skips.
    Every step is logged to out/_sim-cutover-<stamp>.log so we can review
    later. LCM password is generated in-memory, pushed to KV, saved as DPAPI
    file, and immediately zeroed. Never touches stdout or the log.

.PARAMETER OnlyPhases
    Comma-separated list of phases to run. Default: B,C,D,E.
    Use e.g. -OnlyPhases 'D,E' to re-run just the Azure side after AD is done.
#>

param(
    [string]$SimDomain     = 'sim.example.internal',
    [string]$SimNetBios    = 'SIM',
    [string]$SimDc         = 'dc-01.lab.example.com',
    [string]$SimAdminUpn   = 'labadmin@example.com',
    [string]$SimAdminCred  = '.\.creds\sim-example-internal-admin.cred',

    [string]$AzureLocalOuName = 'AzureLocal',
    [string]$AzureLocalOuParent = 'OU=Lab Systems,DC=sim,DC=example,DC=internal',
    [string]$LcmSam            = 'AZLCL-DEPLOY-ADM',
    [string]$LcmParentOu       = 'OU=Service Accounts,OU=Lab Systems,DC=sim,DC=example,DC=internal',
    [string]$KvName            = 'kv-lab-secrets',
    [string]$KvSecretName      = 'sim-lcm-azlcl-deploy-adm',
    [string]$LcmDpapiFile      = '.\.creds\sim-azlcl-deploy-adm.cred',

    [string]$SubscriptionId    = '00000000-0000-0000-0000-000000000001',
    [string]$ResourceGroup     = 'rg-azlocal-poc-001',
    [string]$ClusterName       = 'AZL-CLUSTER-01',
    [string]$DsApiVersion      = '2024-04-01',

    [string]$OnlyPhases        = 'B,C,D,E'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir  = 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$logFile = Join-Path $outDir "_sim-cutover-$stamp.log"
$stateFile = Join-Path $outDir "_sim-cutover-$stamp.state"

function Log([string]$msg, [string]$level='INFO') {
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts $level] $msg"
    $line | Tee-Object -FilePath $logFile -Append | Out-Host
}
function Save-State([hashtable]$s) { $s | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stateFile -Encoding UTF8 }
$state = [ordered]@{ StartedUtc=(Get-Date).ToUniversalTime().ToString('o'); Stamp=$stamp }

Log "Starting sim domain cutover. Log: $logFile"
Log "Plan: docs/runbooks/sim-domain-cutover-plan.txt"

# Load sim Domain Admin cred
if (-not (Test-Path $SimAdminCred)) { throw "Missing admin cred: $SimAdminCred" }
$simCred = [pscredential]::new(
    $SimAdminUpn,
    (ConvertTo-SecureString ((Get-Content $SimAdminCred -Raw).Trim()))
)
$phases = $OnlyPhases -split ','

$azureLocalOuDN = "OU=$AzureLocalOuName,$AzureLocalOuParent"

# ============================================================
# PHASE B: AD writes on sim.example.internal
# ============================================================
if ($phases -contains 'B') {
    Log "==== PHASE B: AD writes on $SimDomain ===="

    # B1: OU
    $ou = Get-ADOrganizationalUnit -Server $SimDc -Credential $simCred -SearchBase $AzureLocalOuParent -SearchScope OneLevel -Filter "Name -eq '$AzureLocalOuName'" -ErrorAction SilentlyContinue
    if ($ou) {
        Log "B1  OU already exists: $($ou.DistinguishedName)"
    } else {
        New-ADOrganizationalUnit -Server $SimDc -Credential $simCred -Name $AzureLocalOuName -Path $AzureLocalOuParent -ProtectedFromAccidentalDeletion:$true
        $ou = Get-ADOrganizationalUnit -Server $SimDc -Credential $simCred -Identity $azureLocalOuDN
        Log "B1  Created OU: $($ou.DistinguishedName)"
    }
    $state.OuDN = $ou.DistinguishedName; Save-State $state

    # B2: gPOptions=1 (block inheritance) via Set-ADObject (no GroupPolicy module needed)
    Set-ADObject -Server $SimDc -Credential $simCred -Identity $ou.DistinguishedName -Replace @{ gPOptions = 1 }
    $checkGp = Get-ADObject -Server $SimDc -Credential $simCred -Identity $ou.DistinguishedName -Properties gPOptions
    Log "B2  Set gPOptions=1 on OU (block GPO inheritance). Now reads: $($checkGp.gPOptions)"
    $state.GpOptions = $checkGp.gPOptions; Save-State $state

    # B3: Ensure LCM parent OU exists (should - Service Accounts exists), then create LCM user
    $lcm = Get-ADUser -Server $SimDc -Credential $simCred -Filter "sAMAccountName -eq '$LcmSam'" -ErrorAction SilentlyContinue
    if ($lcm) {
        Log "B3  LCM user already exists: $($lcm.DistinguishedName)"
    } else {
        # Generate 24-char complex password in memory only
        function New-ComplexPassword([int]$Length=24) {
            $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ','abcdefghjkmnpqrstuvwxyz','23456789','!#$%*+-=@_')
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $bytes = New-Object byte[] ($Length*4)
            $rng.GetBytes($bytes)
            $chars = for($i=0;$i -lt $Length;$i++){
                $set = $sets[$i % $sets.Length]
                $set[ ([BitConverter]::ToUInt32($bytes,$i*4)) % $set.Length ]
            }
            # Shuffle
            $shuf = ($chars | Sort-Object { Get-Random })
            -join $shuf
        }
        $pw = New-ComplexPassword 24
        $secPw = ConvertTo-SecureString $pw -AsPlainText -Force

        try {
            New-ADUser -Server $SimDc -Credential $simCred `
                -Name $LcmSam -SamAccountName $LcmSam `
                -UserPrincipalName "$LcmSam@$SimDomain" `
                -Path $LcmParentOu `
                -AccountPassword $secPw `
                -Enabled:$true `
                -PasswordNeverExpires:$true `
                -CannotChangePassword:$true `
                -Description "Azure Local LCM deployment account for AZL-CLUSTER-01"
            $lcm = Get-ADUser -Server $SimDc -Credential $simCred -Identity $LcmSam
            Log "B3  Created LCM user: $($lcm.DistinguishedName)"

            # B5: Push to KV via temp file (avoids process-arg exposure)
            $tempFile = Join-Path $env:TEMP "kv-$stamp.tmp"
            [IO.File]::WriteAllText($tempFile, $pw, [System.Text.Encoding]::UTF8)
            try {
                az keyvault secret set --vault-name $KvName --name $KvSecretName --file $tempFile --output none
                Log "B5  Pushed LCM password to KV $KvName/$KvSecretName"
                $state.KvSecret = "$KvName/$KvSecretName"; Save-State $state
            } finally {
                if (Test-Path $tempFile) {
                    # Overwrite with zeros before delete
                    [IO.File]::WriteAllBytes($tempFile, (New-Object byte[] 4096))
                    Remove-Item -Force $tempFile
                }
            }

            # B6: DPAPI file
            $secDpapi = ConvertFrom-SecureString $secPw
            $credDir = Split-Path -Parent $LcmDpapiFile
            if (-not (Test-Path $credDir)) { New-Item -ItemType Directory -Path $credDir | Out-Null }
            Set-Content -LiteralPath $LcmDpapiFile -Value $secDpapi -Encoding ASCII -NoNewline
            Log "B6  Saved DPAPI cred file: $LcmDpapiFile"
        } finally {
            # Zero the plaintext password variable
            if ($pw) {
                $pw = 'x' * $pw.Length
                Remove-Variable pw -ErrorAction SilentlyContinue
            }
            Remove-Variable secPw -ErrorAction SilentlyContinue
        }
    }
    $state.LcmDN  = $lcm.DistinguishedName
    $state.LcmSid = [string]$lcm.SID
    Save-State $state

    # B4: Add the 3 direct ACEs to the OU DACL (Microsoft module verbatim)
    Log "B4  Applying 3 direct ACEs to OU DACL for SID $($lcm.SID)..."
    $userIdRef = [System.Security.Principal.IdentityReference][System.Security.Principal.SecurityIdentifier]$lcm.SID
    $adRight   = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild
    $genericAllRight  = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
    $readPropertyRight = [System.DirectoryServices.ActiveDirectoryRights]::ReadProperty
    $type = [System.Security.AccessControl.AccessControlType]::Allow
    $inheritanceType  = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    $allObjectType    = [System.Guid]::Empty
    $computersObjectType = [System.Guid]::New('bf967a86-0de6-11d0-a285-00aa003049e2')
    $msfveRecoveryGuid   = [System.Guid]::New('ea715d30-8f53-40d0-bd1e-6109186d782c')

    $rule1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($userIdRef, $adRight, $type, $computersObjectType, $inheritanceType)
    $rule2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($userIdRef, $readPropertyRight, $type, $allObjectType, $inheritanceType)
    $rule3 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($userIdRef, $genericAllRight, $type, $inheritanceType, $msfveRecoveryGuid)

    # AD PSDrive requires domain-join. Do the SD manipulation via Get-ADObject/Set-ADObject.
    $ouObj = Get-ADObject -Server $SimDc -Credential $simCred -Identity $ou.DistinguishedName -Properties nTSecurityDescriptor
    $sd = $ouObj.nTSecurityDescriptor
    $sd.AddAccessRule($rule1)
    $sd.AddAccessRule($rule2)
    $sd.AddAccessRule($rule3)
    Set-ADObject -Server $SimDc -Credential $simCred -Identity $ou.DistinguishedName -Replace @{ nTSecurityDescriptor = $sd }
    Log "B4  ACEs applied. Re-reading to confirm..."

    $confirm = Get-ADObject -Server $SimDc -Credential $simCred -Identity $ou.DistinguishedName -Properties nTSecurityDescriptor
    $direct = @($confirm.nTSecurityDescriptor.Access | Where-Object {
        try { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq [string]$lcm.SID } catch { $false }
    })
    Log "B4  Direct-ACE count for LCM SID on OU: $($direct.Count) (expect 3)"
    $state.DirectAceCount = $direct.Count
    Save-State $state
}

# ============================================================
# PHASE C: Verify AD side
# ============================================================
if ($phases -contains 'C') {
    Log "==== PHASE C: Verify AD side ===="

    if (-not (Test-Path $LcmDpapiFile)) { throw "LCM cred file missing (Phase B didn't complete): $LcmDpapiFile" }
    $lcmCred = [pscredential]::new(
        "$SimNetBios\$LcmSam",
        (ConvertTo-SecureString ((Get-Content $LcmDpapiFile -Raw).Trim()))
    )

    # C2: bind as LCM, create+delete throwaway computer object
    $throwaway = "AZLTP-$($stamp.Substring(9))"
    try {
        New-ADComputer -Server $SimDc -Path $azureLocalOuDN -Name $throwaway -SAMAccountName $throwaway -Credential $lcmCred -ErrorAction Stop
        Log "C2  CREATE OK (as LCM): $throwaway"
        Remove-ADComputer -Server $SimDc -Identity "CN=$throwaway,$azureLocalOuDN" -Credential $lcmCred -Confirm:$false -ErrorAction Stop
        Log "C2  DELETE OK (as LCM): $throwaway"
        $state.LcmPractical = 'OK'
    } catch {
        Log "C2  FAILED: $($_.Exception.Message)" 'ERROR'
        $state.LcmPractical = 'FAILED'
    }
    Save-State $state

    # C3: run the wizard's OWN validator locally
    if (Get-Module -ListAvailable AzStackHci.EnvironmentChecker) {
        try {
            Log "C3  Running Test-AzStackHciExternalActiveDirectory..."
            $adCheckRaw = Invoke-Command -ScriptBlock {
                param($ouDN,$domain,$lcmSam,$credFile,$netBios)
                Import-Module AzStackHci.EnvironmentChecker -ErrorAction Stop
                $lcm = [pscredential]::new("$netBios\$lcmSam",(ConvertTo-SecureString ((Get-Content $credFile -Raw).Trim())))
                Test-AzStackHciExternalActiveDirectory -OUPath $ouDN -DomainFQDN $domain `
                    -DeploymentUserCredential $lcm -PassThru
            } -ArgumentList $azureLocalOuDN,$SimDomain,$LcmSam,$LcmDpapiFile,$SimNetBios
            $adCheckJson = $adCheckRaw | ConvertTo-Json -Depth 6
            Set-Content -LiteralPath (Join-Path $outDir "_ad-envchecker-$stamp.json") -Value $adCheckJson -Encoding UTF8
            # Summarize
            $adCheckRaw | ForEach-Object {
                Log ("C3    [{0,-8}] {1}" -f "$($_.Status)","$($_.Name)")
            }
        } catch {
            Log "C3  Env checker error: $($_.Exception.Message)" 'WARN'
        }
    } else {
        Log "C3  AzStackHci.EnvironmentChecker not present - skipping local validator" 'WARN'
    }
}

# ============================================================
# PHASE D: Update Azure deploymentSettings + rewrite LCM secret value in wizard KV
# ============================================================
if ($phases -contains 'D') {
    Log "==== PHASE D: Update deploymentSettings + rewrite LCM secret in wizard KV ===="

    # D-pre: back up current state
    $dsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.AzureStackHCI/clusters/$ClusterName/deploymentSettings/default?api-version=$DsApiVersion"
    $currentJson = az rest --method GET --uri $dsUri --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to GET deploymentSettings" }
    $backupFile = Join-Path $outDir "_deploymentSettings-pre-simcutover-$stamp.json"
    $currentJson | Set-Content -LiteralPath $backupFile -Encoding UTF8
    Log "D1  Backed up current deploymentSettings to $backupFile"

    $current = $currentJson | ConvertFrom-Json
    $du = $current.properties.deploymentConfiguration.scaleUnits[0].deploymentData

    # Locate the LCM secret entry
    $lcmSecretEntry = $du.secrets | Where-Object { $_.eceSecretName -eq 'AzureStackLCMUserCredential' } | Select-Object -First 1
    if (-not $lcmSecretEntry) { throw "No AzureStackLCMUserCredential entry in deploymentSettings.secrets[]" }
    $lcmSecretName = $lcmSecretEntry.secretName
    $lcmSecretVault = ($lcmSecretEntry.secretLocation -replace 'https://([^.]+)\..*','$1')
    Log "D2a LCM secret target: vault=$lcmSecretVault name=$lcmSecretName"

    # Load new LCM password from DPAPI (never printed)
    if (-not (Test-Path $LcmDpapiFile)) { throw "LCM cred file missing: $LcmDpapiFile" }
    $sec = ConvertTo-SecureString ((Get-Content $LcmDpapiFile -Raw).Trim())
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $newPw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        # Wizard format: base64( "<SAM>:<pw>" )
        $blob = "${LcmSam}:${newPw}"
        $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($blob))
        # Push via temp file (avoid process-arg exposure)
        $tempFile = Join-Path $env:TEMP "kvsecret-$stamp.tmp"
        # ASCII encoding = no BOM (base64 is pure ASCII anyway). UTF8 encoding in PowerShell
        # adds a BOM which makes the wizard's ECE parser return "invalid object".
        [IO.File]::WriteAllText($tempFile, $b64, [Text.Encoding]::ASCII)
        try {
            az keyvault secret set --vault-name $lcmSecretVault --name $lcmSecretName --file $tempFile --output none
            if ($LASTEXITCODE -ne 0) { throw "KV secret rewrite failed" }
            Log "D2b Overwrote LCM secret VALUE in $lcmSecretVault/$lcmSecretName (base64 SAM:pw)"
        } finally {
            [IO.File]::WriteAllBytes($tempFile, (New-Object byte[] 4096))
            Remove-Item -Force $tempFile
        }
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        if ($blob)   { $blob   = 'x'*$blob.Length;   Remove-Variable blob   -ErrorAction SilentlyContinue }
        if ($newPw)  { $newPw  = 'x'*$newPw.Length;  Remove-Variable newPw  -ErrorAction SilentlyContinue }
        if ($b64)    { $b64    = 'x'*$b64.Length;    Remove-Variable b64    -ErrorAction SilentlyContinue }
    }

    Log "D2c Current AD fields in deploymentSettings:"
    Log "D2c   adouPath  : $($du.adouPath)"
    Log "D2c   domainFqdn: $($du.domainFqdn)"

    # Rewrite ONLY adouPath + domainFqdn; leave secrets[] alone
    $du.adouPath   = $azureLocalOuDN
    $du.domainFqdn = $SimDomain
    Log "D2d New AD fields:"
    Log "D2d   adouPath  : $($du.adouPath)"
    Log "D2d   domainFqdn: $($du.domainFqdn)"

    $body = @{
        properties = @{
            arcNodeResourceIds      = $current.properties.arcNodeResourceIds
            deploymentMode          = 'Validate'
            deploymentConfiguration = $current.properties.deploymentConfiguration
        }
    } | ConvertTo-Json -Depth 32
    $bodyFile = Join-Path $outDir "_ds-patch-body-$stamp.json"
    $body | Set-Content -LiteralPath $bodyFile -Encoding UTF8

    Log "D3  Submitting PATCH to deploymentSettings..."
    $r = az rest --method PUT --uri $dsUri --headers "Content-Type=application/json" --body "@$bodyFile" --output json 2>&1
    if ($LASTEXITCODE -ne 0) { Log "D3  PATCH FAILED: $r" 'ERROR'; throw "PATCH failed" }
    Log "D3  PATCH accepted."
    $state.DeploymentSettingsUpdated = $true; Save-State $state
}

# ============================================================
# PHASE E: Re-run validation
# ============================================================
if ($phases -contains 'E') {
    Log "==== PHASE E: Re-run wizard validation ===="
    Log "E1  Invoking scripts/Invoke-ValidationRetry.ps1 (this will poll for ~15+ min)..."
    & (Join-Path $PSScriptRoot 'Invoke-ValidationRetry.ps1') -PollSeconds 45 -MaxPollMinutes 45 2>&1 | Tee-Object -FilePath $logFile -Append
}

$state.FinishedUtc = (Get-Date).ToUniversalTime().ToString('o')
Save-State $state
Log "==== CUTOVER COMPLETE ===="
Log "State: $stateFile"
Log "Log:   $logFile"
