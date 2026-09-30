---
title: "Azure Local POC requirements gap audit"
domain: [platform]
layer: []
type: evidence
status: current
proof: documented
audience: [leadership, engineer]
tags: [gap-analysis, requirements, audit, traceability]
updated: 2026-08-19
---

# Azure Local POC requirements gap audit

## Purpose

Assess the recovered original acceptance criteria against executed POC evidence as of 2026-08-19. This audit
separates four different outcomes that should not be conflated:

- **Proven**: executed with recorded evidence.
- **Partial**: some of the intent is proven, but a stated requirement or test remains incomplete.
- **Architecture substitution**: Azure Local does not expose the originally named Azure resource, so an applicable
  Azure Local/Kubernetes mechanism was tested instead.
- **Deferred or blocked**: not executed, with a known reason and next decision.

The original baseline is preserved in [Original POC Acceptance Criteria](original-poc-acceptance-criteria.md). Capstone design is deliberately outside this audit because it belongs to the next sprint, not to the original POC closure criteria.

## Executive assessment

### Proven core

- Four-node Azure Local cluster, Azure Arc, Arc Resource Bridge, custom location, and Storage Spaces Direct.
- Manual Windows/Linux VM deployment and network reachability.
- VM lifecycle, live migration, planned host reboot/failover behavior, and Terraform human-operated VM lifecycle.
- Docker/Dockge guest workload.
- AKS Arc cluster, workload scheduling, Kubernetes Deployment replica scale, ready EndpointSlice reconciliation,
  in-cluster Service routing, and pod self-healing.
- Source-only GitHub Actions workflow definition for Terraform, Kubernetes manifest, and PowerShell validation.

### Strict acceptance versus opportunity backlog

The recovered list contains two different kinds of statements. Do not use the broad opportunity list as an
all-or-nothing delivery checklist.

| Category | Closure meaning |
| --- | --- |
| MVP and named sprint commitments | Evaluate as actual acceptance criteria. |
| Goals/targets of opportunity | Track as `misc future crossover` unless a separate work item, owner, date, or customer commitment makes an item mandatory. |
| Architecture substitutions | Record the Azure Local/Kubernetes equivalent and avoid treating an unavailable Azure resource type as an unexecuted task. |
| External governance boundary | Record the required action and owner; it is neither silently complete nor a local engineering failure. |

## Detailed requirements matrix

