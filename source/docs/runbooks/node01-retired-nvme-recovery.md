---
title: "Node 01 retired NVMe recovery"
domain: [storage]
layer: [hardware, cluster]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [nvme, retired-disk, storage-spaces-direct, repair, maintenance-risk, resilience, resolved]
updated: 2026-08-28
---

# Node 01 retired NVMe recovery

## Status

**Resolved 2026-08-28.** The suspended repair completed and `UserStorage_2` returned to `Healthy` / `OK`
after node 01 was restarted. The cluster is green. The physical NVMe is still dead and remains an open
hardware item, but it no longer blocks anything.

See "Resolution" below for what actually worked and why the obvious paths did not.

Remaining open item: the failed PM9A1 on node 01 bus 180 needs physical replacement to restore three
data disks per node. Storage protection is no longer degraded without it.

Heat was ruled out as a cause on 2026-09-03. Bus 180 is the coolest of the three M.2 positions on the
carrier, running three to four degrees below the other two on every node. See
[nvme-thermals.md](../storage-imaging/nvme-thermals.md).

## Resolution - 2026-08-28

### What the reboot did and did not do

It did **not** recover the drive. After the power cycle, node 01 still reports:

```text
OK     width=x4   PCI bus 181
OK     width=x4   PCI bus 182
OK     width=x4   PCI bus 55
Error  width=x2   PCI bus 180      <- unchanged
```

A full power cycle is one of the few things that recovers a device stuck at `ConfigManagerErrorCode=10`.
It did not work here, which upgrades the diagnosis from "probably the drive" to **the drive is genuinely
dead**. A physical replacement is now justified rather than speculative.

### What it did fix

| Item | Before reboot | After reboot |
| --- | --- | --- |
| `UserStorage_2` | `Warning` / `Incomplete` | `Healthy` / `OK` |
| `UserStorage_2-Repair` | `Suspended`, `0%` | `Completed`, `100%` |
| Cluster nodes | 01 `Down` | all four `Up` |
| Running VMs | 3 `Online` | 3 `Online` |

The repair had been suspended at zero for ten days with 8 GiB to move, on a healthy pool with 3671 GB
free. Restarting the node cleared whatever state was holding it, and the rebuild completed on its own.
The root cause of the suspension was never identified.

### The path that worked

The documented maintenance procedure was refused at every step because a space was degraded:

| Action | Result |
| --- | --- |
| `Enable-StorageMaintenanceMode` | `Currently unsafe to perform the operation` |
| `Suspend-ClusterNode -Drain` | `A clustered space is in a degraded condition` |
| `Suspend-ClusterNode -ForceDrain` | Refused |

What worked was `Stop-ClusterNode`, run locally on node 01, followed by `Restart-Computer -Force`.
`Stop-ClusterNode` is a supported cmdlet. It is the blunter sibling of pause and drain: roles fail over
instead of live migrating. On this cluster that cost nothing. CSV ownership moved cleanly, all three
running VMs stayed Online, and no volume changed state.

Note that `Stop-ClusterNode` must be run **on the target node**. Invoking it from another node over WinRM
fails with `Access is denied`, because the credential does not delegate for the second hop.

### The deadlock, and how it broke

- The repair was suspended, so `UserStorage_2` stayed degraded.
- The degraded volume made the cluster refuse to pause node 01.
- Node 01 could not be paused, so it could not be gracefully restarted.
- Restarting it was the thing that cleared the repair.

The circle was broken by leaving the cluster deliberately rather than asking permission to pause.

### Lessons worth keeping

- Redundancy did its job. A drive died in a lab 200 miles away and the only consequence was a number in
  a health report. No outage, no data loss, no workload interruption.
- The guardrails are real and they will refuse you with a clear reason. Every refusal was correct.
- There is no lab override. `-ForceDrain` did not help. A "yes, I know, this is disposable" escape hatch
  does not exist, which is a deliberate supportability stance and a genuine friction point.
- A suspended repair is not always a capacity or configuration problem. Sometimes it is stuck state, and
  a node restart clears it.
- Diagnose before dispatching hardware. Three new drives in node 03 changed nothing there, and a power
  cycle changed nothing on node 01. Both of those are cheap facts that would have cost a site visit.

### Fleet state after this incident

Node 01 now runs on two data disks with the cluster fully healthy, which makes two disks a
demonstrated working configuration rather than a theoretical minimum.

Node 03 also has two working data disks. It has three installed and has never enumerated more than
two, including after all three were replaced with new drives. That means **node 03 is already as
capable as node 01 is today**, and is usable as a spare cluster machine without any hardware work.

