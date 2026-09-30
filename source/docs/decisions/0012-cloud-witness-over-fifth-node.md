---
title: "0012 - Buy two-failure tolerance with a cloud witness, not with node 03"
domain: [platform]
layer: [cluster]
type: decision
status: current
proof: documented
audience: [leadership, engineer]
tags: [adr, quorum, witness, node-03, spare, resiliency]
updated: 2026-09-11
---

# 0012 - Buy two-failure tolerance with a cloud witness, not with node 03

- **Status**: Active
- **Date**: 2026-09-11
- **Owner**: labadmin
- **Relates to**: [0004](0004-four-node-functional-poc-scope.md) (four-node scope),
  [0011](0011-three-data-disks-per-node.md) (drive-count symmetry as an add-server gate),
  [0007](0007-reimage-after-ahci-storage-mode.md) (the VMD/RAID condition and its cure)
- **Revisit when**:
  - Node 03 is confirmed to enumerate a third data disk, which would give it the same margin
    every other candidate was meant to carry, OR
  - Add-server is actually tested against this cluster and its behaviour on a mixed drive count
    is known rather than assumed, OR
  - The cluster is asked to outlive the POC and carry real workloads, OR
  - A Mellanox card or other donor part is consumed out of node 03, which ends the
    sealed-spare argument on its own, OR
  - The subscription stops allowing a storage account for the witness.

## Observe

- The resiliency gap is already recorded as an unmet prerequisite.
  [node-failure-recovery.md](../../working/sprints/node-failure-recovery.md)
  lists "A cluster witness configured, so quorum survives the loss." The cluster has no witness.
  Quorum is Majority across four nodes, verified live on 2026-09-04.
- Microsoft Learn,
  [Understand cluster and pool quorum](https://learn.microsoft.com/en-us/azure/azure-local/concepts/quorum):
  > If you have three or four nodes, witness is **strongly recommended**.
  > If you have five nodes or more, a witness isn't needed and doesn't provide additional resiliency.
  > If you have internet access, use a **cloud witness**.
- Same page, pool quorum outcomes. Pool quorum is harsher than cluster quorum and is the
  binding constraint here:

  | Server nodes | Survive one | Then another | Two at once |
  | --- | --- | --- | --- |
  | 4 | Yes | No | No |
  | 4 + Witness | Yes | Yes | Yes |
  | 5 and above | Yes | Yes | Yes |

- Same page, on cluster quorum at four nodes without a witness: "Can survive two server
  failures at once: **Fifty percent chance**." So the hard stop at a second loss comes from
  the pool, not from the cluster.
- Same page: "Ensure that each node in your cluster is symmetrical (each node has the same
  number of drives)."
- [ADR 0011](0011-three-data-disks-per-node.md) states the harder version of that as a gate:
  > Azure Local add-server enforces a HARD gate: a node being added must have the same number
  > of data drives as the cluster, or the add is BLOCKED.
- That gate has never been exercised on this cluster, and the cluster is no longer uniform.
  Node 01 retired a failed NVMe and runs as a member on two data disks today:

  | Node | Data disks | In cluster |
  | --- | --- | --- |
  | 01 | 2 | yes |
  | 02, 04, 06 | 3 each | yes |
  | 03 | 2 | no |

- Three disks was never a floor. From
  [node01-retired-nvme-recovery.md](../runbooks/node01-retired-nvme-recovery.md):
  > Three data disks per node (ADR 0011) was chosen deliberately as margin, because this POC
  > was allocated used workstations that are not on the Azure Local catalog. The third disk was
  > never spare capacity. It was the buffer that would absorb a failure on ageing hardware.

  The same runbook records the floor and the proof of it: two data disks is "the platform
  minimum", and node 01 running healthy on two makes it "a demonstrated working configuration
  rather than a theoretical minimum".
- Node 03 "has three installed and has never enumerated more than two, including after all
  three were replaced with new drives." So it sits exactly where node 01 sits, and unlike node
  01 it cannot be brought back to three by fitting a drive.
- The same runbook calls node 03 "usable as a spare cluster machine without any hardware
  work". [capstone/prototype/v2/explain.js](../../capstone/prototype/v2/explain.js) still says
  its drives "enumerated behind Intel VMD as BusType RAID, which Storage Spaces Direct will
  not pool". Both cannot be current. ADR 0007 cures that condition with a Non-RAID BIOS state
  plus a reimage, and node 03 is workgroup joined, so settling it needs a local credential on
  the box rather than anything in Azure.
