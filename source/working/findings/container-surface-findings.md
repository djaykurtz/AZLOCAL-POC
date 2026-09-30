---
title: "Container Surface Findings: AKS on Azure Local and the Docker VM path"
domain: [containers]
layer: [cluster]
type: evidence
status: current
proof: proven
audience: [engineer]
tags: [container-surface, capability-check, findings]
updated: 2026-07-28
---

# Container Surface Findings: AKS on Azure Local and the Docker VM path

Date: 2026-07-28. Cluster AZL-CLUSTER-01. Custom location azl-cluster-01-cl.
Source data: out/_container-surface-*.txt.

## Summary

The platform is ready for both container paths at the provider and tooling level. The only gaps are
an IP pool for AKS load balancing and, for the Docker VM path, the same VM image that gates S1.

## Kubernetes: AKS enabled by Azure Arc (AKS on Azure Local)

State:
- All required providers are Registered: Microsoft.HybridContainerService, Microsoft.KubernetesConfiguration,
  Microsoft.Kubernetes, Microsoft.ExtendedLocation, Microsoft.ResourceConnector.
- The aksarc CLI extension installs cleanly (az aksarc). Command surface: create, list, get-versions,
  nodepool, vnet.
- No provisioned AKS clusters exist yet (az aksarc list returns empty).
- A logical network exists, AZL-CLUSTER-01-InfraLNET, but it is type Infrastructure with a nearly
  exhausted static pool (10.10.1.201 to .203). That network is for the cluster's own infra, not for
  tenant AKS.

What AKS on Azure Local needs before bring-up:
1. A logical network for the AKS nodes on the management VLAN, with a static IP range or DHCP for the
   Kubernetes node VMs.
2. A separate block of IPs for the Kubernetes control plane VIP and the load-balancer VIP pool. On Azure
   Local, AKS uses either MetalLB or the built-in HA Proxy/kube-vip path for LoadBalancer services, so we
   need a small set of free management-subnet IPs reserved for VIPs, distinct from the node IPs and the
   cluster infra IPs.
3. az aksarc get-versions against the custom location to pick a supported Kubernetes version.
4. The AKS node image. This is acquired through the AKS Arc flow, not necessarily through
   Microsoft.EdgeMarketplace, so AKS may be less blocked than the tenant VM path. Confirm at create time.

Recommended first AKS test (maps to poc_kubernetes_test_plan.txt):
- Create one AKS cluster with a single small node pool.
- Deploy the smoke manifests in tests/kubernetes/smoke with ClusterIP first.
- Then test a LoadBalancer service once the VIP pool is confirmed.
- Capture kubectl get nodes/pods/services/events to out/.

## Docker: container operations on a disposable VM

State:
- Per ADR 0006, normal Docker operations run in a disposable Linux VM on the cluster, not on the host nodes.
- That VM needs a VM image, which is the same blocker as sprint S1. So the Docker VM path is gated on
  either the EdgeMarketplace registration or the custom VHD.
- Once a VM exists, the Docker test sequence in poc_docker_operations_test_plan.txt Phase B applies:
  install a container runtime, pull from MCR, build/run/inspect/log/exec/stop/restart/publish.

## Order of operations recommendation

1. Sprint S1 first: get one tenant VM up (custom VHD or marketplace). Unblocks the Docker VM path too.
2. AKS bring-up can proceed somewhat in parallel because it does not depend on the tenant VM image, but it
   does need the VIP/node IP pool decided. Reserve those management-subnet IPs before AKS create.
3. Container ops on the VM, then AKS workload smoke, per the existing test plans.

## Open items to line up

- Reserve a small management-subnet IP range for AKS node IPs plus VIPs (like we did for the cluster infra
  block). Confirm free addresses beyond the .200 to .207 infra reservation.
- Decide the tenant VM image path (EdgeMarketplace registration via directory admins, or custom VHD).

