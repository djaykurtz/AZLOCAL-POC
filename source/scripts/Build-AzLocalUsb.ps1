# =====================================================================
# Build-AzLocalUsb.ps1  --  FAT32 Secure-Boot-clean Azure Local install USB
# =====================================================================
# WHY: Rufus will not offer FAT32 because sources\install.wim is 5.55 GB
# (FAT32 max file = 4 GB). This script formats the USB FAT32+GPT, copies
# everything EXCEPT install.wim, then SPLITS the wim into <4 GB .swm parts
# with DISM. Result boots under Secure Boot via Microsoft-signed
# bootmgfw.efi (no Rufus UEFI:NTFS shim that Secure Boot rejects).
#
# RUN THIS ON THE TECH'S MACHINE (the one with the USB), ELEVATED.
#   powershell -ExecutionPolicy Bypass -File .\Build-AzLocalUsb.ps1 -IsoPath <iso> -UsbDiskNumber <N>
#
# It REFUSES to touch a non-USB/non-removable disk and shows you the disk
# + asks you to type YES before it wipes anything.
# =====================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][int]$UsbDiskNumber,
    [string]$Label = 'AZLOCAL',
    [int]$Fat32PartitionMB = 32000   # <=32000; Windows FAT32 formatter caps at 32 GB
)

$ErrorActionPreference = 'Stop'
function Say($m,$c='Cyan'){ Write-Host $m -ForegroundColor $c }

# --- Validate ISO ----------------------------------------------------
if (-not (Test-Path $IsoPath)) { throw "ISO not found: $IsoPath" }

# --- Validate target disk is really a USB / removable ----------------
$disk = Get-Disk -Number $UsbDiskNumber -ErrorAction Stop
Say "`nTarget disk $UsbDiskNumber :" Yellow
$disk | Select-Object Number,FriendlyName,@{n='GB';e={[math]::Round($_.Size/1GB,1)}},BusType,OperationalStatus | Format-Table -Auto | Out-String | Write-Host
if ($disk.BusType -notin @('USB','SD')) {
    throw "REFUSING: disk $UsbDiskNumber BusType is '$($disk.BusType)', not USB/SD. Aborting to protect internal disks."
}
if ($disk.Size -gt 256GB) {
    throw "REFUSING: disk $UsbDiskNumber is $([math]::Round($disk.Size/1GB))GB (>256GB). That is unlikely to be your install stick. Aborting."
}

# --- Explicit human confirmation -------------------------------------
Say "`n*** THIS WILL ERASE ALL DATA ON DISK $UsbDiskNumber ($($disk.FriendlyName)). ***" Red
$ans = Read-Host "Type YES (all caps) to wipe and build the USB"
if ($ans -ne 'YES') { Say "Aborted by user (no changes made)." Yellow; return }

# --- Mount ISO -------------------------------------------------------
Say "`nMounting ISO..."
$img = Mount-DiskImage -ImagePath $IsoPath -PassThru
Start-Sleep -Seconds 2
$isoDrive = ($img | Get-Volume).DriveLetter
if (-not $isoDrive) { throw "Could not determine ISO drive letter after mount." }
$isoRoot = "$isoDrive`:"
Say "ISO mounted at $isoRoot" Green
$wim = Join-Path $isoRoot 'sources\install.wim'
if (-not (Test-Path $wim)) { Dismount-DiskImage -ImagePath $IsoPath | Out-Null; throw "install.wim not found in ISO at $wim" }

try {
    # --- Partition + format FAT32 + GPT via diskpart script ----------
    Say "`nFormatting disk $UsbDiskNumber as GPT + FAT32 ($Fat32PartitionMB MB)..."
    $dp = @"
select disk $UsbDiskNumber
clean
convert gpt
create partition primary size=$Fat32PartitionMB
format fs=fat32 quick label=$Label
assign
exit
"@
    $dpFile = Join-Path $env:TEMP "azusb-$(Get-Random).txt"
    $dp | Set-Content -Path $dpFile -Encoding ascii
    diskpart /s $dpFile | Out-String | Write-Host
    Remove-Item $dpFile -Force -ErrorAction SilentlyContinue

    # --- Resolve the new USB drive letter ----------------------------
    Start-Sleep -Seconds 2
    $usbVol = Get-Partition -DiskNumber $UsbDiskNumber | Get-Volume | Where-Object { $_.FileSystem -eq 'FAT32' } | Select-Object -First 1
    if (-not $usbVol.DriveLetter) { throw "USB FAT32 volume has no drive letter after format." }
    $usbRoot = "$($usbVol.DriveLetter):"
    Say "USB is $usbRoot" Green

    # --- Copy everything except the big wim --------------------------
    Say "`nCopying ISO contents (excluding install.wim) to $usbRoot ..."
    robocopy "$isoRoot\" "$usbRoot\" /E /XF install.wim /NFL /NDL /NJH /NJS /NP | Out-Null
    Say "Base files copied." Green

    # --- Split the wim into <4GB parts straight onto FAT32 -----------
    Say "`nSplitting install.wim into <4GB .swm parts (this takes a few minutes)..."
    $swm = Join-Path $usbRoot 'sources\install.swm'
    dism /Split-Image /ImageFile:$wim /SWMFile:$swm /FileSize:4000 | Out-String | Write-Host

    # --- Verify ------------------------------------------------------
    $parts = Get-ChildItem (Join-Path $usbRoot 'sources') -Filter 'install*.swm' -ErrorAction SilentlyContinue
    $boot  = Test-Path (Join-Path $usbRoot 'efi\boot\bootx64.efi')
    Say "`n== RESULT ==" Cyan
    Say ("  .swm parts: {0} ({1})" -f $parts.Count, (($parts.Name) -join ', ')) Green
    Say ("  UEFI bootloader present (efi\boot\bootx64.efi): {0}" -f $boot) ($(if($boot){'Green'}else{'Red'}))
    if ($parts.Count -ge 1 -and $boot) {
        Say "`nUSB READY. Eject, boot node with Secure Boot ON, F12 -> UEFI: <USB>." Green
    } else {
        Say "`nSomething is missing - re-check the steps." Red
    }
}
finally {
    Say "`nDismounting ISO..."
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
}
