---
title: "Windows Server 2025 on the cluster test plan"
domain: [compute]
layer: [cluster, application]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [windows-server-2025, marketplace-image, vm-lifecycle, live-migration, host-reboot-recovery]
updated: 2026-08-13
---

# Windows Server 2025 on the cluster test plan

Acceptance plan for hosting a Windows Server 2025 guest on the cluster, covering deployability,
manageability, and resilience.

The matching demonstration script is the [Windows Server 2025 demo quick reference](../../docs/runbooks/ws2025-azure-local-demo-quickref.md).

## Reference content

```text
========================================================================
  WINDOWS SERVER 2025 ON AZURE LOCAL CLUSTER - TEST PLAN
========================================================================
  Date: 2026-08-13
  Scope: AZL-CLUSTER-01 (4-node functional cluster)
  Purpose: Validate that a Windows Server 2025 guest image hosted on the
  cluster is deployable, manageable, and resilient for POC use.

  Demonstration quick reference:
  - docs/runbooks/ws2025-azure-local-demo-quickref.md

========================================================================
  PRECHECKS
========================================================================
  1) Access and control plane
  - Microsoft.EdgeMarketplace is Registered on subscription.
  - PIM roles active: Azure Stack HCI Administrator + User Access Administrator.
  - Custom location present and healthy: azl-cluster-01-cl.

  2) Cluster and network
  - Cluster resource reports healthy/connected.
  - Logical network for tenant VM exists with approved/reserved IP pool.
  - Target static IP is reserved in project-owned range before VM create.

  3) Image readiness
  - Marketplace Windows Server 2025 image imported into gallery image.
  - Gallery image provisioningState is Succeeded.

========================================================================
  TEST CASES
========================================================================
  WS25-T01 - Import Marketplace image to gallery
  Goal:
  - Prove Edge Marketplace path works end-to-end for Azure Local image import.
  Steps:
  - Create a gallery image from a Windows Server 2025 marketplace source.
  - Confirm image resource reaches Succeeded.
  Pass criteria:
  - Gallery image exists, osType=Windows, provisioningState=Succeeded.
  Evidence:
  - image show output (name, osType, provisioningState).

  WS25-T02 - Deploy VM from gallery image
  Goal:
  - Prove Windows Server 2025 VM can be created on the cluster.
  Steps:
  - Create NIC on approved logical network.
  - Create VM from WS2025 gallery image with approved credentials.
  - Wait for power state Running.
  Pass criteria:
  - VM provisioningState=Succeeded and powerState=Running.
  Evidence:
  - VM show output (name, host node, power state, provisioning state).

  WS25-T03 - Guest access and bootstrap
  Goal:
  - Prove guest is reachable and admin access works.
  Steps:
  - Validate IP assignment matches reserved target.
  - RDP to guest with admin credential.
  - Confirm hostname, OS version, and time sync.
  Pass criteria:
  - Successful RDP login and expected Windows Server 2025 identity.
  Evidence:
  - Screenshot or command output showing OS caption/build and hostname.

  WS25-T04 - Arc guest manageability
  Goal:
  - Prove VM is visible and manageable in Arc.
  Steps:
  - Confirm Microsoft.HybridCompute/machines entry for the guest.
  - Confirm status Connected.
  - Apply slot/role tags if used by dashboard model.
  Pass criteria:
  - Arc resource exists and status Connected.
  Evidence:
  - Arc machine show output (status, agent version, tags).

  WS25-T05 - Lifecycle control plane operations
  Goal:
  - Prove day-2 lifecycle operations work.
  Steps:
  - Stop VM, Start VM, Restart VM from control plane.
  - Record resulting power states.
  Pass criteria:
  - Each operation succeeds and power state transitions are correct.
  Evidence:
  - Lifecycle log with before/after states for all operations.

  WS25-T06 - Live migration
  Goal:
  - Prove guest can live migrate across nodes.
  Steps:
  - Record current owner node.
  - Live migrate to target node.
  - Confirm role remains online and owner changes.
  Pass criteria:
  - Owner node changes; guest remains online; no reboot event.
  Evidence:
  - Cluster role owner before/after output and VM uptime continuity.

  WS25-T07 - Node reboot resilience
  Goal:
  - Prove workload resiliency during host reboot event.
  Steps:
  - Place VM on a known host.
  - Reboot that host using approved method.
  - Observe cluster state, disk health transition, and VM continuity/failover.
  Pass criteria:
  - Cluster recovers; VM returns Running/Online; storage returns Healthy.
  Evidence:
  - Timeline output for node down/up, VM state, and storage jobs.

  WS25-T08 - Dashboard visibility
  Goal:
  - Prove VM appears in dashboard tile and tagging model works.
  Steps:
  - Refresh workbook after VM is Arc-connected.
  - Verify row appears in tenant VM table.
  - Verify slot/role tags render if applied.
  Pass criteria:
  - VM is visible with expected columns and status.
  Evidence:
  - Workbook screenshot and backing query output.

  WS25-T09 - Teardown and cleanup
  Goal:
  - Prove test leaves no orphaned resources.
  Steps:
  - Delete VM.
  - Delete test NIC.
  - Optionally keep or delete WS2025 gallery image per decision.
  - Validate no orphaned resources remain.
  Pass criteria:
  - No orphaned VM/NIC resources; retained artifacts are intentional.
  Evidence:
  - Final resource list filtered to VM/NIC/image names.

========================================================================
  MINIMUM ACCEPTANCE BAR
========================================================================
  Required pass set for "WS2025 hosted on cluster validated":
  - WS25-T01 through WS25-T07 must pass.
  - WS25-T08 recommended for demo readiness.
  - WS25-T09 required before closing sprint if VM is temporary.

========================================================================
  EXECUTION NOTES
========================================================================
  - Reuse existing scripts where possible:
    - New-AzLocalTestVm.ps1
    - Invoke-VmLifecycle.ps1
    - Invoke-LiveMigrationTest.ps1
    - Invoke-NodeFailureTest.ps1
  - Keep one naming convention for evidence files in out/:
    - _ws2025-t01-*.txt ... _ws2025-t09-*.txt
  - If any AzureStackHCI write operation fails immediately after PIM activation,
    wait 2-3 minutes and retry once (known propagation delay).
```
