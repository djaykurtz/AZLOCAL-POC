---
title: "Azure Local Proof of Concept"
domain: [platform]
layer: []
type: index
status: current
proof: proven
audience: [leadership, engineer, operator]
tags: [overview, project-story, home, poc]
updated: 2026-08-26
---

# Azure Local Proof of Concept

This repository records the build of `AZL-CLUSTER-01`, a four-node Azure Local proof of concept. The goal was not to claim production readiness. The goal was to prove that the lab hardware and Azure control plane could form a working Azure Local cluster, host real Windows and Linux workloads, run AKS, and demonstrate the important recovery and application-platform behaviors.

The project became a useful engineering story because the difficult parts were not just clicking through a deployment wizard. Success required resolving storage, network, security, identity, hardware, and operations constraints in the right order.

## What Is Proven

- A four-node Azure Local cluster is deployed and connected to Azure.
- Storage Spaces Direct is operational across the cluster.
- Azure Arc Resource Bridge and the custom location are operational.
- Azure Local Marketplace image import works with Windows Server 2025 Datacenter: Azure Edition Core and Desktop gallery images.
- A Windows Server 2025 Core VM has been created, lifecycle-tested, live-migrated, and recovered after its host rebooted.
- A Docker and Dockge management VM has been hosted on the cluster without installing Docker on Azure Local hosts.
- A minimal AKS Arc cluster runs Kubernetes `1.33.5` with an Azure Linux control plane and worker.
- Kubernetes workload scheduling, MCR image pull, manual replica scale, and pod self-healing have been demonstrated.
- A two-replica Kubernetes-hosted Azure Local dashboard is running internally through ClusterIP.

## The Journey

The cluster reached a usable state through several hard, instructive problems:

1. **Host readiness and hardware parity**
	- The active POC shape was narrowed to four functional nodes rather than trying to solve every spare-node issue first.
	- Secure Boot, driver, storage-disk, and NIC consistency gates had to pass before Azure Local deployment could proceed.
	- The hosts are Dell Precision 7960 Rack workstations, not certified PowerEdge Azure Local servers. That defines an intentional POC boundary.

2. **Storage network discovery**
	- The storage fabric initially failed Azure Local validation in both directions.
	- Direct DAC testing proved hosts, Mellanox adapters, and VLAN tagging were healthy.
	- The root cause was a combination of inconsistent Windows adapter naming and missing switch trunk mode on one storage switch.
	- Correcting the adapter-to-switch mapping and trunk configuration cleared storage validation and allowed deployment.

3. **Security and observability conflict**
	- An incumbent corporate security monitoring extension occupied a singleton monitoring-agent slot.
	- Azure Local observability could not start until the documented opt-out tag and extension-removal path freed that slot.
	- This was treated as a scoped, reversible exception rather than removing broad security controls.

4. **Directory and identity pivot**
	- The original corporate Active Directory path was blocked by policy inheritance and service-account logon constraints.
	- The POC pivoted to the lab-controlled `sim.example.internal` domain, where the required OU, delegation, deployment account, and validation behavior could be established.

5. **Real workload validation**
	- The cluster is not just registered. It has proven VM lifecycle operations, live migration, and one-node reboot recovery.
	- AKS is running a real two-replica workload and recreates deleted pods.
	- Current capacity is intentionally constrained. Node 06 carries Azure Local infrastructure and has less available memory, so workload placement and scaling remain capacity-gated.

## Current Limits

- This is a functional POC, not a production HA, DR, supportability, or performance certification.
- The four-node cluster has limited memory headroom. Avoid assuming every host can accept another general-purpose VM.
- Windows Server 2025 Core is running. The Desktop Experience image imported successfully, but its first VM placement failed on memory-constrained node 06 and has not yet been recreated elsewhere.
- Kubernetes MetalLB VIP exposure is pending subscription registration of `Microsoft.KubernetesRuntime`.
- The Kubernetes dashboard currently uses fixture inventory data. Live Azure inventory requires a dedicated Reader-only runtime identity.

## Repository Guide

| Path | Contents |
|---|---|
| `decisions/` | Significant engineering decisions and their rationale. |
| `docs/planning/` | Work plans, capacity boundaries, test scope, and the AKS/dashboard roadmap. |
| `docs/runbooks/` | Human-reproducible procedures with commands and expected results. |
| `docs/test-plans/` | Focused acceptance plans for VMs, Docker, Kubernetes, Terraform, and recovery. |
| `guide/` | The Azure Local field guide. A standalone document that cites Microsoft's documentation and does not depend on the rest of this repository. |
| `infra/` | Azure and workbook infrastructure definitions. |
| `scripts/` | Reusable PowerShell automation. Review each script before execution. |
| `tests/` | Docker and Kubernetes workload artifacts, including the dashboard scaffold. |
| `pipelines/` | GitHub Actions strategy and future CI/CD definitions. |

## Start Here

- [Current POC status](STATUS.md)
- [Azure Local field guide](guide/azure-local-guide.html)
- [Curated documentation guide](docs/README.md)
- [Engineering decisions](docs/decisions/README.md)
- [Prerequisites from other roles](docs/prerequisites.md)
- [Capstone product definition](capstone/README.md)
- [Repository and GitHub Actions guide](docs/pipelines/github-actions-and-repo-usage.md)

## GitHub Scope

This repository is deliberately curated. It contains source, decisions, runbooks, plans, tests, and reproducible automation. It does not contain credentials, generated output, downloaded media, drivers, administrator kubeconfigs, or raw host data.

See [pipelines/github-actions-and-repo-usage.md](docs/pipelines/github-actions-and-repo-usage.md) for the repository adoption model, identity boundaries, and the staged GitHub Actions path.