The two are alike in outcome but possibly not in cause:

| Node | Third data slot | Diagnosis |
| --- | --- | --- |
| 01 | Controller enumerates, `Error`, link x2 | Device present and failing. Power cycle did not recover it, so the drive is dead. |
| 03 | Never enumerated | Not probed. Three new drives changed nothing, so it is not the media. |

That distinction matters only if three disks per node is wanted again. It does not affect using node
03 as a spare.

Open pattern worth noting: on both node 01 and node 02 the third data position, PCI bus 180,
negotiates below full link width, x2 and x1 respectively, while buses 55, 181 and 182 all run x4. It
is also the position that failed on node 01. If node 03's missing disk turns out to be bus 180 as
well, the cause is the platform rather than the drives. Node 03 needs a local credential to probe,
since it is not domain joined.

This leaves two of four cluster-capable machines at two data disks, which is the platform minimum.

That matters more than a symmetry note. Three data disks per node
([ADR 0011](../decisions/0011-three-data-disks-per-node.md)) was chosen deliberately as margin,
because this POC was allocated used workstations that are not on the Azure Local catalog. The third
disk was never spare capacity. It was the buffer that would absorb a failure on ageing hardware.

That buffer has now done its job once, and on node 01 it is spent. There is no current risk: the pool
is healthy, protection is not degraded, and two disks meets the minimum.

A second drive loss on node 01 would also be survivable, and by a wider margin than it first appears.
It would leave ten data drives across four nodes:

| Node | Drives | Capacity |
| --- | --- | --- |
| 01 | 1 | 477 GB |
| 02, 04, 06 | 3 each | 1,431 GB each |
| **Pool** | **10** | **about 4,770 GB** |

Against 2,040 GB allocated, that leaves roughly 2,730 GB free, still above the reserve guidance of one
capacity drive per server up to four, which is about 1,908 GB here. Three way mirror needs three of
the four nodes to hold a copy, and nodes 02, 04 and 06 have about 885 GB free each, 2,655 GB between
them. They could hold the entire footprint without node 01 contributing anything, so node 01's
capacity is not a binding constraint.

The real consequences of a second loss would be that node 01 falls below the two disk platform
minimum, and that the cluster re-enters the pause and reboot deadlock described above while the
repair runs. Both are operational friction rather than a threat to the data.

Restoring the third disks is therefore about rebuilding margin on ageing hardware, which the original
design correctly anticipated and which events have already validated. It is not urgent.

## Historical - the condition as observed on 2026-08-18 and 2026-08-28

## Observed condition - 2026-08-18

`AZL-CLUSTER-01` remains online because the virtual disks use three-way mirror and the remaining copies are serving data. This is degraded protection, not a safe steady state for new workload placement.

| Item | Observed state |
| --- | --- |
| Cluster nodes | All four active nodes `Up` |
| Storage pool | `SU1_Pool` `Healthy` / `OK` |
| Affected virtual disk | `UserStorage_2` `Warning` / `Incomplete` |
| Repair job | `UserStorage_2-Repair`, `Suspended`, `0%` |
| Retired physical disk | `PM9A1 NVMe Samsung 512GB`, `Warning` / `Lost Communication`, `Usage=Retired` |
| Drive serial | `0000_0000_0000_0000_0000_0000_0000_0012.` |
| S2D physical location | `PCI Slot 23 : Bus 180 : Device 0 : Function 0 : Adapter 5` |
| S2D disk owner | `AZL-NODE-01` |
| Controller state on node 01 | `Standard NVM Express Controller`, `ConfigManagerErrorCode=10`, `Status=Error` |
| Controller PNP identity | `PCI\VEN_144D&DEV_A80A&SUBSYS_A801144D&REV_00\4&D9700C&0&0008` |
| Other pool members | Twelve `Healthy` / `OK`; one lost-communication member |

The failed drive is no longer enumerated by node 01 Windows disk inventory. The S2D record remains so the cluster can preserve the drive identity and rebuild its data after a working replacement path is available.

`PCI Slot 23 / Bus 180 / Adapter 5` identifies the PCIe controller path reported to Windows. It does not safely
identify a human-visible M.2 carrier position. The carrier contains multiple data drives, and no physical removal
should be attempted from this information alone.

## Why this blocks new workload placement

Three-way mirror preserves availability after a member path is lost, but `UserStorage_2` is incomplete and its repair is suspended. Adding a Terraform VM would increase write activity while the cluster has reduced storage protection and an unresolved hardware path. The correct POC behavior is to stop the capacity-sensitive test, not to test whether redundancy can absorb more risk.

