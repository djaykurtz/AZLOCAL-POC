---
title: "0003 - Storage spec lock: 1x ASUS Hyper M.2 X16 Gen 4 + 2x KIOXIA KXG80ZNV512G per node"
domain: [storage]
layer: [hardware]
type: decision
status: superseded
superseded_by: decisions/0008-asus-card-mechanical-incompatibility.md
proof: proven
audience: [engineer]
tags: [adr, storage, procurement, nvme, carrier-card]
updated: 2026-08-20
---

# 0003 - Storage spec lock: 1x ASUS Hyper M.2 X16 Gen 4 + 2x KIOXIA KXG80ZNV512G per node

- **Status**: Superseded by 0008 for the ASUS adapter-card model; still retained for drive-count and S2D symmetry rationale.
- **Date**: 2026-06-11
- **Owner**: labadmin
- **Revisit when**:
  - Procured parts fail to enumerate or pool after install (would force
    a card or drive swap and a new ADR), OR
  - Cluster is expanded beyond 4 nodes and the spec needs to apply to
    AZL-NODE-05/06, OR
  - We re-platform off the Dell Precision 7960 Rack chassis (the slot
    map and bifurcation path are chassis-specific).

## Observe

### O1. Validator evidence: every node fails the data-disk check
[scripts/Invoke-HardwareValidator.ps1](../../scripts/Invoke-HardwareValidator.ps1)
run on 2026-06-11 across all 4 active nodes
(per-node payloads `out/_hardware-azl-node-0{1..4}-20260611-102636.json`,
summary [out/_hardware-summary-20260611-102636.txt](../../out/_hardware-summary-20260611-102636.txt)):

```
Node           Tests Failed Critical
azl-node-01    23      2        1
azl-node-02    23      2        1
azl-node-03    23      2        1
azl-node-04    23      2        1
```

The CRITICAL failure on every node is the data-disk check (extracted
from the validator report):

```
Unsupported DataDisks:
HCISupported,HCISupportedData,UniqueId
False,@{CanPool=False; CannotPoolReason=Insufficient Capacity;
        BusTypeIsSupported=False; MediaTypeIsSupported=True;
        IsBootDevice=True},eui.00000000000000000000000000000001

Supported DataDisks:
(empty)
```

Read: each node has exactly one drive, it is the boot drive, it is on
VROC (BusType=RAID, which S2D rejects), and there is no second drive
that could become a pooled data drive. S2D's symmetric-per-node rule
requires the same set of `Bus + Media + count` on every node, with
the boot drive excluded.

### O2. Chassis constraints
The Dell Precision 7960 Rack is a workstation, not a server SKU. It
ships with 3.5" front bays (none populated on the POC units) and
onboard M.2 sockets that route through the platform VROC controller.
There is no SAS HBA in the chassis -- the original "HBA / passthrough"
guidance in the prereq checklist assumed a server-class controller
that does not exist here.

PCIe slot map confirmed from a BIOS screenshot taken at
AZL-NODE-01 on 2026-06-10:

| Slot | Width | Current use                                |
| ---- | ----- | ------------------------------------------ |
| 1    | x4    | open                                       |
| 2    | x4    | open                                       |
| 3    | x4    | open                                       |
| 4    | x8    | Mellanox ConnectX-5 100GbE (RDMA)          |
| 5    | x8    | Mellanox ConnectX-5 100GbE (RDMA)          |
| 6    | x16   | open - this is where the new card goes     |
| 7    | x4    | open                                       |

The BIOS Slot Bifurcation page exposes:
- `Auto Discovery Bifurcation Settings`: Enabled
- `Slot 6 Bifurcation Control`: x4/x4/x4/x4 selectable
- Slots 4/5 can do x4/x4 if ever needed as a fallback