- Node 05 has already been stripped. Its Mellanox card went into node 02. Node 03 is the only
  remaining machine with two Mellanox cards at the correct subsystem ID, never opened.
- [security-posture-and-boundaries.md](../access/security-posture-and-boundaries.md): node 03
  "sits outside the cluster, the domain, and the managed credential lifecycle."
- Azure Local bills per physical core. Node 03 is 24 cores. The subscription showed
  `billingModel Trial` with 17 days remaining on 2026-09-09.

## Orient

- The question was posed as a binary: node 03 as a fifth cluster member, or node 03 parked
  beside the cluster as a spare. Both options were being judged on resiliency, and both are
  the expensive way to buy it.
- A fifth node and a witness purchase the same thing. The doc is explicit that past five nodes
  a witness "isn't needed and doesn't provide additional resiliency", which is another way of
  saying four-plus-witness and five-without already sit on the same row of the table. There is
  no resiliency argument for preferring the node.
- Their costs are not the same. A cloud witness is a storage account. A fifth node is an
  add-server validation pass, a storage rebalance, a domain join, Arc rework, a security
  boundary change, 24 more billed cores, and the loss of the last sealed donor.
- The spare argument is the strongest reason to leave node 03 alone, and it is a hardware
  logistics argument rather than a platform one. Once node 03 is a cluster member, a NIC
  failure means taking a cluster member down to repair a cluster member.
- The drive count is an unknown rather than a blocker, and it is worth being careful about
  which. Add-server gates on matching the cluster, and this cluster no longer has one answer to
  match: node 01 is a member at two disks and the other three are at three. Nothing in the repo
  says what the gate compares against in that state, and it has never been run here. Treating
  it as a hard block would be asserting something untested.
- The stronger drive argument is not about whether node 03 can be added. It is about what gets
  added. Three disks was margin on used workstations that are not on the Azure Local catalog,
  and the third disk existed to absorb one failure. Node 01 has already spent its buffer. Node
  03 has never had one and cannot be given one, because fitting three new drives changed
  nothing. So a fifth node would arrive with zero margin and would take the cluster from one
  bufferless member to two, on hardware whose failures have so far clustered on the same PCI
  bus. It adds a vote and it adds a failure surface, and the vote is available elsewhere for
  the price of a storage account.
- The deck's claim that four nodes survive one loss and not two is correct, but the reasoning
  recorded in [acceptance-criteria-verification.md](../planning/acceptance-criteria-verification.md)
  runs through cluster quorum. Cluster quorum at four nodes without a witness survives one
  loss then another, and is a coin flip on two at once. Pool quorum is what makes it a flat No.
  The conclusion is unchanged and the deck line stands.

## Decide

If two-failure tolerance is wanted, **configure a cloud witness** against the existing four
nodes. **Do not add node 03 to the cluster** to get it.

Keep node 03 sealed as the donor of record. It is the only remaining source of a
correct-subsystem-ID Mellanox card, and that is worth more to this cluster than a fifth vote
it can already buy for the price of a storage account.

Adding node 03 becomes worth reopening only if the cluster outlives the POC, and even then not
before its third data disk enumerates. Two disks is a proven working configuration, so the
reason to wait is margin rather than capability.

## Act

- Treat the sprint S3 witness prerequisite as open, with a cloud witness as the named
  remedy rather than a fifth node. Note that this is a resiliency improvement and not
  something the POC set out to prove, so ADR 0004's instruction not to claim production HA
  still holds either way.
- Resolve the node 03 contradiction before it is repeated anywhere else. Probe the box with a
  local credential and record whether its drives still present as `BusType=RAID`, or whether
  the reimage under ADR 0007 already cured it. Whichever way it lands, correct the loser:
  either the `h03` text in [capstone/prototype/v2/explain.js](../../capstone/prototype/v2/explain.js)
  or the spare claim in [node01-retired-nvme-recovery.md](../runbooks/node01-retired-nvme-recovery.md).
- While probing, capture whether the missing third disk sits on PCI bus 180, which the runbook
  flags as the position that failed on node 01 and that trains below full link width on nodes
  01 and 02. A third hit on the same bus makes it a platform fault rather than three unlucky
  drives.
- Leave node 03 out of the domain and out of the managed credential lifecycle. Nothing here
  changes the boundary described in
  [security-posture-and-boundaries.md](../access/security-posture-and-boundaries.md).
- Do not restate the four-node resiliency limit as a cluster quorum result. It is a pool
  quorum result.
