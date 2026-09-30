---
title: "Sprint S3 - Test cluster node failure and recovery"
domain: [platform]
layer: [cluster]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [sprint, node-failure, recovery, resync, sprint-s3]
updated: 2026-08-13
---

# Sprint S3 - Test cluster node failure and recovery

Sprint S3 (PoC Validation Part 1). Status: planned. Do this last. Depends on S1 and S2.
Cluster: AZL-CLUSTER-01 (4 nodes: 01, 02, 04, 06).

Detailed recovery boundaries, hardware limits, preflight gates, and the hard-power test procedure:
- docs/planning/unplanned-node-recovery-boundary-plan.md

## Objective

Prove the cluster tolerates losing a node and recovers when the node returns. Show that a running VM
survives on a surviving node and that Storage Spaces Direct stays online through the failure and
resyncs on repair. This is a POC-level resiliency check, not a production HA certification.

Status update, 2026-08-13: the controlled current-host reboot scenario passed with `ws2025-core-01`.
The node rejoined after about 26 minutes, the VM recovered on a survivor, and all six virtual disks
returned Healthy. A manual hard power-loss test remains unexecuted and must follow the recovery-boundary
plan's no-go gates.

## Safety first

This is the most disruptive sprint. Do the graceful drain before any hard power-off. On marginal
workstation-class hardware, treat a hard failure with care and be ready to bring the node back.
Coordinate physical or iDRAC power access before starting so recovery is not blocked.

## Prerequisites

- A running VM from S1, and live migration proven in S2.
- Cluster healthy, all four nodes Up.
- Storage resiliency confirmed. On a 4-node cluster this is usually three-way mirror, which tolerates
  losing a node. Confirm with Get-VirtualDisk and Get-StorageTier before starting.
- A cluster witness configured, so quorum survives the loss.
- A continuity probe ready against the VM.

## Procedure

Stage 1 - Graceful drain and restore (low risk, do this first).
1. Baseline.
   Capture Get-ClusterNode, Get-ClusterGroup owners, Get-VirtualDisk and Get-StoragePool health.
   Result: clean baseline.
2. Drain a node.
   Run Suspend-ClusterNode -Drain on the node that owns the VM. Roles should live-migrate off it.
   Result: node Paused, VM moved to a surviving node, no guest reboot.
3. Confirm and resume.
   Confirm the VM is Online elsewhere and storage stays Healthy. Then Resume-ClusterNode.
   Result: node rejoins, cluster back to all Up.

Stage 2 - Ungraceful failure and recovery (the real test).
4. Baseline again and start the continuity probe.
   Result: live signal against the VM.
5. Fail a node hard.
   Power the node off abruptly through iDRAC or the power button, simulating a real failure. Pick a
   node that does NOT currently own the VM first, to observe storage behavior without a VM failover,
   then optionally repeat on the VM owner to observe failover.
   Result: one node down.
6. Observe cluster and storage response.
   The cluster should stay Online on quorum plus witness. Get-VirtualDisk may show Degraded but must
   stay Online and serve IO. If the failed node owned the VM, the VM should restart on a surviving node.
   Result: cluster survives, storage online, VM running somewhere.
7. Recover the node.
   Power the node back on. Watch it rejoin with Get-ClusterNode, and watch Storage Spaces Direct
   resync with Get-StorageJob until virtual disks return to Healthy.
   Result: node back Up, storage repaired to Healthy.

## Success criteria

- Graceful drain moves roles with no guest reboot.
- After a hard node loss, the cluster stays Online and storage stays Online, Degraded is acceptable
  during the outage.
- A VM on the failed node restarts on a surviving node.
- The node rejoins and Storage Spaces Direct resyncs back to Healthy with no manual repair.

## Evidence to capture (out/)

- Cluster and storage health at baseline, during the outage, and after recovery.
- Get-StorageJob output showing the resync progressing to done.
- VM owner and power state across the failure.
- Continuity-probe log with timestamps around the failure and the failover.

## Risks and notes

- Hard power-off on marginal hardware carries a small risk the node does not come back cleanly. Have
  the reimage and Arc re-onboard path ready as a worst case, it is documented in the runbooks.
- Do not fail two nodes at once on a 4-node three-way mirror. That can take storage offline and is out
  of scope for this POC.
- Watch that the witness actually holds quorum. If the cluster goes offline on a single node loss, the
  witness or quorum config needs attention.

## Rollback

- Bring the powered-off node back on and let Storage Spaces Direct resync. Confirm Healthy before
  declaring the sprint done. No configuration rollback is needed if the cluster recovered on its own.