| Requirement area | Status | Evidence | Gap or next test |
| --- | --- | --- | --- |
| Three or more Azure Local nodes | Proven | Four active cluster nodes 01, 02, 04, 06. | None for MVP. |
| Six-node deployment target | Partial by decision | Four-node functional POC selected. Nodes 03/05 are not cluster members. | Add-node readiness and scale-out are not tested. Decision needed before treating six nodes as a requirement again. |
| Azure subscription/RG/security/security compliance posture | Proven for POC baseline | Subscription/RG, PIM/RBAC, SkipSecurityMonitoringAgent exception, and observability conflict evidence. | Posture and boundaries now recorded in [Security posture and boundaries](../access/security-posture-and-boundaries.md). Residual risk sign-off outstanding. |
| Manual IaaS VM deployment | Proven | Windows Server 2025 and Linux guests created on Azure Local. | Desktop Experience guest placement should be re-tested only if still needed; earlier failure was node 06 memory placement. |
| Scripted/automated IaaS VM deployment | Proven, human-operated | Terraform `plan -> apply -> clustered runtime -> destroy -> final empty plan`. | CI-grade state/OIDC/approval pipeline not yet implemented. |
| VM corporate connectivity | Proven for guest access path | Tenant LNET, SSH/Dockge guest access, Arc guest management evidence. | Formal bidirectional connectivity test matrix could be condensed into final demo evidence. |
| Docker container operations | Proven in guest, evidence consolidation needed | `rocky-docker-01` ran Docker/Dockge. | Re-run a concise standard Docker lifecycle transcript if the old evidence is not already curated; custom image build/publish not proven. |
| AKS Arc cluster | Proven | AKS `1.33.5`, control plane and worker Ready. | None for baseline. |
| Kubernetes workload scheduling | Proven | Dashboard Deployment and earlier smoke workload. | None for baseline. |
| Kubernetes replica scale | Proven | Dashboard `2 -> 3 -> 2`, all requested pods Ready. | HPA remains untested. |
| Kubernetes Service routing | Proven internally | 30 independent in-cluster requests distributed `17/13` across two ready pods. | Externally reachable Service VIP remains unavailable. |
| Pod self-healing | Proven | Deleted dashboard pod replaced; Deployment and EndpointSlice recovered. | None for baseline. |
| Integrated external load balancer | Deferred, external governance boundary | MetalLB design and reserved VIP range documented. | `Microsoft.KubernetesRuntime/register/action` at subscription is required; do not treat internal ClusterIP routing as an external VIP proof. |
| VM Availability Sets | Architecture substitution, intent proven | No Azure Availability Set resource on Azure Local. Live migration moved the worker VM between hosts on 2026-09-01 with no observed disruption. | Availability Sets protect against host loss, not host maintenance. Surviving an unplanned node failure is proven separately; surviving it while a workload has only one worker node is not. |
| VM Scale Sets | Architecture substitution, intent capability-checked | No VMSS resource, and the recorded intent was "a more manageable security/patching posture". Both halves of that intent were checked on 2026-09-01. Rolling update replaced every pod with minimum ready endpoints of 2. Live migration moved the host underneath the workload in 16.7s with no disruption visible to Kubernetes. | Capability check only, not a production pattern. Needs a second worker node, pod anti-affinity, a disruption budget, and graceful SIGTERM handling. AKS node-pool autoscale is supported and documented but was never enabled here. |
| Demand-driven autoscale | Deferred | Metrics API unavailable; HPA not configured. | Install/validate Metrics Server and use a bounded HPA workload only if this remains a closure requirement. |
| Azure Database SaaS | Deferred opportunity, and capacity blocked | No database workload deployed. Separately, SQL Managed Instance enabled by Arc requires 16 GB of free Kubernetes capacity and a minimum 8 GB node; the single AKS worker reports 5.86 GiB allocatable with about 4.3 GiB free. `Microsoft.AzureArcData` is Registered and the custom location exists, so this was never permissions. | Choose a specific database service and define why it must run in/with Azure Local, then size the cluster to it. Note Arc-enabled PostgreSQL was retired 2025-07-14 and indirect mode for SQL MI was retired 2025-09, so older guidance is stale. Full analysis in [database-saas-options-and-workload-fit.md](database-saas-options-and-workload-fit.md). |
| Azure Storage blob/queue/table | Deferred opportunity | S2D storage is operational, but no Blob/Queue/Table service workload exists. | Clarify whether local emulation, Azure cloud service, or application integration is the intended test. |
| ADO pipelines/hybrid workers | Complete for POC intent | GitHub Actions source-only validation exists; existing ADO estate is intentionally not rebuilt for this POC. | ADO hybrid worker is future crossover only if a real local-network execution need appears. |
| Threat model | Addressed by substitution | [Security posture and boundaries](../access/security-posture-and-boundaries.md) records inherited controls, platform defaults, the local surface Azure does not reach, and deliberate deviations. | Residual risk acceptances still need project owner sign-off. A structured threat model remains future work. |
| Demo of findings | In progress | Capstone product definition, architecture, design, interaction, and evidence plans exist. | Build the actual learning-environment shell and evolving product pane. |

## Evidence quality gaps

These are not necessarily capability failures, but they affect how confidently the POC can be presented:

