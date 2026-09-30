---
title: "USB install media and Secure Boot"
domain: [platform, security]
layer: [firmware, os]
type: reference
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [secure-boot, usb-media, rufus, fat32, virtual-media, uefi, wim-split, kvm]
updated: 2026-07-15
---

# USB install media and Secure Boot

How to build install media that boots with Secure Boot left enabled.

The whole Secure Boot saga on this project traces back to one thing: the installer would not boot
with Secure Boot on, so it was turned off to finish the install, and the OS then sealed VBS against
Secure Boot being off. Enabling it later fails with `0xc0430001` and cannot be repaired in place.
Getting the media right is the fix.

## Reference content

```text
RUFUS - SECURE-BOOT-CLEAN INSTALL USB (Azure Local POC)
=============================================================
PURPOSE: Build a USB that BOOTS UNDER SECURE BOOT so you can install with
Secure Boot ON from first boot. That makes the OS seal VBS against
Secure-Boot-ON -> NO 0xc0430001, and the CRITICAL SecureBoot validator PASSES.
This is the fix for nodes imaged with SB off (03/04/05/06). 04 + 06 hardware
is already verified good (BIOS 2.5.4, 4 NVMe / 3 poolable, Mellanox up); the
reimage is SEAL-ONLY, not storage/NIC troubleshooting.

*** RE-CORRECTION (2026-07-15): FAT32 *IS* REQUIRED on these 7960s. ***
PROVEN LIVE on node 06: a Rufus NTFS stick (Kingston DT microDuo 3C) was
REJECTED with "UEFI0073: Unable to boot ... because of the Secure Boot policy"
even with factory keys + Policy Standard + scope Device Firmware and OS +
Generic USB Boot enabled. The Rufus UEFI:NTFS shim is NOT trusted by this
firmware's db. So the earlier "NTFS is fine / shim claim outdated" note was
WRONG for this hardware.
WHAT ACTUALLY BOOTS UNDER SECURE BOOT ON THE 7960:
  1. A FAT32 stick (pure Microsoft-signed bootmgfw.efi, NO uefi-ntfs shim) --
     build via the MANUAL FAT32 + WIM-SPLIT method below (install.wim is 5.5 GB
     so it MUST be split to fit FAT32's 4 GB file cap).
  2. Raritan VIRTUAL MEDIA (ISO) -- also pure signed bootmgfw.efi, reaches
     "Loading files" -> WinPE on 06. Downside: streams from your laptop (slow,
     ~5.5 GB, drops if KVM session dies). Only the install-copy phase needs it;
     once files are on the NVMe (first reboot) the stream is done.
  3. iDRAC Remote File Share (NFS/CIFS) IF the iDRAC is licensed (lab iDRACs
     are typically NOT). Survives laptop close since iDRAC pulls from the share.
DO NOT rely on a Rufus NTFS stick for SB-on install on the 7960 -- it UEFI0073s.
How 01/02 got imaged is unclear, but 06 definitively rejects NTFS under SB.

YOU NEED
- Azure Local ISO downloaded from Microsoft.
- USB stick >= 16 GB (ERASED during this).
- Rufus (latest) from rufus.ie.

RUFUS STEPS
1. Insert USB (back up first - it gets wiped).
2. Launch Rufus.
3. Device        = your USB stick (verify the letter!).
4. Boot selection = SELECT -> the Azure Local .iso.
5. Image option  = Standard Windows installation.
6. Partition scheme = GPT.
7. Target system    = UEFI (non CSM).
8. File system      = *** FAT32 REQUIRED for SB-on boot on the 7960. ***
   NTFS was REJECTED with UEFI0073 on node 06 (2026-07-15) -- the Rufus
   uefi-ntfs shim is not trusted by this firmware's Secure Boot db. Because
   install.wim is 5.5 GB (> FAT32's 4 GB cap), Rufus may hide FAT32; if so use
   the MANUAL FAT32 + WIM-SPLIT method below, or boot the Raritan virtual ISO.
9. START.  (If Rufus offers to split a >4GB install.wim, accept - harmless.)
10. Wait for READY (green). Eject.
11. NOTE: the ONE case where NTFS fails but FAT32 boots is if the node's Secure
    Boot db lacks the Microsoft 3rd-party UEFI CA. On the 7960 that CA is
    included by BIOS setting "UEFI CA Certificate Scope = Device Firmware and
    OS" - which we set anyway below. So NTFS is fine once that scope is set.

IF FAT32 IS GREYED OUT / NOT OFFERED (our case - install.wim is 5.55 GB)
- Root cause CONFIRMED: sources\install.wim = 5.55 GB. FAT32 max file size is 4 GB,
  so FAT32 only appears if the tool SPLITS the wim. If Rufus will not show FAT32,
  skip Rufus entirely and build the USB by hand with DISM (below). This is MORE
  Secure-Boot-clean than Rufus (pure Microsoft-signed files, no UEFI:NTFS shim).
- Do NOT fall back to NTFS; that reintroduces the shim Secure Boot rejects.

MANUAL FAT32 + WIM-SPLIT USB (no Rufus) - the reliable method
  Run in an ELEVATED PowerShell on the machine with the USB inserted. Replace
  the disk number and drive letters with YOUR values (check them first!).
  1. Mount the ISO (double-click it, or: Mount-DiskImage -ImagePath <iso>).
     Note its drive letter, e.g. X:.
  2. Format the USB as FAT32 + GPT. In diskpart (ERASES the USB):
       diskpart
       list disk                      (identify the USB by size!)
       select disk N                  (N = your USB disk number)
       clean
       convert gpt
       create partition primary size=32000   (<=32000 MB; FAT32 tool caps at 32 GB)
       format fs=fat32 quick label=AZLOCAL
       assign letter=U
       exit
  3. Copy everything EXCEPT the big wim (robocopy skips it):
       robocopy X:\ U:\ /E /XF install.wim
  4. Split the wim into <4 GB chunks straight onto the FAT32 USB:
       dism /Split-Image /ImageFile:X:\sources\install.wim /SWMFile:U:\sources\install.swm /FileSize:4000
     Creates install.swm + install2.swm; Windows Setup reads the set fine.
  5. Eject. Boots under Secure Boot from FAT32 via Microsoft-signed bootmgfw.efi.
  NOTE if USB > 32 GB: Windows' FAT32 formatter refuses > 32 GB, which is why we
  cap the partition at size=32000. The leftover space is unused - fine for a
  one-shot install stick.

AT THE NODE (06/04 - hardware already good)
1. BIOS: Secure Boot = Enabled, Policy = Standard (Microsoft(R) Boot),
   RESTORE FACTORY KEYS, UEFI CA Certificate Scope = Device Firmware and OS,
   Mode = firmware default (User). *** DEPLOYED MODE IS NOT REQUIRED. ***
   LEAVE SECURE BOOT ON. (No need to disable; the USB boots with it on.)
   WHY (proven 2026-07-15, live db/kek read of 01/02):
     - User Mode and Deployed Mode apply IDENTICAL boot-time signature checks.
       Deployed only hardens key MANAGEMENT; it is not a boot gate. Switching
       User<->Deployed does NOT change whether the Rufus USB boots.
     - What actually makes the USB boot is the KEY DATABASE, not the mode:
       nodes 01/02 (passing) carry, as FACTORY keys, all three of:
         db : Microsoft Corporation UEFI CA 2011   (signs the Rufus uefi-ntfs shim)
         db : Microsoft Windows Production PCA 2011 (signs bootmgfw.efi)
         kek: Microsoft Corporation KEK CA 2011
       Restore Factory Keys re-writes exactly these -> reproduces 01/02's state.
     - The prior USB failure (UEFI0073) was Policy=Custom + narrowed cert scope
       on node 03 removing that OS trust - a KEYS/POLICY problem, fixed here by
       Restore Factory Keys + Policy Standard + scope "Device Firmware and OS".
     - The validator (Test-SecureBoot) checks ONLY Confirm-SecureBootUEFI=True
       (1 of 1). Across 342 AzStackHci module files there are ZERO references to
       DeployedMode/SecureBootMode. The deployment security module reports the
       2023 CAs as INFORMATIONAL/SUCCESS ("# Don't fail the check as all agreed
       for 2604") and the platform self-enrolls the 2023 certs during servicing
       (node 02 passes with NONE of them). Secured-core = the 8 hardware/BIOS
       AvailableSecurityProperties + VBS, none of which is Deployed Mode.
2. F12 boot menu -> UEFI: <your USB>.
2a. *** WIPE THE BOOT NVMe FIRST - MANDATORY ON EVERY NODE (03/04/05/06). ***
    The old SB-off OS is still on the boot disk. If left in place, Setup takes the
    IN-PLACE UPGRADE path ("it looks like you started an upgrade and booted from
    installation media"), reboots into the OLD sealed-for-SB-off OS, and throws
    0xc0430001 again. Proven on node 06 (2026-07-15). A clean install is the ONLY
    thing that seals VBS against SB-on.
    At the first Setup screen press SHIFT+F10 -> cmd, then:
      diskpart
      list disk                 (identify BOOT NVMe by SIZE - the SK hynix PC811,
                                 NOT the 3 poolable data NVMes)
      select disk X             (X = boot NVMe)
      detail disk               (CONFIRM it has the old EFI + Windows volume)
      clean                     (instant + destructive - boot disk ONLY)
      convert gpt
      exit
    Then Install now -> Custom (advanced) -> pick the Unallocated Space -> Next.
    Leave the 3 data NVMes untouched (storage prep happens post-install).
3. Install Windows normally (CUSTOM, not Upgrade). Installs UNDER Secure Boot -> seals correctly.
4. *** DO NOT run SConfig option 6 / Windows Update *** (re-triggers the
   KB5082417/KB5082063 recipe-LCU contamination). Configure network / name /
   RDP only, then run Arc init and let the Azure Local solution channel apply
   the recipe LCUs.

POST-INSTALL CHECKLIST (per node)
- Verify Secure Boot:  .\scripts\Test-SecureBootGate.ps1 -Nodes azl-node-0X
  WANT: SecureBoot=True, VBS=2. SecureBoot validator row now SUCCESS.
- Storage prep: diskpart clear RO + clean data disks -> Update-StorageProviderCache
  -DiscoveryLevel Full -> confirm Get-PhysicalDisk | ? CanPool lists the data disks.
- Full validator: Invoke-AzStackHciHardwareValidation (expect storage + NIC SUCCESS,
  SecureBoot now SUCCESS; GPU stays a benign WARNING).
- Then Onboard-ArcMachine.ps1 (delete any stale AZL-NODE-0X Arc resource first).

WHY THIS BEATS IN-PLACE TOGGLE (proven 2026-07-14)
- In-place Secure Boot enable = 0xc0430001 on 03, 05, AND 06 (only 02 ever worked).
  1-of-4. The OS was sealed for SB-off; flipping SB on can't re-seal it.
- Installing with SB ON from first boot is the reliable fix. 40-min reimage, but
  it actually sticks.
```
