---
title: "BIOS ideal state per node"
domain: [platform, storage]
layer: [firmware, hardware]
type: reference
depth: quickref
status: current
proof: proven
audience: [engineer, operator]
tags: [bios, dell-precision-7960, secure-boot, bifurcation, slot-disablement, tpm, smart-hands]
updated: 2026-06-30
---

# BIOS ideal state per node

The single reference for the BIOS settings every node must land on before the cluster is built.
Pull this up at the KVM or paste it into a smart-hands handoff.

This document exists because the storage and NIC requirements were once buried as sub-bullets in a
checklist and got missed for weeks. Hard requirements get their own page.

## Reference content

```text
========================================================================
  AZURE LOCAL POC // BIOS IDEAL STATE (per node)
========================================================================
  Target hardware:  Dell Precision 7960 Rack (Intel Xeon Silver 4410Y,
                    Sapphire Rapids 4th gen)
  Nodes in scope:   AZL-NODE-01..06 when assigned for prep/reimage
  First cluster:    AZL-NODE-01..04 unless the POC expands to 6 nodes

  Purpose: Single reference for the BIOS settings each node must land
  on before the cluster is built. Pull this up at the KVM (or paste it
  into the local admin handoff) so nobody has to go hunting for
  "what was that setting again?". This is the cure for the
  buried-in-comments documentation failure that cost us the original
  storage spec.

  Owner:    [LOCAL ADMIN] sets, [PLATFORM] verifies post-boot via WinRM
  Source:   BIOS Slot Bifurcation screenshot captured from
            AZL-NODE-01 during the procurement decision, 2026-06-11
  See also: decisions/0003-storage-spec-lock.md
            poc_prereq_checklist.txt   (Phase 0)
            poc_prereq_checklist.notes.txt (Phase 0 source)

  Status legend:
    [BASELINE]   already validated across all 4 nodes, do not change
    [CHANGE]     must be set/verified during the local admin pass
    [VERIFY]     should already be correct, local admin eyeballs it

========================================================================
  PHYSICAL CARD LAYOUT (slot map confirmed from BIOS screenshot)
========================================================================
  Slot 1   x4    open / unused
  Slot 2   x4    open / unused
  Slot 3   x4    open / unused
  Slot 4   x8    Mellanox ConnectX-5 (100Gbps RDMA) -- verify, do NOT
                 displace
  Slot 5   x8    Mellanox ConnectX-5 (100Gbps RDMA) -- verify, do NOT
                 displace
  Slot 6   x16   RIITOP Quad PCIe NVMe carrier (replaces ASUS, ADR 0008)
                 holding 2x KIOXIA KXG80ZNV512G M.2 NVMe drives
                 (card has 4 M.2 sockets; we populate 2)
  Slot 7   x4    open / unused

  Hard rule: do NOT install the quad M.2 carrier in any slot other
  than Slot 6. Only Slot 6 is x16-capable and only Slot 6 exposes a
  multi-segment bifurcation alignment. NOTE (2026-06-30): this board's
  Slot 6 menu does NOT offer x4/x4/x4/x4 -- the available split is
  x4/x4/x8. That is FINE: the two x4 segments give two independent x4
  NVMe endpoints, which covers our 2-drive-per-node requirement.
  Slot 4 and Slot 5 are x8 with x4/x4 -- reserved for the Mellanox NICs.

========================================================================
  BIOS SETTINGS TABLE
========================================================================
  | # | Setting                  | Old / Default      | Target value          | Why / Notes                                                |
  | - | ------------------------ | ------------------ | --------------------- | ---------------------------------------------------------- |
  | 1 | SATA Operation (sSATA)   | RAID / VROC        | AHCI                  | [CHANGE] No drives on it now; cleanest if added later.     |
  | 2 | SATA Operation (tSATA)   | RAID / VROC        | AHCI                  | [CHANGE] Same as above. Keep SATA paths non-RAID too.      |
  | 3 | NVMe Mode (onboard M.2)  | RAID On            | Non-RAID / AHCI       | [CHANGE] Cleans the BusType=RAID artifact on the boot drv. |
  |   |                          |                    |                       | CAVEAT: flipping this may break boot of the existing       |
  |   |                          |                    |                       | SK hynix PC811 install. See "Boot drive caveat" below.     |
  | 4 | Intel VROC               | Enabled            | Disabled              | [CHANGE] S2D does not use VROC. Remove to drop confusion.  |
  | 5 | Slot 6 Bifurcation       | Auto               | x4/x4/x8              | [CHANGE] x4/x4/x4/x4 is NOT offered on this board; x4/x4/x8 |
  |   |                          |                    |                       | is the available split. The two x4 segments each present   |
  |   |                          |                    |                       | one M.2 at x4 -> covers our 2 data drives per node.        |
  |   |                          |                    |                       | Populate the FIRST TWO M.2 sockets (the x4 segments).      |
  |   |                          |                    |                       | "Auto Discovery Bifurcation" should also stay enabled.     |
  | 6 | Boot Mode                | UEFI               | UEFI                  | [VERIFY] S2D + Secure Boot both require UEFI.              |
  | 7 | Secure Boot              | Enabled            | Enabled               | [BASELINE] Already validated across all 4 nodes.           |
  | 8 | TPM 2.0                  | Enabled            | Enabled               | [BASELINE] Already validated across all 4 nodes.           |
  | 9 | Intel VT-x               | Enabled            | Enabled               | [VERIFY] Required for Hyper-V. WMI gives a false negative  |
  |   |                          |                    |                       | inside the root partition; see decisions/0002-vtx-slat-... |
  |10 | Intel VT-d               | Enabled            | Enabled               | [VERIFY] Required for Hyper-V / SR-IOV passthrough.        |
  |11 | Execute Disable (XD bit) | Enabled            | Enabled               | [VERIFY] Required for hardware-enforced DEP.               |
  |12 | Boot order               | varies             | M.2 NVMe (boot) first | [VERIFY] OS already installed; just confirm boot device.   |

========================================================================
  PCIE SLOT BIFURCATION PAGE (from screenshot)
========================================================================
  System Setup > Device Settings > Integrated Devices > Slot Bifurcation

  HOW THIS BOARD'S BIFURCATION WORKS (confirmed 2026-06-30):
  There is NO per-slot "bifurcation on/off" toggle. Instead there is one
  GLOBAL "Auto Discovery Bifurcation Settings" switch, and then EACH slot
  gets an ALIGNMENT value (x16 / x8/x8 / x4/x4/x4/x4 etc) describing how
  that slot's lanes are sliced. You do NOT enable/disable per slot -- you
  pick how each slot splits its lanes.
    - Alignment = how many independent endpoints the slot presents:
        x16            -> 1 device gets all lanes  (only FIRST M.2 shows)
        x8/x8          -> 2 endpoints              (only 2 M.2 show)
        x4/x4/x8       -> 3 endpoints              (3 M.2 show; 2 at x4 +
                                                    1 on the x8 at x4)
        x4/x4/x4/x4    -> 4 endpoints  (NOT offered on this board)
    - For a PASSIVE quad M.2 carrier each M.2 needs its own x4 link. We
      only populate 2 drives, so x4/x4/x8 is sufficient: put both drives
      in the two x4-segment sockets (first two M.2 sockets on the card).
  ONLY change Slot 6. Leave all other slots at their defaults.

  - Auto Discovery Bifurcation Settings ............. Enabled
  - Slot 1 Bifurcation .............................. (n/a, x4 native)
  - Slot 2 Bifurcation .............................. (n/a, x4 native)
  - Slot 3 Bifurcation .............................. (n/a, x4 native)
  - Slot 4 Bifurcation Control ...................... x4/x4 (available;
                                                       leave alone)
  - Slot 5 Bifurcation Control ...................... x4/x4 (available;
                                                       leave alone)
  - Slot 6 Bifurcation Control ...................... x4/x4/x4/x4
                                                       (REQUIRED)
  - Slot 7 Bifurcation .............................. (n/a, x4 native)

  Fallback if Auto Discovery does not enumerate all 4 drives after
  installing the ASUS card: switch Slot 6 from "Auto" to "Manual" and
  set the bifurcation explicitly to x4/x4/x4/x4.

  2026-06-18 node01 pilot note: ASUS card + 2x KIOXIA drives are installed
  in AZL-NODE-01, and smart-hands/user report Slot 6 Bifurcation is
  x4/x4/x4/x4. Windows still sees no KIOXIA/NVMe data disks. If this state
  repeats after a full power-cycle, focus on physical socket labels
  (M2_1/M2_2), card seating in Slot 6, and BIOS NVMe/device inventory.
  Do not initialize disks until Windows actually enumerates new disks.

  2026-06-19 node01 follow-up: a different card / different NVMe drive
  enumerated one Samsung PM9A1 device, but Windows reports it as
  BusType=RAID behind Intel VMD/VROC and it has existing GPT/OS-like
  partitions. For Azure Local data disks, BIOS should expose add-in-card
  data NVMe as plain NVMe if possible; do not disable global VMD/VROC if it
  would strand the existing boot disk without an OS reinstall plan.

========================================================================
  BOOT DRIVE CAVEAT (read before flipping NVMe mode)
========================================================================
  All 4 nodes currently boot from an onboard SK hynix PC811 ~954 GB
  NVMe via Intel VROC (Get-PhysicalDisk reports BusType=RAID for that
  device, which is the tell). The cluster validator does not require
  the boot drive to be on any specific bus type -- it just must not be
  pooled into the S2D set, which it won't be.

  Two paths for setting #3 (NVMe Mode -> Non-RAID / AHCI):

  Path A (cleanest, more work):
    - Flip NVMe Mode to Non-RAID / AHCI.
    - Wipe + reinstall Azure Stack HCI OS on the boot drive (it will
      now enumerate as BusType=NVMe instead of BusType=RAID).
    - Pro: no VROC artifacts anywhere; spec is uniformly clean.
    - Con: re-runs the imaging step from Phase 0 of the checklist.

  Path B (pragmatic, what we will actually do):
    - LEAVE NVMe Mode at "RAID On" for now (boot drive stays on VROC).
    - Only fix the data-tier-relevant settings (#1, #2, #4, #5).
    - Pro: zero downtime; existing OS install + Arc onboarding survives.
    - Con: Get-PhysicalDisk will continue to show BusType=RAID for the
      boot drive. Documented and benign -- the boot drive is excluded
      from the S2D pool by IsBootDevice=True, not by BusType.

  Decision update 2026-06-19 (ADR 0007): the storage-mode pilot showed
  add-in data NVMe can be captured by VMD/VROC and rejected as BusType=RAID.
  If a node was installed with the storage path set to RAID/VROC, set the
  final Non-RAID/plain NVMe BIOS state and reimage it. Do not spend time
  preserving a VROC-installed OS before cluster deployment.

========================================================================
  SMART-HANDS ONE-PASS PROCEDURE
========================================================================
  The chassis is being opened once to install the ASUS Hyper M.2 X16
  Gen 4 + 2x KIOXIA M.2 NVMe drives per node. Do all of the BIOS
  changes in the same window. The full pass per node is:

  1. Power off node; pull chassis.
  2. Seat 2x KIOXIA M.2 NVMe drives onto the ASUS Hyper M.2 card
     (sockets M2_1 and M2_2; use the standoffs + screws in the bag;
     keep the included heatsinks attached).
  3. Install ASUS card into Slot 6.
     - Verify card is fully seated and the PCIe latch clicks.
     - Plug the card's onboard fan into a chassis fan header if one is
       free (otherwise it free-spins on standby +12V, which is fine).
  4. Reseat chassis; power on; F2 into BIOS.
  5. Apply BIOS table above (settings #1, #2, #3-Path-B-or-A, #4, #5).
     - VERIFY #6-#11 are in their target state while you are in there.
  6. Save + exit. Reboot.
  7. Smart-hands signs off. The platform team takes over via WinRM for
     verification (next section).

  Per-node time estimate: 20-30 min including card install, BIOS pass,
  and reboot.

========================================================================
  POST-BOOT VERIFICATION (platform team, from DevBox)
========================================================================
  After smart-hands signs off, from c:\tools\POC-AzureLocal run:

    .\scripts\Invoke-PostImageAll.ps1 -Nodes azl-node-01

  Then quick checks via WinRM (replace the hostname for each node):

    $s = New-PSSession -ComputerName azl-node-01.lab.example.com `
           -Credential (Get-Credential)

    # 1. Drives enumerate as NVMe and are poolable
    Invoke-Command -Session $s -ScriptBlock {
      Get-PhysicalDisk |
        Where-Object BusType -eq 'NVMe' |
        Format-Table FriendlyName, Size, MediaType, BusType, `
                     CanPool, CannotPoolReason, HealthStatus
    }
    # Expected: 2 rows per node, ~512 GB each, MediaType=SSD,
    # BusType=NVMe, CanPool=True, CannotPoolReason=None.

    # 2. VROC artifact gone (only if Path A was taken)
    Invoke-Command -Session $s -ScriptBlock {
      Get-PhysicalDisk |
        Where-Object IsBoot -eq $true |
        Format-Table FriendlyName, BusType, IsBoot
    }
    # If Path A: BusType=NVMe on the boot drive too.
    # If Path B: BusType=RAID on the boot drive (expected, benign).

    # 3. Virtualization signals still healthy
    Invoke-Command -Session $s -ScriptBlock {
      (Get-ComputerInfo).HyperVisorPresent
    }
    # Expected: True (see decisions/0002 for the WMI false-negative
    # gotcha if you are tempted to query VT-x directly).

    Remove-PSSession $s

  Then re-run the cluster validator on all 4 nodes:

    .\scripts\Invoke-HardwareValidator.ps1 -NodeNumbers @(1,2,3,4)

  Acceptance: zero CRITICAL failures on the data-disk check.

========================================================================
  RAM SIDE NOTE (not BIOS, but in the same smart-hands window)
========================================================================
  Each node currently reports 31.5 GB visible RAM (BMC carves ~512 MB
  out of 32 GB physical). Azure Local enforces a 32 GB minimum.

  Current POC direction as of 2026-06-18: assume no additional RAM is
  available. Proceed with storage install, re-run hardware validation,
  and escalate RAM only if the Azure Local validator explicitly blocks
  on memory.

========================================================================
  FUTURE: REMOTE BIOS AUTOMATION
========================================================================
  Once iDRAC is licensed and reachable from the platform team VPN, every
  setting in the BIOS Settings Table can be applied via Ansible
  (dellemc.openmanage collection) over Redfish. The work to convert
  this document into an Ansible task list is small once iDRAC is
  available -- the field names line up directly with the Redfish
  attribute registry for the Precision 7960 platform.

  Until then: KVM + manual setup. Slow but reliable.
```
