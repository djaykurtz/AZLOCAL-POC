---
title: "0011 - Standardize on 3 data NVMe disks per node (up from 2)"
domain: [storage]
layer: [hardware]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, data-disks, symmetry, storage-spaces-direct]
updated: 2026-07-13
---

# 0011 - Standardize on 3 data NVMe disks per node (up from 2)

- **Status**: Active
- **Date**: 2026-07-10
- **Owner**: labadmin
- **Supersedes**: the drive-count portion of [0003](0003-storage-spec-lock.md)
  (which locked 2 data disks/node). The S2D symmetry rationale in 0003 still stands.
- **Revisit when**:
  - Any node cannot physically seat 3 M.2 drives on the RIITOP carrier
    (bifurcation/slot limit), forcing a return to 2/node fleet-wide, OR
  - The cluster is expanded and the count must be applied to new nodes.

## Observe

- ADR 0003 locked **2** data NVMe disks per node. Node 01 validated storage with
  2 data disks (Samsung PM9A1 512GB), and PASSED
  (`Invoke-AzStackHciHardwareValidation`: all 6 disk/storage checks SUCCESS).
  One of the two data drives trained at PCIe x2 instead of x4 - non-blocking for
  validation, but a marginal seat.
- The RIITOP quad PCIe carrier (ADR 0008) with Slot 6 bifurcation `x4/x4/x8`
  exposes multiple independent NVMe endpoints as `BusType=NVMe`.
- Node 02, after the 3x-NVMe hardware change, presents **4 NVMe total**:
  - Disk 0 = SK hynix PC811 954GB = boot/system (excluded from pool).
  - Disks 1/2/3 = Samsung PM9A1 512GB = data.
- The 3 data disks arrived GPT-partitioned (`CanPool=False`,
  `CannotPoolReason=Insufficient Capacity`). After clearing them (diskpart
  `clean` on the data disks only, then `Update-StorageProviderCache
  -DiscoveryLevel Full`) all 3 flip to `CanPool=True`. Boot disk untouched.
- Size floor: PM9A1 = 512,110,190,592 bytes = 476.94 GiB = **512.11 GB decimal**.
  The real validator compares the DECIMAL-GB floor (>=500 GB), so these PASS
  (empirically confirmed on node 01; see repo memory / risk register).
- Azure Local add-server enforces a HARD gate: a node being added must have the
  **same number of data drives** as the cluster, or the add is BLOCKED. The
  hardware validator also runs `PhysicalDisk-GroupConsistency` and
  `PhysicalDisk-InstanceCountByGroup` checks that flag asymmetric drive counts.

## Orient

- Moving to 3 data disks/node buys: more S2D rebuild/repair headroom, and it lets
  us drop the marginal x2-trained drive from node 01 rather than depend on it.
- The cost is one extra 512GB M.2 per node - already the plan for the fleet
  (nodes 03-06 are down specifically for the 3x-NVMe change).
- **Symmetry is the binding constraint, not the count itself.** Whatever number
  we pick, every deployed node must match it. Mixing 2-disk and 3-disk nodes
  would fail GroupConsistency/InstanceCountByGroup and block add-server. So the
  decision is really "pick one count and apply it to ALL nodes" - and 3 is the
  better count for the reasons above.
- Node 01 currently sits at 2 data disks; to keep the fleet symmetric it must be
  brought to 3 as well before multi-node deployment (or the fleet standardizes at
  whatever count node 01 ends up at - but 3 is the target).

## Decide

Standardize on **3 data NVMe disks per node** (1 boot + 3 data = 4 NVMe total),
applied uniformly to every deployed node. Drive-count symmetry across nodes is a
hard requirement; no mixed-count fleet.

**Vendor is NOT part of the spec — capacity + media are.** The standard is
"3x 512GB-class NVMe SSD per node," VENDOR-AGNOSTIC. Mixed vendors are expected
and acceptable (fleet already runs Samsung PM9A1 on nodes 01-04 and KIOXIA
KXG80ZNV512G on nodes 05-06; future drives may be either). S2D groups physical
disks by CHARACTERISTICS (media type, bus type, size), not by make/model, so
same-size/same-media disks from different vendors land in the same pool group and
pass GroupConsistency. The ONLY drive attributes that must stay uniform: MediaType
= SSD, BusType = NVMe, and Size = 512GB-class (>=500GB decimal). If a future drive
differs in SIZE or MEDIA it would split the group — so hold the line on
"512GB NVMe SSD," not on brand. (User confirmed 2026-07-13: can't guarantee all
KIOXIA, but all will be 512GB.)

## Act

- Nodes 03-06 taken down for the 3x-NVMe hardware change (in progress).
- Node 02 verified at 3 data disks, all `CanPool=True` after the clear procedure.
- Node 01 (currently 2 data disks) to be brought to 3 before multi-node deploy so
  the fleet is symmetric.
- Rollout per node (never touches the OS/boot disk):
  `Test-NoRaidConfig` -> clear data disks (attribute-based selection, diskpart
  `clean`) -> `Update-StorageProviderCache -DiscoveryLevel Full` -> confirm
  `CanPool` on all 3 data disks -> `Invoke-AzStackHciHardwareValidation`
  (expect storage SUCCESS). Tool: [scripts/Clear-DataDisks.ps1](../../scripts/Clear-DataDisks.ps1)
  (guardrails: non-boot, non-system, non-BootFromDisk, <=550GB, NVMe, Online).
- Updated `poc_risk_register.txt` scale-out section already notes the same-drive-
  count add-server gate; this ADR makes the count itself explicit.

