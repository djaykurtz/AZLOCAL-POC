---
title: "Sprint S1 - Deploy test VMs on the cluster"
domain: [compute]
layer: [cluster]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [sprint, vm-deploy, lifecycle, sprint-s1]
updated: 2026-08-13
---

# Sprint S1 - Deploy test VMs on the cluster

Sprint S1 (PoC Validation Part 1). Status: planned.
Cluster: AZL-CLUSTER-01. Custom location: azl-cluster-01-cl. Arc bridge: AZL-CLUSTER-01-arcbridge.

## Objective

Provision an Arc-enabled VM on the Azure Local cluster and prove the full VM lifecycle. This is
the foundation sprint. Live migration and node-failure tests both need a running VM first.

Windows Server 2025 focused matrix:
- docs/test-plans/windows-server-2025-on-cluster-test-plan.md

## Prerequisites

- Cluster deployed and ConnectedRecently. Done.
- Custom location present. Done (azl-cluster-01-cl).
- A VM image available on the cluster. This is the likely first blocker. Marketplace images flow
  through Microsoft.EdgeMarketplace, which is currently NotRegistered and needs an owner or directory admins
  to register. A custom image uploaded from a VHD is the fallback if marketplace stays blocked.
- A logical network defined on the cluster that maps to the management VLAN with an IP pool or DHCP.
- PIM roles active. Key Vault reachable if secrets are needed.

## Procedure

1. Confirm the platform surface.
   Run az to list the custom location and confirm the Arc VM extension is installed on the cluster.
   Result: custom location id in hand for the VM create call.

2. Create the logical network.
   Call the Arc VM logical-network create against the custom location, mapped to the mgmt VLAN with a
   static IP pool inside the reserved range or DHCP.
   Result: a logical network the VM NIC can attach to.

3. Get a VM image.
   Preferred: register Microsoft.EdgeMarketplace, then create a marketplace image (small Linux, for
   example Ubuntu, or Azure Linux). Fallback: create a custom image from an uploaded VHD.
   Result: an image resource on the custom location.

4. Create the VM.
   Call the Arc VM create with a small size (2 vCPU, 4 GB), the image, the logical network, an OS disk,
   and admin credentials. Prefer SSH key for Linux.
   Result: VM resource provisioning.

5. Verify running and reachable.
   Poll power state to Running. Reach it over the approved network path with SSH or RDP.
   From inside the VM, resolve and reach mcr.microsoft.com and management.azure.com to confirm egress.
   Result: a reachable guest with working outbound.

6. Exercise lifecycle.
   Stop, start, and restart the VM through the Arc VM control plane and confirm each state change.
   Result: lifecycle operations all succeed.

7. Clean up or keep.
   Keep one VM running for the S2 and S3 sprints. Delete any throwaway VMs.
   Result: a known-good VM staged for the next sprints.

## Success criteria

- A VM reaches Running on the cluster.
- The VM is reachable over the management path.
- Outbound from the guest works.
- Stop, start, and restart all succeed.
- VM placement node is recorded for the migration sprint.

## Evidence to capture (out/)

- VM resource name, size, image, node placement, private IP.
- Screenshot or JSON of power-state transitions.
- Guest reachability output (nslookup and curl -I to MCR and ARM).

## Risks and notes

- EdgeMarketplace not registered is the most likely blocker. Escalate registration early or plan the
  custom-VHD path.
- Image size versus available S2D capacity on marginal hardware. Keep images small.
- Logical network and IP pool must not collide with the six infra IPs the cluster reserved.

## Rollback

- Delete the VM, image, and logical network in reverse order. None of this touches cluster health.

