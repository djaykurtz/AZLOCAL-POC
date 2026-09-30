---
title: "Sprint S2 - Test live migration between nodes"
domain: [compute]
layer: [cluster]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [sprint, live-migration, sprint-s2]
updated: 2026-07-27
---

# Sprint S2 - Test live migration between nodes

Sprint S2 (PoC Validation Part 1). Status: planned. Depends on S1.
Cluster: AZL-CLUSTER-01 (4 nodes: 01, 02, 04, 06).

## Objective

Move a running VM from one node to another with little or no interruption, and prove the workload
keeps running across the move. This exercises Storage Spaces Direct shared storage plus the RDMA
storage fabric we fought to get working.

## Prerequisites

- A running VM from sprint S1, with its current owner node recorded.
- Cluster healthy. All four nodes up and joined.
- Storage Spaces Direct healthy, with the VM on a Cluster Shared Volume so both nodes can reach it.
- The storage network is the path live migration uses, so this also validates that fabric under load.

## Procedure

1. Baseline health.
   Run Get-ClusterNode and Get-ClusterGroup on a node to confirm all nodes Up and note the VM's owner.
   Run Get-VirtualDisk and Get-StoragePool to confirm storage HealthStatus Healthy.
   Result: a clean starting picture and the source node identified.

2. Start a continuity probe.
   From the DevBox or another VM, start a continuous ping and an SSH or HTTP session to the guest.
   Result: a live signal that will show any interruption during the move.

3. Trigger live migration.
   Move the VM's clustered role to a target node. Use Move-ClusterVirtualMachineRole with
   -MigrationType Live on a cluster node, or the Arc VM move path if exposed through the control plane.
   Result: the VM begins migrating over the storage or migration network.

4. Watch the move.
   Track the ping and session during the transition. Live migration should show zero or a single
   dropped packet, not a reboot.
   Result: measured interruption, expected near zero.

5. Confirm the new owner.
   Run Get-ClusterGroup again and confirm the owner node changed and state is Online.
   From inside the guest, confirm uptime did not reset.
   Result: ownership moved, guest never rebooted.

6. Migrate back.
   Move the VM to its original node and confirm the same clean behavior.
   Result: bidirectional live migration proven.

## Success criteria

- VM owner node changes across the move.
- Guest uptime does not reset, so it was a live move, not a restart.
- Continuity probe shows zero or minimal loss.
- Storage HealthStatus stays Healthy throughout.

## Evidence to capture (out/)

- Get-ClusterGroup owner before and after.
- Ping and session log across the migration window with timestamps.
- Guest uptime before and after.
- Any migration events from Get-WinEvent on the FailoverClustering log.

## Risks and notes

- Live migration rides the storage or migration network. If it is slow or drops, that points back at
  the RDMA or SMB path, so capture the network counters if it misbehaves.
- All four nodes are identical hardware, so processor-compatibility blocks are not expected.
- Quick migration or a move that reboots the guest is a failure for this test. The goal is a live move.

## Rollback

- No rollback needed. The VM ends on a valid node either way. Return it to its original node for the
  next sprint.