### O3. Drive compatibility
The KIOXIA KXG80ZNV512G (Dell OEM 0WGWK4, 512 GB M.2 2280, PCIe Gen 4
x4 NVMe, MLC SSD) was vetted as S2D-compatible:
- BusType reports as `NVMe` (not `RAID`) when consumed direct, no VROC.
- MediaType reports as `SSD`.
- Capacity 512 GB clears Microsoft's recommended floor for an all-flash
  cache-less S2D layout in a 4-node POC.
- Dell ships this part inside HCI Catalog systems for the same role;
  the part itself is on the Windows Server HCL.

### O4. Adapter card vetting
The ASUS Hyper M.2 X16 Gen 4 (B084HMHGSP, ~$80 retail) was chosen over:
- Generic "Yosoo" no-name x16 cards (no provenance, no firmware
  support, intermittent in Dell-vendor reports).
- ASUS Hyper M.2 X16 V2 Gen 3 (B07NQBQB6Z) - works, but Gen 3 caps the
  KIOXIA drives at half their rated bandwidth.

The Gen 4 ASUS card is the reference design that BIOS vendors test
their bifurcation tables against; "works in a Dell workstation"
reports are plentiful in the wild; it ships with active fan + per-slot
heatsinks so we are not improvising thermals.

### O5. Procurement source / review evidence / access method

Procurement evidence captured as of 2026-06-18:

| Item | Source captured | Evidence retained |
| ---- | --------------- | ----------------- |
| ASUS Hyper M.2 X16 Gen 4 | Likely Amazon retail listing, part number B084HMHGSP, 6 units purchased | Model/SKU, approximate unit cost, and likely marketplace captured here; exact Amazon order URL/seller/review snapshot still needs to be pasted from the order source. |
| KIOXIA KXG80ZNV512G | Dell OEM part 0WGWK4, 512 GB M.2 NVMe | Model/part and compatibility rationale captured here; vendor URL/seller/review snapshot still needs to be pasted from the order source. |

Access / install method captured:

- Physical installation is by the datacenter technician at rack rack-01.
- Remote BIOS/console access is via Raritan Dominion KX3 KVM at
  `https://kvm-01.lab.example.com/` over CORP-VPN.
- iDRAC virtual console/media is not relied on because the POC iDRACs
  are unlicensed for that workflow.
- The platform team verification is via WinRM from the DevBox after smart-hands
  completes the physical install and BIOS pass.

Review/source gap:

- We have not yet pasted the exact purchase website URL, seller name,
  order page, rating/review count, or review quotes into the repo. Current
  best recollection is that the ASUS cards came from Amazon, based on the
  6-unit purchase pattern and retail SKU. If a procurement defense is needed,
  add the exact Amazon order/listing details here rather than relying on
  recollection.

## Orient

### Why M.2-on-a-card and not "just add drives to the bay"
The chassis has 3.5" bays. Procuring 8x enterprise 2.5"-or-3.5"
U.2 / SATA SSDs + the brackets + (if we had to) a real HBA blows past
the POC budget and timeline. Buying 6x $80 PCIe adapters and 8x
~$60 M.2 NVMe drives lands the same outcome (8 data drives across
4 nodes, 2 per node, all on NVMe) for an order of magnitude less.

### Why 6 cards but only 4 will be installed
4 active POC nodes + 2 spares. The spares are cheap insurance against
a bent connector, a DOA card, or a future expansion to AZL-NODE-05
/ 06 once those are racked.

### Why 2 drives per node (not 4)
S2D minimum is 2 data drives per node. The ASUS card supports 4, so
we are leaving headroom - but doubling drive count doubles the SSD
spend with no functional gain for the POC's "does S2D come up?"
acceptance criterion. If the POC extends into a perf-validation run,
we add 2 more drives per node into the existing card.

### Why not put the card in Slot 4 or Slot 5
Those are x8 with x4/x4 bifurcation - usable for 2 drives at full
speed, on paper. Two reasons not to:
1. The Mellanox 100GbE NICs are already in Slots 4 and 5 and are
   doing their job. Moving them just to make room is risk for no
   reward.
2. Slot 6 is x16 and supports x4/x4/x4/x4. Using it future-proofs
   the layout for the eventual move to 4 drives per node.

