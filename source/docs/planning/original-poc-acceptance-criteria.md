---
title: "Original Azure Local POC acceptance criteria"
domain: [platform]
layer: []
type: reference
status: current
proof: documented
audience: [leadership, engineer]
tags: [acceptance-criteria, scope, traceability, requirements]
updated: 2026-08-19
---

# Original Azure Local POC acceptance criteria

## Purpose

This document preserves the recovered original POC/demo acceptance criteria and maps each item to current evidence. The traceability section adds current status without changing the original intent.

## Original criteria

### Sprint 1 - Fact finding

- Sync with the network and datacenter teams to familiarize with resources.

### Minimum viable product requirements

1. Three or more compute nodes imaged with Azure Stack HCI and connected to an Azure subscription as an Azure Local instance.

### Sprint 2 - Six-node deployment target

- Subscription for the POC: `contoso-lab-sub`.
- Create resource groups.
- Deploy resources while keeping security and security compliance KPIs in mind.

### Sprint 3 - IaaS virtual machines

1. Infrastructure as a Service virtual machine roles can be deployed manually and through automation or scripting from Azure Portal, Azure CLI, and PowerShell.

- IaaS VMs running on the Azure Local instance can connect to, and be connected to from, corporate network resources.

### Goals and targets of opportunity

1. Docker and Kubernetes container clusters or swarms.
   - On-premises hosting of containerized workloads with high availability and Azure management control-plane tools.
2. Azure integrated load balancer in front of IIS, web-server, or similar role VMs.
   - Provide high-availability tools and services for future infrastructure deployments.
3. VM Availability Sets.
   - Increase service availability/resiliency with VM groups serving a role/service while isolated to different fault/update domains.
4. VM Scale Sets.
   - Enable auto-scale up/down of VM counts for a role based on service demand.
5. Azure database software as a service.
   - Deploy highly available/scalable databases with less manual SQL/OS maintenance.
6. Azure Storage Services.
   - Test locally hosted blob, queue, and table storage.
   - Enable tools/services using Azure Storage without prematurely accruing cloud operating costs.
7. Azure DevOps pipelines and hybrid workers.
   - Enable tighter use of local compute for compile, pipelines, and tools such as Ansible or Terraform.
8. Prepare a threat model.
9. Prepare a demo of findings.

## Traceability and current result

| Original criterion | Current POC result | Status | Evidence and boundary |
| --- | --- | --- | --- |
| Fact finding with the network and datacenter roles | Storage fabric, switch, IP, and hardware investigations completed. | Complete | VLAN/trunk and adapter-naming issues were identified and corrected before deployment. |
| Three or more Azure Local nodes | Four-node Azure Local cluster deployed: 01, 02, 04, 06. | Complete | Cluster, S2D, Arc Resource Bridge, and custom location are operational. |
| Six-node target | Four-node functional POC selected; 03 and 05 are not members. | Partial by scope decision | [Four-node POC scope](../decisions/0004-four-node-functional-poc-scope.md). |
| Subscription/RG/security | `contoso-lab-sub` and `rg-azlocal-poc-001` used; RBAC/PIM/security boundaries documented. | Complete for POC | [Permissions register](../access/azure-permissions-and-capability-register.md). |
| Manual IaaS VM deployment | Windows Server 2025 and Linux VMs created on Azure Local. | Complete | Image, lifecycle, migration, and recovery evidence exists. |
| Automated/scripting VM deployment | Terraform planned, created, verified, and cleaned up an isolated Azure Local VM. | Complete for human-operated POC | [Terraform sprint plan](../../working/sprints/terraform-against-cluster.md). |
| Corporate network VM connectivity | Tenant network/IP allocation and Docker/Dockge guest access demonstrated. | Complete for POC | Tenant logical network and guest connectivity validated. |
| Docker and Kubernetes workloads | Docker/Dockge ran in Linux VM; AKS Arc dashboard has replicas, endpoint reconciliation, and self-healing. | Complete for functional POC | [Integration test results](kubernetes-terraform-integration-test-results.md). |
| Integrated load balancer | Internal Kubernetes Service routing proven; external MetalLB VIP is provider-registration blocked. | Partial with explicit boundary | In-cluster requests distributed `17/13` across ready pods; no external VIP. |
| VM Availability Sets | No Azure Availability Set resource exists on Azure Local. | Architecture finding | Clustered VM roles and AKS replicas are applicable resiliency mechanisms. |
| VM Scale Sets | No Azure VM Scale Set resource exists on Azure Local. | Architecture finding and partial proof | Likely original intent was repeatable fleet lifecycle, security/update posture, and demand capacity. Terraform VM lifecycle plus Kubernetes Deployment scale `2 -> 3 -> 2` are proven; node-pool scale and pipeline-grade image/update delivery are deferred. |
| Auto-scale based on demand | HPA not validated. | Deferred | Metrics API unavailable; manual Deployment scale is proven. |
| Azure database SaaS | Not deployed. | Opportunity deferred, and the managed option would not have fit | Not required for current functional POC closure. The bar was highly available, scalable, less manual SQL and OS maintenance, with no product named. SQL Managed Instance enabled by Arc wants 16 GB of free Kubernetes capacity against about 4.3 GiB here, and Arc-enabled PostgreSQL was retired 2025-07-14. Options and workload fit in [database-saas-options-and-workload-fit.md](database-saas-options-and-workload-fit.md). |
| Azure Storage Services | S2D operational; application-level Blob/Queue/Table service not deployed locally. | Opportunity deferred | Define target service/workload before implementation. |
| ADO pipelines/hybrid workers | GitHub Actions source-only validation exists; existing ADO estate is intentionally not rebuilt for this POC. | Complete for POC intent | GitHub Actions validates Terraform, manifests, and PowerShell. ADO hybrid workers remain future crossover only if a real local-network execution need appears. |
| Threat model | Security boundaries and identity separation documented; formal threat-model artifact pending. | Partial | Create capstone/pipeline threat model. |
| Demo of findings | Capstone product architecture and evidence model documented. | In progress | [Capstone product definition](../../capstone/README.md). |

