[CmdletBinding()]
<#
.SYNOPSIS
  READ-ONLY iDRAC (Redfish) verifier for Azure Local node BIOS security state.
  No racadm install needed - pure PowerShell REST. Does NOT change anything.

.DESCRIPTION
  Pulls the BIOS attributes that matter for the Azure Local SecureBoot gate and
  reports them per node, plus checks the iDRAC Job Queue for PENDING BIOS jobs
  (the "staged change stomps your setting on reboot" risk).

  iDRAC Express is sufficient for Redfish BIOS reads (no Enterprise/video license
  needed). Run this from a machine that can REACH the iDRAC management network
  (the DevBox on AzVPN generally CANNOT - the tech's box usually can).

.PARAMETER IdracHost
  One or more iDRAC IPs / hostnames.

.PARAMETER Credential
  iDRAC admin credential (usually root). Prompted if omitted - do NOT hardcode.

.EXAMPLE
  .\Get-IdracBiosSecurity.ps1 -IdracHost 192.168.10.120
.EXAMPLE
  .\Get-IdracBiosSecurity.ps1 -IdracHost 192.168.10.121,192.168.10.122 -Credential (Get-Credential root)

.NOTES
  WANTED STATE for the reimage:
    SecureBoot            = Enabled
    SecureBootPolicy      = Custom -> should read Standard/Microsoft (attr value 'Standard')
    UefiCaCertScope / UefiVariableAccess-adjacent scope = Device Firmware and OS
    SecureBootMode        = DeployedMode
    TpmSecurity           = On, TpmHierarchy = Enabled
    Pending BIOS jobs     = NONE (clear them before trusting F2/iDRAC changes)
#>
param(
    [Parameter(Mandatory)][string[]]$IdracHost,
    [System.Management.Automation.PSCredential]$Credential
)

# Accept iDRAC self-signed certs for this session only (read-only calls).
try {
    Add-Type -TypeDefinition @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class IdracCertPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@ -ErrorAction SilentlyContinue
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object IdracCertPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
} catch { }

if (-not $Credential) { $Credential = Get-Credential -Message 'iDRAC admin (e.g. root)' }

$attrsOfInterest = @(
    'SecureBoot','SecureBootPolicy','SecureBootMode',
    'UefiCaCertScope','AuthorizeDeviceFirmware',
    'TpmSecurity','TpmHierarchy','BootMode',
    'ProcVirtualization','SecureBootPolicySummary'
)

foreach ($h in $IdracHost) {
    Write-Host ""
    Write-Host "==================== iDRAC $h ====================" -ForegroundColor Cyan
    $base = "https://$h/redfish/v1"
    $hdr  = @{ Accept = 'application/json' }
    $splat = @{ Credential = $Credential; Headers = $hdr; ErrorAction = 'Stop' }
    if ($PSVersionTable.PSVersion.Major -ge 6) { $splat.SkipCertificateCheck = $true }

    # 1) BIOS current attributes
    try {
        $bios = Invoke-RestMethod @splat -Uri "$base/Systems/System.Embedded.1/Bios" -Method Get
        $a = $bios.Attributes
        Write-Host "  --- BIOS security attributes ---" -ForegroundColor Green
        foreach ($name in $attrsOfInterest) {
            if ($a.PSObject.Properties.Name -contains $name) {
                Write-Host ("    {0,-24} = {1}" -f $name, $a.$name)
            }
        }
        # quick verdict
        $sb    = "$($a.SecureBoot)"
        $scope = "$($a.UefiCaCertScope)"
        $mode  = "$($a.SecureBootMode)"
        $verdict = if ($sb -eq 'Enabled' -and $scope -match 'FirmwareAndOs|Firmware and OS|DeviceFirmwareAndOs') { 'LOOKS GOOD' } else { 'CHECK - not in target state' }
        Write-Host ("  VERDICT: SecureBoot=$sb Scope=$scope Mode=$mode -> $verdict") -ForegroundColor Yellow
    } catch {
        Write-Host "  BIOS read FAILED: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Red
    }

    # 2) Pending jobs (the stomp risk)
    try {
        $jobs = Invoke-RestMethod @splat -Uri "$base/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs?`$expand=*(`$levels=1)" -Method Get -ErrorAction Stop
        $pending = @($jobs.Members | Where-Object { "$($_.JobState)" -notmatch 'Completed|Failed' })
        if ($pending.Count -gt 0) {
            Write-Host "  *** PENDING JOBS ($($pending.Count)) - may overwrite settings on reboot ***" -ForegroundColor Red
            $pending | ForEach-Object { Write-Host ("    {0}  {1}  {2}" -f $_.Id, $_.JobState, $_.Name) }
            Write-Host "    -> Clear via iDRAC Maintenance > Job Queue before trusting BIOS state."
        } else {
            Write-Host "  Job queue: clean (no pending jobs)." -ForegroundColor Green
        }
    } catch {
        # older iDRAC path fallback
        try {
            $jobs2 = Invoke-RestMethod @splat -Uri "$base/JobService/Jobs?`$expand=*(`$levels=1)" -Method Get -ErrorAction Stop
            $pending2 = @($jobs2.Members | Where-Object { "$($_.JobState)" -notmatch 'Completed|Failed' })
            if ($pending2.Count -gt 0) {
                Write-Host "  *** PENDING JOBS ($($pending2.Count)) ***" -ForegroundColor Red
                $pending2 | ForEach-Object { Write-Host ("    {0}  {1}" -f $_.Id, $_.JobState) }
            } else {
                Write-Host "  Job queue: clean." -ForegroundColor Green
            }
        } catch {
            Write-Host "  Job-queue read skipped: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor DarkYellow
        }
    }
}
Write-Host ""
Write-Host "READ-ONLY. Nothing was changed. To SET values later, we can add a staged PATCH + one reboot." -ForegroundColor Cyan
