---
title: "Azure Local POC external dependencies and lessons"
domain: [platform]
layer: []
type: postmortem
status: current
proof: proven
audience: [leadership, engineer]
tags: [lessons-learned, external-dependencies, blockers, retrospective]
updated: 2026-08-18
---

# Azure Local POC external dependencies and lessons

## Purpose

`AZL-CLUSTER-01` is a functional proof of concept, including a four-node Azure Local cluster, tenant VMs, AKS Arc, and a Kubernetes dashboard. It also exposed dependencies that one engineering team cannot solve alone.

This document records those dependencies so a future Azure Local POC can request the right involvement before hardware work, deployment, or workload expansion begins. A completed cluster does not mean every optional platform capability is available.

For the complementary role, action, scope, and status ledger, see the
[Azure permissions and capability register](../access/azure-permissions-and-capability-register.md).

## Current limitation: AKS LoadBalancer VIP

The dashboard runs successfully behind a Kubernetes `ClusterIP` Service and has passed an HTTP check through a local `kubectl port-forward`. It cannot currently receive a management-subnet LoadBalancer VIP.

The required provider is not registered:

```text
Microsoft.KubernetesRuntime: NotRegistered
```

On 2026-08-18, an attempted registration returned:

```text
AuthorizationFailed: The client does not have authorization to perform action
'Microsoft.KubernetesRuntime/register/action' over scope
'/subscriptions/00000000-0000-0000-0000-000000000001'.
```

This action is subscription-scoped. The POC's Azure Stack HCI Administrator role at subscription scope and User Access Administrator role at resource-group scope do not include it. Resource-group role assignment cannot provide a subscription provider-registration action.

### POC decision

Do not request additional external permission for this POC. Keep the dashboard on `ClusterIP` and use an explicit, temporary `kubectl port-forward` when a local demonstration is needed.

MetalLB, a `.221-.223` management-subnet VIP pool, and a Kubernetes `LoadBalancer` Service remain documented but out of the current executable scope. This is a valid POC boundary, not a cluster failure.

## Third-party engagement preflight

Engage the named owners before beginning the affected phase. Treat every row marked **hard gate** as a written go/no-go check.