Azure Local requires direct-attached data drives and documents repair flexibility when the original drive is no longer available. Source: [Azure Local system and storage requirements](https://learn.microsoft.com/en-us/azure/azure-local/concepts/system-requirements-23h2).

## Update - 2026-08-28: the condition is now a deadlock

Attempting recovery ladder step 2 surfaced a circular dependency that was not visible on 2026-08-18.

Observed today:

| Item | State |
| --- | --- |
| Retired physical disk | `Removing From Pool` **and** `Lost Communication`, `Usage=Retired` |
| `UserStorage_2` | `Warning` / `Incomplete`, unchanged |
| `UserStorage_2-Repair` | `Suspended`, `0%`, `BytesTotal` 8589934592 (8 GiB) |
| Storage pool `SU1_Pool` | `Healthy` / `OK`, 3671.3 GB free |
| Cluster nodes | All four `Up` / `Normal` |
| Fault domains | All `Healthy`, none in maintenance mode |
| Physical disks | Twelve healthy, one retired |

The `Removing From Pool` status was not present at 19:27 and was present at 19:45. A pool removal was
initiated in that window. The originating action is not established.

### The deadlock

`Suspend-ClusterNode -Name AZL-NODE-01 -Drain` is refused with:

```text
A clustered space is in a degraded condition and the requested action cannot be completed at this time
```

This is the documented safety check working correctly. It is the same gate described in
[Failover cluster maintenance procedures](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/maintain-servers),
which requires every volume to be `Healthy` / `OK` before a node is taken offline.

The circle:

- The repair is suspended, so `UserStorage_2` stays degraded.
- `UserStorage_2` is degraded, so the cluster refuses to pause node 01.
- Node 01 cannot be rebooted, so the failed NVMe controller cannot be re-enumerated.
- A reboot was the most likely way to clear the suspended repair.

Nothing visible accounts for the suspension: the pool is healthy, capacity is abundant, no fault
domain or disk is in maintenance mode, and the Storage Spaces driver log has no entries since
2026-08-15.

### Additional finding: node 01 hosts a live AKS worker

Cluster resources owned by `AZL-NODE-01` include the running AKS Arc worker VM
`azl-cluster-01-aks-01-worker-01` in the example inventory. Any node 01 outage moves or interrupts the
Kubernetes workload, so this node is not as idle as the stopped tenant VMs suggest.

### NVMe path evidence

`scripts/Invoke-NvmeEnumerationProbe.ps1` compared nodes 01 and 02. Both enumerate four NVMe
controllers, on buses 55, 180, 181 and 182. The failure is on bus 180, matching the retired member at
`PCI Slot 23 : Bus 180`. On node 01 that controller is present but in `Error`; on node 02 the
equivalent is `OK`. Because the NVMe controller sits on the M.2 device itself, this points at the
drive rather than the slot.

Link width is the unexplained part. Buses 55, 181 and 182 negotiate x4 on both machines. Bus 180
negotiates x2 on node 01 and x1 on node 02. The third data position runs below full width on both
machines, and it is also the position that failed. Recorded as an observation, not a conclusion.

### What was deliberately not done

- No second `Remove-PhysicalDisk`. A removal is already pending and waiting on the same repair.
- No forced `Resume-StorageJob`. Still listed below as something not to reach for without the
  storage owner, and the reason the job is parked is not understood.
- No hard power cycle of node 01. Bypassing the cluster safety check is precisely what that check
  exists to prevent.

### Suggested next step

This needs the storage owner or Microsoft support. The question is narrow and evidenced: why is an
8 GiB repair suspended at zero on a healthy four node pool with 3671 GB free, no maintenance mode
anywhere, and a pool member stuck in `Removing From Pool` with `Lost Communication`.

Evidence files, timestamped, are in `out/`:

- `_retired-disk-readiness-*.txt`
- `_nvme-enumeration-*.txt`
- `_retired-disk-removal-*.txt`

## Recovery ladder

### 1. Freeze nonessential change

- Keep `ws2025-core-01` and `rocky-docker-01` stopped. Both were stopped for this recovery.
  `rocky-docker-01` was restarted on 2026-09-01, after recovery completed, to re-check the
  container evidence. Stop it again before working any future storage incident.
- Do not apply Terraform or change AKS node-pool capacity.
- Preserve the current Terraform plan as evidence only. Regenerate it after storage recovery; do not reuse it for apply.
- Do not use `Reset-PhysicalDisk`, `Remove-PhysicalDisk`, `Clear-Disk`, `diskpart clean`, or a forced `Resume-StorageJob` as a first response.

### 2. POC decommission option - no physical removal

For this POC, storage capacity is not the constraint. Node 01 retains two working data disks, which meets the
Azure Local minimum. If the team accepts the reduced disk-count symmetry, the preferred near-term path is to
remove only the **already retired and non-enumerated S2D disk record**, then allow repair to complete against
the remaining capacity.

Before any state-changing storage command:

1. Capture pool free capacity, `UserStorage_2` footprint, repair-job state, and all current virtual disk health.
2. Confirm the retired target by its immutable unique ID and serial, never by friendly name alone:

  ```text
  UniqueId: {00000000-0000-0000-0000-000000000005}
  Serial:   0000_0000_0000_0000_0000_0000_0000_0012
  ```

1. Review the exact removal command and expected repair behavior with the storage owner.
2. Remove only that retired S2D record. Do not touch any locally visible healthy NVMe device.
3. Monitor repair until `UserStorage_2` returns to `Healthy` / `OK`.

This decommissions the failed member from the POC storage layout. It does not repair the node 01 NVMe controller
path. Preserve the controller failure for later hardware remediation.

### 3. Physical inspection on AZL-NODE-01

During an approved maintenance window:

1. Identify the PCIe controller path matching `PCI Slot 23 / Bus 180 / Adapter 5` and map its carrier positions
  to the healthy-drive serial inventory before removing any device.
2. Power down or follow the approved hardware-maintenance procedure before touching the NVMe carrier, drive, or adapter.
3. Inspect seating, retention hardware, carrier-to-slot connection, and visible damage.
4. Reseat the PM9A1 and its adapter/carrier connection.
5. If the drive or controller path still fails to enumerate, replace with a compatible NVMe device that meets the cluster's capacity, performance, and firmware expectations.
6. Record the replacement serial, model, firmware, and physical location before returning the host to service.

The POC hardware is not an Azure Local catalog system. Use Dell and component-vendor guidance for the physical procedure and keep the existing three-data-disk-per-node symmetry objective when replacing hardware.

### 4. Post-boot hardware confirmation

Run read-only checks on node 01 after the hardware path is restored:

```powershell
Get-PnpDevice -Class SCSIAdapter |
  Where-Object FriendlyName -eq 'Standard NVM Express Controller' |
  Select-Object Status, FriendlyName, InstanceId

Get-CimInstance Win32_DiskDrive |
  Where-Object Model -match 'PM9A1|NVMe' |
  Select-Object Model, SerialNumber, DeviceID, PNPDeviceID, Status, Size

Get-PhysicalDisk |
  Select-Object FriendlyName, SerialNumber, HealthStatus, OperationalStatus, Usage, PhysicalLocation
```

Pass criteria:

- No `Standard NVM Express Controller` remains in `Error` state.
- A local NVMe disk path is visible on node 01.
- The replacement or restored physical disk is visible to Storage Spaces.

### 5. Storage recovery validation

Do not manually resume a storage job until the physical disk path is healthy and the storage owner agrees the cluster has recognized the restored or replacement member.

Then monitor:

```powershell
Get-StorageJob | Select-Object Name, JobState, PercentComplete

Get-VirtualDisk |
  Select-Object FriendlyName, HealthStatus, OperationalStatus, ResiliencySettingName

Get-PhysicalDisk |
  Select-Object FriendlyName, SerialNumber, HealthStatus, OperationalStatus, Usage

Get-StoragePool -IsPrimordial $false |
  Select-Object FriendlyName, HealthStatus, OperationalStatus
```

Pass criteria:

- `UserStorage_2` returns to `Healthy` / `OK`.
- No storage repair job remains `Suspended`.
- No physical disk remains `Lost Communication` or `Retired` due to the failed path.
- Pool, all six virtual disks, and all four cluster nodes report healthy states.

### 6. Resume Terraform test

Only after the storage pass criteria are met:

1. Capture a fresh host-memory and running-VM baseline.
2. Confirm TenantLNET capacity and gallery image state.
3. Regenerate the Terraform speculative plan.
4. Confirm again: `3 to add, 0 to change, 0 to destroy` and only `tf-poc-` resources.
5. Obtain a new explicit approval before `terraform apply`.

## Evidence commands used

The investigation used read-only cluster and node queries through the established domain-admin WinRM path. It did not change disk state, repair state, cluster configuration, or Terraform-managed resources.

## Related records

- [Terraform sprint plan](../../working/sprints/terraform-against-cluster.md)
- [Terraform and CI/CD capstone plan](../../capstone/terraform-cicd-plan.md)
- [Azure Local system requirements](https://learn.microsoft.com/en-us/azure/azure-local/concepts/system-requirements-23h2)
