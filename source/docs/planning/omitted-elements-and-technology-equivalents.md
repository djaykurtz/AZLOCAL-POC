---
title: "Omitted POC elements and technology equivalents"
domain: [platform]
layer: []
type: reference
status: current
proof: documented
audience: [leadership, engineer]
tags: [scope-boundary, equivalents, load-balancer, vmss, not-in-scope]
updated: 2026-08-20
---

# Omitted POC elements and technology equivalents

## Purpose

The original POC opportunity list included several Azure public-cloud resource names that are unavailable on Azure Local, were too broad to be acceptance criteria, or depend on external governance. This guide explains the intended capability, the Azure Local-supported equivalent, the current POC evidence, and the remaining boundary.

It prevents two common mistakes:

1. Calling a POC incomplete because it did not deploy an unavailable Azure resource type.
2. Claiming that a similar technology was proven when only part of the intended behavior was tested.

## Summary matrix

| Original element | Why omitted or deferred | Intended capability | Azure Local-supported equivalent | Current evidence | Remaining work or boundary |
| --- | --- | --- | --- | --- | --- |
| Azure Standard Load Balancer | Not an Azure Local resource. | Stable endpoint in front of multiple healthy backends. | Kubernetes `Service`, EndpointSlices, and MetalLB VIP when configured. | ClusterIP Service routed 30 independent in-cluster requests `17/13` across two ready pods; EndpointSlice updated with scale/recovery. | External VIP requires `Microsoft.KubernetesRuntime` registration, intentionally not escalated. |
| VM Scale Sets | Not an Azure Local resource. | Repeatable role deployment, desired capacity, scale, and better update posture. | Terraform/IaC Arc VMs, Kubernetes Deployments, AKS node pools, versioned images, rollout controls. | Terraform VM lifecycle and Deployment `2 -> 3 -> 2` scale/self-heal proven. | AKS node-pool scale, HPA, custom image delivery, and pipeline-grade update flow remain future work. |
| VM Availability Sets | Not an Azure Local resource. | Place related instances across failure/update domains. | Clustered VM roles, Azure Local host recovery, Kubernetes replicas, pod topology/spread constraints when needed. | VM migration and host reboot recovery proven; dashboard replicas and self-heal proven. | Explicit pod anti-affinity/topology-spread policy not tested. |
| Docker directly on Azure Local hosts | Deliberately excluded by ADR 0006. | Build/run/manage containers near on-prem compute. | Docker/Dockge in a Linux guest VM; AKS Arc for supported orchestration. | Docker/Dockge guest workload and AKS dashboard workload proven. | Curated Docker lifecycle evidence and custom image registry are follow-on. |
| External Kubernetes LoadBalancer VIP | Provider registration unavailable at subscription scope. | Management-network reachability to a multi-backend application endpoint. | Current ClusterIP plus controlled local `kubectl port-forward`; future MetalLB VIP. | Internal routing and endpoint reconciliation proven. | Subscription `Microsoft.KubernetesRuntime/register/action` decision. |
| HPA / demand autoscale | Metrics API is unavailable; no bounded HPA policy selected. | Increase/decrease application replicas based on demand. | Manual Deployment scaling now; HPA after Metrics Server validation. | Manual `2 -> 3 -> 2` scale proven. | Metrics Server, resource metrics, bounded load policy, and max replica guardrail. |
| AKS node-pool scale | Deferred for capacity discipline. | Add worker capacity under sustained application demand. | AKS Arc node-pool scale. | One worker supports the current dashboard scale demonstration. | Fresh capacity decision, healthy storage maintenance state, then one-worker scale test. |
| Azure Database SaaS | No business workload selected, and the managed option does not fit this cluster. | Managed/scalable database with reduced OS/SQL maintenance. | SQL Managed Instance enabled by Arc needs 16 GB free Kubernetes capacity and an 8 GB minimum node; the worker reports 5.86 GiB. Arc-enabled PostgreSQL was retired 2025-07-14, so Postgres workloads have no managed path. Remaining options are SQL Server in an Arc-connected VM, a database container on AKS Arc, or an Azure-hosted database over the network. | None. | Name the application first. The engine it wants decides whether a managed option exists. See [database-saas-options-and-workload-fit.md](database-saas-options-and-workload-fit.md). |
| Azure Blob/Queue/Table services | No application workload selected; these are Azure services, not native S2D APIs. | Object, queue, and table service APIs for application development. | Azure Storage account, emulator-compatible development tool, or chosen local application storage component. | S2D storage foundation is operational only. | Define whether cloud Azure Storage, local emulation, or a workload-specific service is required. |
| Azure DevOps hybrid worker | GitHub repository and GitHub Actions selected for current source validation. | Use local compute for build/pipeline/orchestration work. | GitHub Actions source validation now; ADO agent/hybrid worker if organization requires ADO specifically. | Credential-free GitHub Actions workflow validates Terraform, Kubernetes manifests, and PowerShell syntax. | Decide whether ADO is a mandatory platform requirement. |
| Full six-node cluster | Four-node functional scope selected. | More capacity and host-failure margin. | Four-node Azure Local cluster with optional later add-node path. | Four active nodes deployed and functional. | Decide whether six nodes are a hard requirement; repair/onboard spare nodes if promoted. |
| Formal threat model | Security analysis exists in pieces, not as a formal artifact. | Identify threats, trust boundaries, mitigations, and residual risk. | Dedicated threat-model document for cluster, pipeline, dashboard, evidence, and operator paths. | PIM/RBAC, identity, external dependency, and no-write dashboard boundaries documented. | Create and review formal threat model. |

## How to use the equivalence model

When a requirement uses an Azure public-cloud term, translate it before deciding whether it was omitted:

```text
Named Azure resource
-> intended operational capability
-> Azure Local/Kubernetes-supported mechanism
-> executed proof
-> stated remaining boundary
```

Examples:

```text
VM Scale Set
-> repeatable role lifecycle, capacity, and update posture
-> Terraform-managed VM + Kubernetes Deployment + AKS node pool
-> Terraform lifecycle and pod scale proven
-> node-pool/HPA pipeline work deferred
```

```text
Azure Load Balancer
-> stable endpoint to healthy backends
-> Kubernetes Service + EndpointSlices + MetalLB VIP
-> internal routing proven
-> external VIP gated by subscription registration
```

## Current POC boundaries

- This is a functional POC, not a production HA, DR, performance, or patch-compliance certification.
- The node 01 retired NVMe path is a maintenance condition. Three-way mirror preserves availability for small,
  reversible work; storage mutation, stress, and large capacity expansion remain deferred.
- The dashboard remains internal via ClusterIP and local port-forward until the provider-registration decision changes.
- Terraform is proven for a human-operated isolated VM lifecycle. Remote state, GitHub OIDC, protected pipeline
  environments, and custom image delivery remain later delivery work.

## Related records

- [Azure Local platform boundary research](azure-local-platform-boundary-research.md)
- [Original POC Acceptance Criteria](original-poc-acceptance-criteria.md)
- [POC Requirements Gap Audit](poc-requirements-gap-audit.md)
- [Terraform, Docker, AKS, and Azure Local Model](terraform-docker-aks-responsibility-model.md)
- [Kubernetes and Terraform integration test results](kubernetes-terraform-integration-test-results.md)
- [External dependencies and POC lessons](external-dependencies-and-poc-lessons.md)