| Dependency | Why it matters | Owner type | Evidence from this POC | Required before | Gate |
| --- | --- | --- | --- | --- | --- |
| Subscription resource-provider registration | Azure services can require a provider to be registered before resource creation or extension installation. | Subscription Owner or a custom subscription role with the provider's `register/action`. | `Microsoft.EdgeMarketplace` needed registration before Azure Local-compatible Marketplace image import. `Microsoft.KubernetesRuntime` registration was denied on 2026-08-18. | Marketplace image import, MetalLB, and any service that names an unregistered provider. | Hard gate for the affected capability. |
| Subscription and RG Azure RBAC | Azure Local deployment, Arc VM operations, Key Vault access, AKS Arc creation, and dashboard identity each have distinct permissions. | Subscription owner, RBAC administrator, or approved PIM owner. | AKS creation initially failed until AKS Arc roles were assigned. Workbook updates required Workbook Contributor because Contributor coverage was not available through the active PIM path. | Deployment and each new service workstream. | Hard gate. List the action, scope, identity, and duration before starting. |
| PIM eligibility and propagation | Eligible roles must be activated, and Azure resource providers can take minutes to honor them. | PIM/RBAC owner for eligibility; POC operator for activation. | Azure Stack HCI operations returned transient `AuthorizationFailed` immediately after activation, then succeeded after propagation. | Any time-limited privileged operation. | Operational gate. Activate before the change window and retry one narrow operation after propagation. |
| Active Directory domain, OU, and service account | Azure Local deployment needs a reachable domain, an OU, a deployment account, correct permissions, and compatible logon policy. | AD/domain administrators and identity/security owners. | Corporate AD policy and inherited deny-logon controls blocked the original path. The POC pivoted to `sim.example.internal`, where the OU, account, direct permissions, and GPO boundary could be created. | Azure Local deployment. | Hard gate. Prove with the Azure Local AD validator and a practical account operation. |
| Enforced Group Policy and security controls | Parent GPOs and endpoint security can override local configuration or block required Azure Local components. | Domain policy and security owners. | A pre-existing corporate security monitoring agent occupied the singleton monitoring-agent slot and blocked Azure Local observability. A scoped `SkipSecurityMonitoringAgent=true` opt-out and extension removal were required. | Azure Local deployment and post-deployment observability. | Hard gate when conflicting controls exist. Record the approved exception, scope, rollback, and validation. |
| Storage fabric configuration | Azure Local requires working, lossless east-west storage paths. This spans host NICs, cabling, switch configuration, and network policy. | Network/switch team plus rack or smart-hands team. | Storage validation exposed reversed adapter naming on three nodes and missing trunk mode on SW2. Tagged VLAN 711 and 712 tests passed only after adapter renaming and switch correction. | Azure Local deployment and any future cluster scale-out. | Hard gate. Validate the actual Azure Local network path, not only link state. |
| Management-subnet address reservation | Azure Local, tenant VMs, AKS nodes, API endpoint, and possible service VIPs need non-overlapping, documented addresses. | IPAM/DNS or network owner. | POC moved tenant VMs from an unreserved `.240-.243` range to the formally reserved `.208-.228` range. | Deployment, VM creation, AKS, and LoadBalancer planning. | Hard gate. Obtain a written allocation before creating network resources. |
| DNS, NTP, and egress | Nodes need name resolution, a valid external time source, and supported direct Azure egress. | DNS, NTP, firewall, and proxy owners. | Azure Local validation stopped when nodes reported `Local CMOS Clock`; it passed after all nodes used the lab DC as NTP. TLS inspection was explicitly ruled out by endpoint testing. | Deployment and Arc onboarding. | Hard gate. Validate from every node with the Azure Local tooling. |
| Hardware, firmware, drivers, and physical access | Unsupported hardware still needs coherent drivers, storage, Secure Boot, and physical remediation capability. | Hardware owner, OEM support, and smart-hands/rack access. | Dell Precision 7960 Rack hardware required a donor Mellanox card, OEM Broadcom driver, Secure Boot-clean image process, and repeated KVM work. | Imaging, host validation, and cluster deployment. | Hard gate. Run the full hardware validator and review every row before deployment. |
| Marketplace terms and supported image SKU | Provider registration alone does not make every Marketplace SKU compatible with Azure Local. | Subscription owner for registration; image/workload owner for selection. | Standard Windows Server 2025 SKUs were unsupported. Windows Server 2025 Datacenter: Azure Edition Core and Desktop succeeded. | Gallery image import. | Capability gate. Verify the exact URN against the Azure Local flow before committing to a guest OS plan. |
| AKS and Kubernetes runtime support | AKS Arc versions, worker OS choices, extension availability, and LoadBalancer implementation vary by custom location and provider state. | POC operator for discovery; subscription owner if provider registration is required. | The custom location supported Kubernetes `1.33.5` with Linux workers. The former managed load-balancer-count assumption was invalid; MetalLB is the supported VIP path. | AKS deployment and exposure planning. | Capability gate. Query supported versions and CLI validation before building the workload plan. |

## Recommended engagement sequence

1. Establish the intended POC outcomes: Azure Local only, Arc VMs, Docker VM, AKS, external Kubernetes VIP, or all of them.
2. For each outcome, inventory every Azure provider, RBAC action, network range, domain dependency, and third-party owner before creating resources.
3. Obtain written IP reservations and determine the required provider-registration actions at subscription scope.
4. Confirm PIM eligibility and activation duration for operators. Do not confuse active resource-group roles with subscription administration.
5. Validate AD, GPO, DNS, NTP, egress, hardware, drivers, and the real storage path before opening the deployment window.
6. Use the smallest supported workload first: a VM, then AKS with `ClusterIP`, then optional external VIP only after all its gates are green.
7. Preserve capability gaps as POC findings. Do not bypass them with standing administrator credentials, unreserved addresses, or unmanaged host changes.

## Lessons for future POC plans

- Treat Azure provider registration as a named preflight item for every Azure service and extension, not as an implementation detail.
- Request least privilege by action and scope. A broad-looking role name does not guarantee a separate subscription-level control-plane action.
- Use a `ClusterIP` workload as the initial AKS proof. It separates Kubernetes scheduling from the provider, IPAM, and MetalLB dependencies of external exposure.
- Make external dependencies visible in the initial project plan, including the owner and the last responsible decision date.
- Keep unsupported or unavailable features explicit. The POC remains successful when its working capabilities and its limits are both reproducible.

## Related records

- [AKS on Azure Local and scale demonstration work plan](../../working/plans/aks-and-scale-work-plan.md)
- [Kubernetes-hosted Azure Local status dashboard](kubernetes-self-referential-dashboard.md)
- [Azure Local POC accounts and service dependencies](../active-directory/accounts-and-dependencies.md)
- [Azure Local POC decisions](../decisions/README.md)

