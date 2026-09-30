---
title: "Drive failure on Azure Local: how it is supposed to go, and how it went"
domain: [storage]
layer: [hardware, cluster]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [storage-spaces-direct, drive-failure, repair, resilience, guardrails, lessons, deadlock]
updated: 2026-08-28
---

# Drive failure on Azure Local: how it is supposed to go, and how it went

A single NVMe died in `AZL-NODE-01` in a lab roughly 200 miles from anyone who could touch it. The
cluster absorbed it without incident, which is the whole point of the design. Getting from there back
to a green health report took ten days and turned into a useful education.

This document records the difference between the documented model and what actually happens, because
the gap is where the operational lessons live. The specific incident is in
[node01-retired-nvme-recovery.md](node01-retired-nvme-recovery.md).

## How it is supposed to go

1. A drive fails.
2. Storage Spaces Direct retires it automatically. The pool stops writing to it.
3. Repair starts automatically and rebuilds the missing copy into reserve capacity.
4. The affected volume returns to `Healthy` on its own.
5. The dead drive is replaced whenever convenient. There is no rush, because protection is already
   restored.
6. The new drive is absorbed into the pool.

The design intent is that a drive failure is a maintenance ticket, not an incident. Reserve capacity
exists precisely so that repair does not wait on procurement. Microsoft's guidance is to leave the
equivalent of one capacity drive per server unallocated, up to four, so an in place repair can always
succeed. Source:
[Plan volumes on Azure Local](https://learn.microsoft.com/en-us/azure/azure-local/concepts/plan-volumes).

## How it actually went

Steps one and two worked exactly as advertised. Nothing after that did.

| Stage | Expected | Observed |
| --- | --- | --- |
| Failure noticed | promptly | not for some time, nothing paged anyone |
| Disk retired | automatic | automatic, correct |
| Repair starts | automatic | started, then `Suspended` at `0%` |
| Volume recovers | within minutes | `Warning` / `Incomplete` for ten days |
| Remediation | routine | every graceful action refused |
| Resolution | replace drive | reboot the node, drive still dead |

The repair had 8 GiB to move on a pool with 3,671 GB free, every node `Up`, no fault domain in
maintenance mode, and no Storage Spaces driver events for nearly two weeks. It simply sat there. The
reason it parked was never established.

## The deadlock

This is the part worth internalising, because each individual behaviour is correct and the
combination is a trap.

- The repair was suspended, so the volume stayed degraded.
- The degraded volume made the cluster refuse to pause the node.
- The node could not be paused, so it could not be gracefully restarted.
- Restarting it turned out to be the thing that cleared the repair.

Three separate refusals, each with a clear and accurate message:

| Action | Refusal |
| --- | --- |
| `Enable-StorageMaintenanceMode` | `Currently unsafe to perform the operation` |
| `Suspend-ClusterNode -Drain` | `A clustered space is in a degraded condition and the requested action cannot be completed at this time` |
| `Suspend-ClusterNode -ForceDrain` | refused |

None of these are bugs. The platform will not trade redundancy on an already degraded volume to make
an operator's evening easier, and it cannot distinguish a disposable lab from a hospital. There is no
override, which is a deliberate supportability stance rather than an oversight.

The way out was `Stop-ClusterNode`, run locally on the affected node, followed by a normal restart.
That is a supported cmdlet. It is the blunter sibling of pause and drain: roles fail over instead of
live migrating. On a four node cluster with capacity to spare, that cost nothing. CSV ownership moved
cleanly and every running VM stayed online.

## What the reboot did and did not do

It did **not** recover the drive. The NVMe controller was reporting `ConfigManagerErrorCode=10`, this
device cannot start, and a full power cycle is one of the few things that recovers a device in that
state. It came back identically broken, which converted the diagnosis from probably the drive to
definitely the drive.

It **did** clear the suspended repair. The rebuild completed at 100 percent on its own within minutes
of the node rejoining, and the volume returned to `Healthy`.

So the reboot fixed the software state and proved the hardware state. Both were worth knowing.

## Lessons

**A suspended repair is silent.** Nothing alerts on it. The volume shows `Warning`, the pool shows
`Healthy`, and if nobody runs `Get-StorageJob` nobody finds out. Check storage jobs on a schedule,
not on suspicion.

**Automatic does not mean guaranteed.** Repair is automatic in the sense that nobody has to start it.
It is not automatic in the sense that it always finishes.

**Guardrails compose into deadlocks.** Each refusal was individually correct. Together they removed
every graceful path. Know that `Stop-ClusterNode` exists before you need it.

**Cluster cmdlets do not delegate.** Running `Stop-ClusterNode` against a remote node from a third
machine fails with `Access is denied`, because the credential cannot make the second hop. Run it on
the target node.

**Never identify a disk by friendly name or physical location.** Four disks in this pool reported the
identical `PCI Slot 23 : Bus 180 : Device 0 : Function 0 : Adapter 5`, and three of them were
healthy. Anyone pulling hardware from that string had a three in four chance of removing a working
drive. Use the immutable `UniqueId` and serial. Conveniently, the failed disk was also the only one
whose `UniqueId` was a GUID rather than an `eui.` value, because Windows had lost the device and
Storage Spaces fell back to a synthetic identifier.

**Diagnose before dispatching hardware.** Node 03 has three drives installed and enumerates two, and
stayed that way after all three were replaced with new drives. Three new drives do not arrive dead,
so that is a path fault rather than media. A site visit with a box of drives would have fixed
nothing. Two remote read only probes established that for free.

**Read the refusal.** Every message named its cause precisely. The temptation is to reach for a force
flag. The information was in the text.

**Reserve capacity is not a spare drive.** Storage Spaces Direct does not use hot spares. It repairs
into unallocated pool capacity. The question to ask after a failure is not "do we have a spare disk"
but "do we still have a drive's worth of free space per server".

## Worth remembering about margin

The nodes were built with three data disks each rather than the platform minimum of two, deliberately,
because the POC was allocated used workstations that are not on the Azure Local catalog. That third
disk was never spare capacity. It was the buffer that would absorb a failure on ageing hardware.

It did exactly that. A drive died and the only consequence was a number in a health report. No
outage, no data loss, no interrupted workload.

The constraint produced the evidence. On new certified hardware nothing would have failed, and there
would have been nothing to learn.
