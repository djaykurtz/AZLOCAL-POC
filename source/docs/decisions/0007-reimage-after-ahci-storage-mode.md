---
title: "0007 - Recover storage mode by reimaging after AHCI/Non-RAID"
domain: [storage]
layer: [firmware, os]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, ahci, raid, vroc, reimage]
updated: 2026-08-20
---

# 0007 - Recover storage mode by reimaging after AHCI/Non-RAID

- **Status**: Active
- **Date**: 2026-06-19
- **Owner**: labadmin
- **Revisit when**:
  - A node boots successfully after changing to AHCI/Non-RAID and all data disks validate without reimage, OR
  - Dell BIOS exposes a per-slot/per-port VMD/VROC setting that lets the boot disk remain VROC while Slot 6 data disks are plain NVMe, OR
  - AD computer objects are later created and begin affecting hostname reuse.

## Observe

- Early prerequisite docs asked for direct-attached storage, not RAID:
  - [poc_prereq_checklist.notes.txt](../../archive/docs/poc_prereq_checklist.notes.txt): "Set storage controller to HBA / passthrough mode, NOT RAID" and "Convert to Non-RAID".
  - [poc_prereq_checklist.txt](../../archive/docs/planning/poc_prereq_checklist.txt) and the deployment wizard answer sheet: same HBA/passthrough, NOT RAID instruction; Storage Spaces Direct requires HBA/passthrough mode per the Phase 0 BIOS checklist.
- Later, [bios-ideal-state.md](../storage-imaging/bios-ideal-state.md) translated that generic server/HBA language into the Precision 7960 Rack settings: sSATA/tSATA AHCI, NVMe Non-RAID/AHCI, Intel VROC disabled, Slot 6 x4/x4/x4/x4.
- Node01 testing showed one added Samsung PM9A1 could enumerate through the add-in path, but both boot and data candidate disks were exposed as `BusType=RAID` behind Intel Volume Management Device / VROC.
- Azure Local hardware validation rejected the added PM9A1 with `BusTypeIsSupported=False` and `CanPool=False`.
- Local admin later found an area where the main drive and all drives were set to RAID. After switching to AHCI/Non-RAID, normal detection is expected, but the existing OS may not boot because it was installed while the boot disk was VROC/RAID-presented.
- AD scans on 2026-06-19 found no `AZL-NODE-01..06` or `AZL-CL01` computer objects in either `corp.example.com` or `corp.example.com`. Reachable nodes 04 and 06 report `WORKGROUP`, not domain-joined.

## Orient

- The root storage problem is platform storage mode, not the ASUS PCIe carrier.
- For Azure Local S2D, data disks must be direct-attached and poolable. A disk shown as `BusType=RAID` is rejected even if it is physically NVMe.
- Preserving the existing OS install mattered less than getting the final storage presentation correct. The POC is still pre-cluster; reimaging now is cheaper than discovering unsupported data disks during cluster deployment.
- Hostname reuse is currently safe from an AD perspective because no matching AD computer objects were found and the reachable nodes are still workgroup joined.
- Reimage does create Azure Arc rework because the local Arc agent identity/state is lost. Arc cleanup/re-onboarding is the main control-plane recovery task, not AD rename.

## Decide

Use Non-RAID storage presentation as the final mode. If a node was installed while the boot/data path was set to RAID/VROC, set the final Non-RAID BIOS state and reimage it rather than trying to preserve the current OS. Keep the existing `AZL-NODE-0X` names.

## Act

- Preserve hostnames: `AZL-NODE-01..06` as assigned. The recovery issue is RAID/VROC storage presentation, not lack of drives.
- For any node found in RAID/VROC storage mode, reimage with final BIOS storage settings already applied:
  - sSATA/tSATA = AHCI
  - NVMe mode = Non-RAID/plain NVMe (AHCI wording may not appear for NVMe)
  - Intel VROC disabled where possible
  - Slot 6 bifurcation = x4/x4/x4/x4
- Do not ask local admin to run `bcdedit` or attempt a Safe Mode storage conversion.
- Do not domain-join manually; Azure Local deployment handles domain join later.
- After reimage, rerun post-image setup and validation:
  - [scripts/Invoke-PostImageAll.ps1](../../scripts/Invoke-PostImageAll.ps1)
  - [scripts/Get-NodeHardware.ps1](../../scripts/Get-NodeHardware.ps1)
  - [scripts/Invoke-HardwareValidator.ps1](../../scripts/Invoke-HardwareValidator.ps1)
- Expect possible Arc cleanup/re-onboarding for existing Arc machine resources. Do not rename nodes to work around Arc; repair or recreate Arc records instead.
- Evidence files from the pre-reimage state include:
  - `out/_storage-raid-survey-20260619-114609.json`
  - `out/_hardware-azl-node-01-20260619-114622.json`
  - `out/_node01-physicaldisk-validator-detail-20260619-114622.json`
  - `out/_ad-computer-scan-azl-node-20260619-162044.csv`
  - `out/_ad-computer-scan-azl-node-corp-20260619-162105.csv`