| Gap | Why it matters | Remediation |
| --- | --- | --- |
| `STATUS.md` is dated 2026-07-20 and describes pre-deployment blockers. | It contradicts current cluster state and cannot remain the single source of truth. | Replace with a short current-state board or mark it historical and point to this audit plus acceptance traceability. |
| Original Docker/Kubernetes/Terraform preliminary plans still say `PLAN ONLY`. | They understate executed work. | Add execution result links or mark them superseded by sprint and integration records. |
| Terraform VM ARM completion lag required state reconciliation. | This is a real automation behavior that a future pipeline must handle. | Add retry/poll and reconciliation design to CI/CD acceptance criteria; do not claim unattended pipeline readiness yet. |
| PIM expired during NIC cleanup. | Future automation cannot depend on human PIM. | Use dedicated OIDC pipeline identity with exact roles, protected apply/destroy approvals, and remote state. |
| Local service port-forward selects one backend pod. | It cannot prove Service distribution. | Use in-cluster independent requests, as completed, for Service routing proof. |
| Node 01 has one retired NVMe path and `UserStorage_2` remains incomplete. | It is a declared maintenance risk during the POC. | Keep changes small/reversible, complete storage maintenance later, and avoid stress/scale claims. |

## Remaining strict POC tests and decisions

### Requirements that are explicit enough to need a decision

1. **Formal threat model**
   - Superseded for POC closure by [Security posture and boundaries](../access/security-posture-and-boundaries.md),
     which was written 2026-08-31.
   - A threat model is a structured exercise and a shallow one would be worse than none. The posture
     document answers the question a reviewer asks first instead: which controls are relied on, who
     provides them, and what is left over.
   - Remaining decision: the project owner must confirm or amend the eight residual risk acceptances
     listed in that document.

2. **Six-node target decision**
   - The original text named six nodes, while the POC later made an explicit four-node scope decision.
   - Decide whether four functional nodes close the POC or whether an add-node test is still required.

3. **External VIP decision**
   - The original request named an integrated load balancer, while the current platform implementation requires MetalLB.
   - Keep this as a subscription-governance decision, not an open engineering investigation.

### Misc future crossover backlog

These items should remain visible but are not current closure blockers without a concrete workload, owner, or
acceptance definition:

- Azure database SaaS workload.
- Azure Storage Blob/Queue/Table service workload.
- Azure DevOps hybrid worker only if a future workload requires local-network execution beyond the existing ADO estate.
- HPA and demand-driven autoscale after Metrics API availability and a bounded workload are intentionally selected.
- AKS node-pool scale after a separate capacity decision.
- VM availability or scale-set capability discussion beyond the documented Azure Local/Kubernetes equivalents.

### Opportunity tests that remain relevant if promoted

1. **Metrics/HPA feasibility**
   - First validate whether Metrics Server can be enabled on this AKS Arc build without external dependencies.
   - If it can, run a fixed low-rate HPA test with a strict maximum of three dashboard replicas.
   - If it cannot, record manual Deployment scale as the accepted POC substitute.

2. **External VIP implementation**
   - Keep ClusterIP plus port-forward as the current supported POC demo path.
   - Only revisit MetalLB if the subscription owner agrees to register `Microsoft.KubernetesRuntime`.

3. **AKS node-pool scale**
   - Re-measure physical host memory and storage health first.
   - Do not test node-pool scale while the node 01 maintenance condition remains open unless the scope is explicitly
     changed and capacity is reviewed.

## Next-sprint extension

The capstone learning environment, custom dashboard image, and pipeline evidence integration are planned next-sprint work. They should consume the completed POC evidence in this audit, not be used to redefine whether the original POC requirements are complete.

## Requirement recovery gap

This audit covers only the recovered criteria supplied on 2026-08-19 and the requirements found in this repository.
If the original project had a work-item hierarchy, charter, customer commitment, or leadership deliverable outside
the repository, those requirements must be added before declaring full project closure. The appropriate next step is
to append them to the acceptance criteria baseline and classify them using the categories above.

## Explicit non-requirements unless re-promoted

- Production HA, DR, performance, or capacity certification.
- Kubernetes external ingress before the provider-registration decision changes.
- Direct Docker installation on Azure Local hosts.
- Terraform management of cluster foundation, storage, networking fabric, AD, or existing manually created VMs.
- Unbounded workload load test or stress test while storage maintenance remains open.

## Related records

- [Original POC Acceptance Criteria](original-poc-acceptance-criteria.md)
- [Kubernetes and Terraform integration test results](kubernetes-terraform-integration-test-results.md)
- [External dependencies and POC lessons](external-dependencies-and-poc-lessons.md)

