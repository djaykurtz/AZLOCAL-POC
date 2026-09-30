[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$NodeFqdn,
  [string]$Username = 'Administrator',
  [string]$CredFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred')
)

$ErrorActionPreference = 'Stop'
$short = ($NodeFqdn -split '\.')[0]

$cipher = Get-Content -Path $CredFile -Raw
$pw     = ConvertTo-SecureString $cipher.Trim()
$cred   = [pscredential]::new("$short\$Username", $pw)

$s = New-PSSession -ComputerName $NodeFqdn -Credential $cred -Authentication Negotiate
try {
  $r = Invoke-Command -Session $s -ScriptBlock {
    $h = [ordered]@{}
    $h.RAM_GB        = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB, 0)
    $h.DIMMs         = (Get-CimInstance Win32_PhysicalMemory).Count
    $h.DIMM_Detail   = Get-CimInstance Win32_PhysicalMemory |
      Select-Object BankLabel, @{n='GB';e={[math]::Round($_.Capacity/1GB,0)}}, Speed, Manufacturer, PartNumber
    $h.CPU           = Get-CimInstance Win32_Processor |
      Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
    $h.Disks_Disk    = Get-Disk |
      Select-Object Number, FriendlyName, @{n='GB';e={[math]::Round($_.Size/1GB,0)}}, BusType, PartitionStyle, IsBoot, OperationalStatus
    $h.Disks_Phys    = Get-PhysicalDisk |
      Select-Object DeviceId, FriendlyName, MediaType, @{n='GB';e={[math]::Round($_.Size/1GB,0)}}, BusType, CanPool, HealthStatus
    $h.SCSI_Ctlrs    = Get-CimInstance Win32_SCSIController |
      Select-Object Name, Manufacturer, Status
    $h.NICs          = Get-NetAdapter |
      Select-Object Name, Status, LinkSpeed, MediaConnectionState, MacAddress, InterfaceDescription

    # --- Azure Local prereq checks ----------------------------------------
    # TPM 2.0
    $tpm = $null
    try { $tpm = Get-Tpm -ErrorAction Stop } catch {}
    $tpmWmi = $null
    try {
      $tpmWmi = Get-CimInstance -Namespace 'Root\CIMv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
    } catch {}
    $h.TPM = [pscustomobject]@{
      Present       = [bool]($tpm -or $tpmWmi)
      Enabled       = if ($tpm) { [bool]$tpm.TpmEnabled } elseif ($tpmWmi) { [bool]$tpmWmi.IsEnabled_InitialValue } else { $null }
      Activated     = if ($tpm) { [bool]$tpm.TpmActivated } elseif ($tpmWmi) { [bool]$tpmWmi.IsActivated_InitialValue } else { $null }
      Owned         = if ($tpm) { [bool]$tpm.TpmOwned } elseif ($tpmWmi) { [bool]$tpmWmi.IsOwned_InitialValue } else { $null }
      SpecVersion   = if ($tpmWmi) { $tpmWmi.SpecVersion } else { $null }
      ManufacturerId = if ($tpmWmi) { $tpmWmi.ManufacturerIdTxt } else { $null }
    }

    # Secure Boot
    $sb = $null
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { $sb = $_.Exception.Message }
    $h.SecureBoot = $sb

    # ECC memory (MemoryErrorCorrection: 5=Single-bit ECC, 6=Multi-bit ECC, 7=CRC, 3=None, 4=Parity)
    $memArr = Get-CimInstance Win32_PhysicalMemoryArray
    $eccMap = @{0='Reserved';1='Other';2='Unknown';3='None';4='Parity';5='Single-bit ECC';6='Multi-bit ECC';7='CRC'}
    $h.MemoryECC = $memArr | Select-Object Tag, MemoryDevices, @{n='ECC';e={ $eccMap[[int]$_.MemoryErrorCorrection] }}, MemoryErrorCorrection

    # Virtualization enabled in BIOS (Hyper-V firmware feature)
    #
    # WARNING: When a Type-1 hypervisor (Hyper-V) is already running in
    # the root partition, Win32_Processor returns paravirtualized CPU
    # descriptors and these flags will report $false even when VT-x,
    # VT-d, and SLAT are actually enabled in BIOS. This bit the lab
    # POC on 2026-06-09 - see decisions/0002-vtx-slat-false-positive.md.
    #
    # We therefore also capture HypervisorPresent so any downstream
    # reader knows when to ignore the BIOS flags entirely. When
    # HypervisorPresent is True, the only honest answer is "must be on,
    # or the hypervisor could not be running" - cross-check with
    # Get-ComputerInfo HyperVRequirement*, bcdedit hypervisorlaunchtype,
    # or scripts/Get-VirtualizationSignals.ps1 for an authoritative read.
    $cpu1 = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cs   = Get-CimInstance Win32_ComputerSystem
    $h.Virtualization = [pscustomobject]@{
      HypervisorPresent                       = [bool]$cs.HypervisorPresent
      VirtualizationFirmwareEnabled           = $cpu1.VirtualizationFirmwareEnabled
      VMMonitorModeExtensions                 = $cpu1.VMMonitorModeExtensions
      SecondLevelAddressTranslationExtensions = $cpu1.SecondLevelAddressTranslationExtensions
      Note = if ($cs.HypervisorPresent) {
        'Hypervisor running - BIOS flags above are unreliable, treat VT-x/SLAT as enabled.'
      } else {
        'Hypervisor not running - BIOS flags above reflect actual firmware state.'
      }
    }

    # Firmware mode (UEFI vs Legacy BIOS)
    $h.FirmwareType = (Get-CimInstance Win32_ComputerSystem).BootupState
    $h.UEFI         = (Test-Path 'HKLM:\System\CurrentControlSet\Control\SecureBoot\State')

    [pscustomobject]$h
  }
}
finally { Remove-PSSession $s }

$outFile = Join-Path (Split-Path -Parent $PSScriptRoot) "out\_$short-live.json"
$r | ConvertTo-Json -Depth 6 | Set-Content -Path $outFile -Encoding utf8
"Wrote $outFile"

Write-Host "`n--- RAM ---" -ForegroundColor Cyan
"  Total: $($r.RAM_GB) GB in $($r.DIMMs) DIMMs"
$r.DIMM_Detail | Format-Table -AutoSize

Write-Host "--- CPU ---" -ForegroundColor Cyan
$r.CPU | Format-Table -AutoSize

Write-Host "--- Disks (Get-Disk) ---" -ForegroundColor Cyan
$r.Disks_Disk | Format-Table -AutoSize

Write-Host "--- Physical Disks (Get-PhysicalDisk) ---" -ForegroundColor Cyan
$r.Disks_Phys | Format-Table -AutoSize

Write-Host "--- Storage Controllers ---" -ForegroundColor Cyan
$r.SCSI_Ctlrs | Format-Table -AutoSize

Write-Host "--- NICs ---" -ForegroundColor Cyan
$r.NICs | Format-Table Name, Status, LinkSpeed, MediaConnectionState, InterfaceDescription -AutoSize

Write-Host "--- TPM ---" -ForegroundColor Cyan
$r.TPM | Format-List

Write-Host "--- Secure Boot ---" -ForegroundColor Cyan
"  $($r.SecureBoot)"

Write-Host "`n--- Memory ECC ---" -ForegroundColor Cyan
$r.MemoryECC | Format-Table -AutoSize

Write-Host "--- Virtualization (BIOS) ---" -ForegroundColor Cyan
$r.Virtualization | Format-List
