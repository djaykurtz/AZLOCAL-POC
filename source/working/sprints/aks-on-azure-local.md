---
title: "Sprint S5 - Deploy AKS on Azure Local and validate"
domain: [containers]
layer: [kubernetes]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [sprint, aks-arc, sprint-s5]
updated: 2026-08-14
---

# Sprint S5 - Deploy AKS on Azure Local and validate

Sprint S5 (PoC Validation Part 2). Status: planned.
Cluster: AZL-CLUSTER-01. Custom location: azl-cluster-01-cl. Arc bridge: AZL-CLUSTER-01-arcbridge.

Integrated execution plan for S5 and the follow-on S7 load-balancer/scale demonstration:
- docs/planning/aks-and-scale-work-plan.md

## Objective

Stand up an AKS cluster on Azure Local (AKS Arc / aksarc) on top of the POC cluster and prove basic
workload scheduling and exposure. This is the supported way to run containers ON the cluster and is the
foundation for S7 (load balancer + scale).

## Surface already confirmed (container-surface-findings.md)

- Providers Registered: Microsoft.HybridContainerService, KubernetesConfiguration, Kubernetes,
  ExtendedLocation, ResourceConnector.
- az extension aksarc installs clean (create/list/get-versions/nodepool/vnet).
- No AKS clusters exist yet. Custom location Succeeded.

## Prerequisites

- A logical network for the AKS nodes with an IP pool on the mgmt subnet (same gap as S1). AKS Arc
  needs an AKS "arcnetwork"/logical network plus a control-plane IP and a load-balancer VIP range.
- Enough free mgmt IPs: control-plane IP + node IPs + LB VIP pool. Confirm against the reserved block;
  InfraLNET static pool .201-.203 is infra-only and nearly exhausted, so a dedicated tenant pool is needed.
- A Kubernetes version from az aksarc get-versions.
- PIM active; KV reachable.

## Procedure

1. Create the AKS logical network / arcnetwork (az aksarc vnet or the logical-network create) mapped to the
   mgmt VLAN with a static IP pool sized for control plane + nodes + a separate LB VIP range.
   Result: a network AKS can consume.
2. Create the AKS cluster: az aksarc create with the custom location, the network, a small node pool
   (1-2 nodes, 2-4 vCPU), an SSH key, and the chosen K8s version.
   Result: provisioningState Succeeded; control plane reachable.
3. Get credentials: az aksarc get-credentials; kubectl get nodes.
   Result: nodes Ready.
4. Deploy a ClusterIP workload first: tests/kubernetes/smoke manifests (deployment + ClusterIP service).
   Result: pods Running, in-cluster curl works.
5. Scale the deployment (kubectl scale) and confirm rescheduling.
   Result: replicas scale up/down cleanly.
6. Recreate: delete a pod, confirm the ReplicaSet reschedules it.
   Result: self-heal works.
7. Leave the AKS cluster up for S7 (LoadBalancer + node-pool scale).

## Success criteria

- AKS Arc cluster reaches Succeeded and nodes are Ready.
- A ClusterIP workload runs and is reachable in-cluster.
- Scale and self-heal work.

## Evidence

- out/_aksarc-create-*.txt, out/_aks-smoke-*.txt.
- Reuse scripts/Invoke-AksSmokeValidation.ps1 and scripts/Test-KubernetesManifests.ps1 for preflight.

## Risks / notes

- LoadBalancer service type is deferred to S7 (needs the VIP path / MetalLB or the Arc LB).
- IP planning is the real gate: keep the AKS pool and LB VIP range OUT of the K8s service/pod CIDRs
  (10.96.0.0/12, 10.244.0.0/16) and out of the infra pool.

