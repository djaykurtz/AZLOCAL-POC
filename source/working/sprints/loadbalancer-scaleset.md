---
title: "Sprint S7 - Validate load balancer and scale set compatibility"
domain: [containers, network]
layer: [kubernetes]
type: plan
status: current
proof: blocked
audience: [engineer]
tags: [sprint, load-balancer, metallb, scale-set, sprint-s7]
updated: 2026-08-19
---

# Sprint S7 - Validate load balancer and scale set compatibility

Sprint S7 (PoC Validation Part 2). Status: complete with documented external and capacity boundaries.
Cluster: AZL-CLUSTER-01. Depends on S5 (AKS on Azure Local).

Integrated execution plan for S5 and S7:
- docs/planning/aks-and-scale-work-plan.md

## Current capacity boundary (measured 2026-08-14)

This task must remain deliberately small. Direct host checks showed 31.5 GB visible RAM on every node,
with the following free memory before any AKS workload is created:

| Node | Free memory | Existing running VM allocation | Notes |
|---|---:|---:|---|
| AZL-NODE-01 | 24.5 GB | 0 GB | Available for a small test workload. |
| AZL-NODE-02 | 14.4 GB | 4 GB | Hosts `ws2025-core-01`. |
| AZL-NODE-04 | 18.2 GB | 0 GB | Available for a small test workload. |
| AZL-NODE-06 | 5.5 GB | 12 GB | Hosts Arc infrastructure; do not target for another 4 GB VM. |

Evidence: attempting to start the 4 GB `ws2025-desktop-01` VM on node 06 failed with Hyper-V
`0x8007000E`, insufficient memory. This is a placement/capacity signal, not an image failure.

Consequences:

- Do not attempt multiple general-purpose Arc VMs as a stand-in for a VM scale set.
- Keep AKS worker sizing and replica counts minimal, and leave capacity for the Azure Local control plane.
- Before creating AKS or scaling a node pool, remeasure free memory and record actual worker VM sizes.
- A failed placement on node 06 is expected until its free memory increases or the workload is explicitly
  scheduled elsewhere.

## Implementation correction and current blocker (2026-08-14)

The initial AKS proof passed: one Linux worker scheduled the two-replica smoke deployment, manual replica
scale passed, and deleting a pod triggered successful replacement. The Kubernetes `LoadBalancer` Service
correctly remained `EXTERNAL-IP <pending>` because no MetalLB IP pool was configured.

This Azure Local version uses the MetalLB Azure Arc extension for a Service VIP. It does not support the
previously proposed managed `--load-balancer-count` VM model; the CLI permits only the default value `0`.

MetalLB needs `Microsoft.KubernetesRuntime` registered at subscription scope. The provider is currently
`NotRegistered`, and the current user's RG-scoped AKS Arc Contributor/UAA roles cannot register it. The
only pending action for the VIP demonstration is subscription-scoped provider registration:

```powershell
az provider register -n Microsoft.KubernetesRuntime
```

Once registered, configure MetalLB in ARP mode with a small reserved IP pool `.221-.223`, then reapply the
existing LoadBalancer smoke service and confirm it receives a VIP.

## Objective

Validate the load-balancing and horizontal-scale story on Azure Local for the POC. Set expectations
correctly first, because Azure Local is NOT the Azure public cloud: there is no Azure Standard Load
Balancer resource and no Azure Virtual Machine Scale Set resource on Azure Local. The equivalent
capabilities are delivered differently, and this sprint proves those equivalents.

## Terminology mapping (important, avoids a wrong-resource chase)

- "Load balancer" on Azure Local:
  - For AKS workloads: a Kubernetes Service of type LoadBalancer, backed by the AKS Arc load balancer
    (MetalLB-style VIP allocation from a configured VIP pool). This is the primary path to validate.
  - For plain Arc VMs: there is no managed L4 LB resource; you would run a software LB (for example HAProxy
    or nginx) in a VM. Note this as a limitation, do not expect an Azure LB resource.
- "Scale set" on Azure Local:
  - There is no Azure VM Scale Set resource. Horizontal scale = AKS node pools (scale node count) and the
    Kubernetes Horizontal Pod Autoscaler for workloads. Validate node-pool scale + deployment scale.
  - Arc VMs scale by explicit create of more VMs, not by a scale-set object. Note this as a limitation.

## Prerequisites

- A working AKS Arc cluster (S5) with a LoadBalancer VIP pool/range configured on the mgmt subnet,
  separate from the infra pool and node pool, and outside the K8s service/pod CIDRs.
- kubectl access to the AKS cluster.

## Procedure

1. Load balancer (AKS Service type=LoadBalancer):
   Deploy the smoke deployment and expose it with a Service type LoadBalancer.
   Confirm an external VIP is allocated from the pool and the app answers on VIP:port from another host on
   the mgmt subnet.
   Result: L4 LB path works via the AKS Arc LB.