## Closing interpretation

The MVP is complete: a four-node Azure Local system is operational, IaaS VMs were deployed and automated, and container workloads are running under AKS Arc with Azure management integration.

The opportunity list is not an all-or-nothing gate. It includes proven capabilities, Azure Local equivalents, externally governed dependencies, and future workstreams. The capstone should present those distinctions directly.

### Current sprint closure interpretation

| Target | Closure result |
| --- | --- |
| Terraform provisioning | Confirmed. Terraform planned, created, verified, reconciled state for, and cleaned up an isolated Azure Local VM stack. |
| Load balancing capability | Confirmed at the Kubernetes internal-Service layer. Thirty independent in-cluster requests were distributed `17/13` across two ready dashboard pods, and EndpointSlices reconciled during scale and recovery. |
| External Service VIP | Documented external governance boundary. MetalLB requires subscription provider registration that is intentionally not being escalated for this POC. |
| ADO/hybrid worker | Not required for POC closure. Existing ADO pipelines remain unchanged; GitHub Actions is the lightweight source-validation proof. |

### VM Scale Set intent interpretation

VM Scale Sets were a common Azure design direction when these criteria were written because they package repeatable VM deployment, desired capacity, scale behavior, and a more manageable security/patching posture. Azure Local does not support the Azure VMSS resource type, so literal VMSS deployment is not an available test target.

| Original VMSS concern | Azure Local-supported equivalent | Current result |
| --- | --- | --- |
| Repeatable role deployment | Terraform/IaC-managed Arc VM resources or image-based VM creation | Terraform isolated VM lifecycle proven. |
| Application instance scale | Kubernetes Deployment replicas | Dashboard `2 -> 3 -> 2` and self-healing proven. |
| Worker capacity scale | AKS node-pool scale | Deferred pending a separate capacity decision. |
| Security/update posture | Azure Local host update management, guest OS/image lifecycle, and pipeline validation | Host/guest lifecycle evidence exists; pipeline-grade identity and image delivery remain follow-on work. |
| Controlled rollout/rollback | Kubernetes rolling updates plus versioned images and CI evidence | Design documented; custom image delivery not yet implemented. |

## Follow-on gaps

1. External Kubernetes VIP through MetalLB if subscription provider registration is later approved.
2. Metrics Server and a bounded HPA test.
3. AKS node-pool scale after a fresh capacity decision.
4. Formal threat model for capstone and pipeline identity scope.
5. GitHub OIDC, remote Terraform state, protected apply/destroy environments, and custom dashboard image delivery.
6. Azure DevOps hybrid worker only if ADO remains a required platform integration.
7. Database and Azure Storage opportunities after a specific application workload justifies them.