### Why leave the boot drive on VROC for now
Flipping NVMe Mode to Non-RAID on the boot path would orphan the
existing Azure Stack HCI OS install. The boot drive is excluded
from the S2D pool by `IsBootDevice=True`, not by `BusType`, so the
VROC artifact on the boot drive is documented-and-benign rather than
a real blocker. See [bios-ideal-state.md](../storage-imaging/bios-ideal-state.md)
"Boot drive caveat" for the full Path A vs Path B writeup.

### Why a separate ADR (and not a comment in the checklist)
This is exactly the failure mode the documentation retrospective
called out: the original S2D drive symmetry requirement was buried as
a sub-comment on a line in [poc_prereq_checklist.notes.txt](../../archive/docs/poc_prereq_checklist.notes.txt)
("Drive types, counts, and sizes. Must be symmetric across all nodes.")
and the HBA / passthrough requirement was assumed-server-class without
ever validating against the actual chassis. Both got missed; both ate
weeks of elapsed time. Promoting the storage spec to a named ADR plus
a top-level reference doc (bios-ideal-state.md) makes it so the next
person on this project - or future-us - has a single artifact to read.

## Decide

Procure and install:
- **6x ASUS Hyper M.2 X16 Gen 4** (B084HMHGSP, ~$80 ea) - 1 per active
  node + 2 spares.
- **8x KIOXIA KXG80ZNV512G** (Dell OEM 0WGWK4, 512 GB M.2 2280 NVMe
  Gen 4) - 2 per active node.

Install in **Slot 6** of each of AZL-NODE-01..04, with **Slot 6
Bifurcation = x4/x4/x4/x4**. Leave VROC enabled on the boot drive
(Path B in [bios-ideal-state.md](../storage-imaging/bios-ideal-state.md)) unless a
reinstall is happening for another reason.

AZL-NODE-05 and AZL-NODE-06 are deferred from the storage build
out - keep the 2 spare adapter cards in inventory against the day
they come online.

RAM is tracked separately. All active nodes report 31.5 GB visible
against the 32 GB Microsoft floor. As of 2026-06-18, assume no
additional RAM is available; proceed with storage install and escalate
only if the Azure Local validator explicitly blocks on memory.

## Act

What was done:
- Procurement order placed for the 6 cards + 8 drives (2026-06-11).
- Procurement source details still need the exact website/seller/review
  snapshot pasted into O5 if we need a fully auditable purchase trail.
- BIOS target state documented in
  [bios-ideal-state.md](../storage-imaging/bios-ideal-state.md).
- [poc_prereq_checklist.txt](../../archive/docs/planning/poc_prereq_checklist.txt) Phase 0
  rewritten to (a) call out the storage adapter + drive procurement
  as explicit checkbox items, (b) flag the RAM-under-floor validation risk,
  (c) cross-reference this ADR and `bios-ideal-state.md` instead of
  re-stating the spec inline.
- [poc_prereq_checklist.notes.txt](../../archive/docs/poc_prereq_checklist.notes.txt)
  Phase 0 updated to keep the master notes file in sync.
- [poc_runbook.txt](../../archive/docs/runbooks/poc_runbook.txt) Phase 6 (smart-hands) BIOS spec
  line updated to point at `bios-ideal-state.md` rather than
  re-listing settings inline.

Validation plan:
- Smart hands installs cards + drives, applies the BIOS table.
- The platform team re-runs
  `.\scripts\Invoke-HardwareValidator.ps1 -NodeNumbers @(1,2,3,4)`.
- Acceptance: zero CRITICAL failures on the data-disk check; each
  node reports 2 drives with `BusType=NVMe`, `MediaType=SSD`,
  `CanPool=True`.

Follow-ups still open:
- RAM validation result after storage install (see Phase 0a of the prereq
  checklist).
- Decision on whether to extend to AZL-NODE-05/06 mid-POC (out of
  scope of this ADR; revisit after the 4-node cluster stabilizes).