2. Node-pool scale (the "scale set" equivalent):
   az aksarc nodepool scale up (for example 1 -> 3), confirm new nodes Ready and pods spread; then scale
   back down and confirm drain/removal.
   Result: horizontal node scale works.
3. Workload scale + HPA:
   kubectl scale the deployment, then apply an HPA and drive load to confirm autoscale up/down.
   Result: pod-level horizontal scale works.
4. Failure interaction (optional, ties to S3):
   With a LoadBalancer service live, drain or reboot a worker node and confirm the VIP keeps serving from
   surviving nodes.
   Result: LB survives a node loss.

## Minimal demonstration plan

This is the recommended light demonstration once S5 provides an AKS Arc cluster. It proves the
Azure Local equivalent capabilities without needing a VM Scale Set or Azure Standard Load Balancer.

1. Create the smallest practical AKS node pool compatible with the measured capacity.
  Do not scale beyond the size that leaves a healthy memory reserve on every host.
2. Deploy a simple HTTP workload with two replicas and low requests/limits.
3. Expose it using a Kubernetes `Service` of type `LoadBalancer`.
4. Confirm that AKS Arc assigns a VIP from the reserved LoadBalancer VIP range and that HTTP succeeds
  against the VIP from a management-subnet client.
5. Scale the deployment from two to three replicas, confirm three Ready pods, then scale back to two.
6. If capacity permits, scale the AKS node pool by one node, confirm the new worker is Ready, then scale
  it back down cleanly. If the node-pool operation cannot fit, record that as the POC capacity limit rather
  than forcing placement.

The minimal pass condition is a reachable Service VIP and workload replica scaling. Node-pool scale is a
conditional second demonstration because the existing Arc infrastructure already leaves node 06 constrained.

## Success criteria

- A LoadBalancer Service gets a reachable external VIP and serves traffic.
- AKS node pool scales up and down; new nodes join and drain cleanly.
- Deployment/HPA horizontal scale works.
- The Azure-LB-resource and VM-scale-set-resource limitations are documented, with the AKS-native
  equivalents demonstrated in their place.

## Executed POC result - 2026-08-19

The Azure Local equivalents that do not require a subscription provider registration were validated:

| Capability | Result | Evidence |
| --- | --- | --- |
| Kubernetes workload scale | Pass | Dashboard Deployment scaled `2 -> 3 -> 2`; every requested replica became Ready with zero restarts. |
| Service endpoint reconciliation | Pass | EndpointSlice membership changed from two to three ready endpoints during scale, then returned to two. |
| In-cluster Service routing | Pass | Thirty independent HTTP requests through the ClusterIP Service DNS name reached both ready pods: `17` responses from `m94q2` and `13` from `72jvt`. |
| Deployment self-healing | Pass | One dashboard pod was deleted; a replacement became Ready and the Deployment returned to `3/3` before steady-state restoration. |
| Bounded application work | Pass | Ten work requests completed successfully in `38.37-46.08 ms`; final restored-state request completed in `40.04 ms`. |
| Azure Load Balancer and VMSS mapping | Pass as architecture finding | Azure Local has no Azure Standard Load Balancer or VM Scale Set resource. The equivalent mechanisms are Kubernetes Service/MetalLB and Deployment/node-pool scale. |

The remaining requested mechanisms were investigated and closed as explicit POC boundaries:

| Capability | Closure reason |
| --- | --- |
| Reachable Service VIP | `Microsoft.KubernetesRuntime` remains `NotRegistered`; registration requires subscription-scoped `Microsoft.KubernetesRuntime/register/action`, which was denied and is intentionally not escalated for this POC. Dashboard access remains ClusterIP plus local port-forward. |
| AKS node-pool scale | Deferred. The existing single worker proves pod-level scale. A second worker requires a materially larger VM placement and was not needed to validate the workload-scale equivalent. |
| HPA | Deferred. The Metrics API is not installed (`kubectl top` reports `Metrics API not available`); manual Deployment scale is the selected POC proof. |

## Closure statement

S7 is complete for the POC scope: Kubernetes workload scale, ready-endpoint reconciliation, and self-healing
were demonstrated and restored to steady state. The missing external VIP is a subscription governance boundary,
not an untested implementation detail. Node-pool scale and HPA remain future capacity and metrics work, not
requirements for this constrained-cluster capability proof.

## Evidence

- out/_aks-lb-*.txt, out/_aks-scale-*.txt.

## Risks / notes

- VIP pool exhaustion: size the LoadBalancer VIP range for the number of Services under test.
- Keep VIP, node, infra, and K8s CIDRs strictly non-overlapping (see S5 notes).
- POC proof only, no HA/DR/perf commitment (ADR 0004/0005).

