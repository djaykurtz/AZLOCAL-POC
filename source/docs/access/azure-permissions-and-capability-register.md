---
title: "Azure permissions and capability register"
domain: [identity]
layer: [arc]
type: reference
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [rbac, pim, permissions, capability-register, resource-providers]
updated: 2026-08-20
---

# Azure permissions and capability register

## Purpose

This is the living authorization register for `AZL-CLUSTER-01`. It exists because a POC can succeed at one task and still stop at the next unregistered provider, resource-provider action, role assignment, or policy boundary.

For every normal operation, record both:

- **least privilege**: the narrowest known role or action that should perform it.
- **practical maximum**: the broadest role that is reasonable for that operation and scope, without defaulting to permanent subscription Owner.

The practical maximum is a planning ceiling, not a recommendation to grant it. Use PIM eligibility, the narrowest scope, and a short activation window whenever available.

## How to maintain this register

When any Azure command is denied, add a row before attempting workarounds:

1. Copy the exact denied action, scope, and date from Azure.
2. State the operation being attempted and whether it remains in POC scope.
3. Record the least-privileged path and practical maximum.
4. Mark whether the permission is active, PIM-eligible, externally owned, or intentionally not requested.
5. Link the runbook, script, decision, or external dependency that established the finding.

Do not treat a temporary `AuthorizationFailed` immediately after PIM activation as a new role gap. The Azure Local resource provider has demonstrated a 2-3 minute propagation delay in this POC. Retry one narrow operation after that delay before adding a denial row.

## Normal POC operations

| Capability | Least-privilege route | Practical maximum for the operation | Scope | Current POC position | Preflight evidence |
| --- | --- | --- | --- | --- | --- |
| Deploy and operate Azure Local resources, Arc VMs, gallery images, NICs, and logical networks | Azure Stack HCI Administrator | Azure Stack HCI Administrator plus RG User Access Administrator only when role assignment is needed | Azure Stack HCI Administrator at subscription; UAA at POC RG | Active through eight-hour PIM routine | `scripts/Invoke-PocPimElevation.ps1`; [VM runbook](../runbooks/custom-vm-image-and-test-runbook.md) |
| Assign the Azure Local deployment support roles at the POC RG | User Access Administrator | User Access Administrator, not Owner | POC RG | Active through PIM | [Prerequisites](../prerequisites.md) |
| Azure Local initial deployment support roles | Azure Stack HCI Administrator, plus Key Vault Data Access Administrator, Key Vault Secrets Officer, Key Vault Contributor, Storage Account Contributor, Azure Connected Machine Onboarding, and Azure Connected Machine Resource Administrator | The documented deployment-role set plus RG User Access Administrator for self-assignment | Azure Stack HCI Administrator at subscription; support roles at POC RG | Established during cluster deployment | Microsoft Learn: "The deployment user must be assigned the following roles." [Source](https://learn.microsoft.com/en-us/azure/azure-local/deploy/deployment-arc-register-server-permissions) |
| Create or administer AKS Arc cluster resources | Azure Kubernetes Service Arc Contributor Role | Contributor at the POC RG only if the built-in AKS Arc role is insufficient for a later supported operation | POC RG | Role assignment resolved AKS creation denial | [AKS work plan](../../working/plans/aks-and-scale-work-plan.md) |
| Read AKS cluster state through Kubernetes | AKS Arc Cluster User Role for user credentials, or AKS Arc Cluster Admin Role only for isolated administration | AKS Arc Cluster Admin Role | AKS Arc cluster resource | Admin kubeconfig used only for POC administration | Keep the admin kubeconfig out of source control and application pods. |
| Deploy or update the Azure Monitor Workbook | Workbook Contributor or Monitoring Contributor | Contributor at POC RG | POC RG | Requires a distinct role path from Azure Local VM operations | `scripts/Deploy-FunderDashboard.ps1` |
| Import Azure Local Marketplace images | `Microsoft.EdgeMarketplace/register/action` once, then Azure Local image permissions | Subscription Owner or custom role containing only the provider registration action for registration; Azure Stack HCI Administrator for image work | Provider registration at subscription; image resources at POC RG | `Microsoft.EdgeMarketplace` registered after external engagement | [Prerequisites](../prerequisites.md) |
| Register a resource provider | `<provider>/register/action` | Subscription Owner, or a custom subscription role containing the exact `register/action` | Subscription | Evaluate provider by provider before planning dependent capability | Provider registration cannot be granted from an RG-scoped role. |
| Configure MetalLB and a Kubernetes LoadBalancer VIP | `Microsoft.KubernetesRuntime/register/action` first, then AKS runtime extension permissions | Subscription Owner or custom role containing the KubernetesRuntime registration action | Provider registration at subscription; extension and pool at POC scope | Not available. Registration attempt denied 2026-08-18; intentionally not escalated. | [External dependency record](../planning/external-dependencies-and-poc-lessons.md) |
| Read Azure Local inventory from the dashboard | Reader | Reader only. Do not use Contributor, UAA, Azure Stack HCI Administrator, or a human PIM session. | POC RG | Pending dedicated runtime identity | [Dashboard plan](../planning/kubernetes-self-referential-dashboard.md) |
| Access or update Key Vault secrets for deployment automation | Key Vault Secrets Officer for secret data, Key Vault Contributor for vault management, and Key Vault Data Access Administrator only for RBAC delegation | Those three scoped roles. Do not use Owner for normal secret operations. | POC RG or vault resource | Used during deployment; keep runtime dashboard identity excluded | Azure Local deployment role record above. |
| Azure Arc onboarding and Arc resource administration | Azure Connected Machine Onboarding and Azure Connected Machine Resource Administrator | Azure Connected Machine Resource Administrator | POC RG | Established for deployment | Azure Local deployment role record above. |
| Terraform interactive plan for one Azure Local VM | Azure Stack HCI Administrator | Azure Stack HCI Administrator | POC RG or subscription containing the Azure Local custom location | Existing PIM role is sufficient for human plan and VM operations | Azure Local VM [built-in RBAC roles](https://learn.microsoft.com/en-us/azure/azure-local/manage/assign-vm-rbac-roles) |
| Terraform pipeline creates/destroys only its VM and NIC | Azure Stack HCI VM Contributor | Azure Stack HCI VM Contributor | POC RG | Future pipeline identity only. No shared logical network, image, or storage path creation. | Azure Local VM built-in RBAC roles source above. |
| Terraform pipeline remote-state data plane | Storage Blob Data Contributor | Storage Blob Data Contributor | Dedicated state storage account | Not yet assigned because the pipeline identity does not exist. | State must be remote, access-controlled, and locked. |
| Create GitHub OIDC Entra identity | Entra application registration and federated credential write permission | Entra tenant | Not verified for current user | Potential external gate. Verify before requesting; combine application and federated credential actions in one request if needed. | [GitHub OIDC for Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure) |

## Confirmed denials and resolved gaps

| Date | Operation | Exact missing action or gap | Outcome | Follow-up |
| --- | --- | --- | --- | --- |
| Before Marketplace image import | Register Edge Marketplace provider | `Microsoft.EdgeMarketplace/register/action` at subscription | Resolved through external registration. Azure Edition images subsequently imported. | Add every new provider to preflight before relying on it. |
| 2026-08-14 | Create AKS Arc cluster | Missing AKS Arc creation role at POC RG | Resolved by Azure Kubernetes Service Arc Contributor Role assignment. | Retain this row as proof that Azure Local roles do not automatically cover AKS Arc. |
| 2026-08-18 | Register Kubernetes runtime provider for MetalLB | `Microsoft.KubernetesRuntime/register/action` at subscription | Denied. No external request will be made for this POC. | Keep dashboard on ClusterIP and use temporary port-forward. |
| Repeated after PIM activation | Create or delete Azure Local VM resources | Transient `AuthorizationFailed` despite active roles | Not a role gap. Operations succeeded after 2-3 minutes. | Treat as propagation delay and retry one operation once. |
| 2026-08-18 | Read Azure Local VM as top-level ARM resource | `Microsoft.AzureStackHCI/virtualMachineInstances` returned `InvalidResourceType` in global scope | Not a role gap. The VM instance is an extension resource named `default` under its `Microsoft.HybridCompute/machines/<vm-name>` parent. | Use the Azure Verified Terraform module or parent-scoped azapi contract. |
| 2026-08-18 | Initialize Azure Verified Terraform Module | No denied Azure action; backend-free module initialization succeeded | Supported module `Azure/avm-res-azurestackhci-virtualmachineinstance/azurerm` resolved AzureRM, AzAPI, Random, and ModTM providers locally. | Next gate is a human-authenticated speculative plan with current POC resource IDs. |
| 2026-08-18 | Human-authenticated Terraform plan for `tf-poc-linux-01` | No Azure Local RBAC denial after disabling AzureRM provider auto-registration | Plan proposed only Terraform-owned Arc machine, NIC, and VM extension: `3 to add, 0 to change, 0 to destroy`. | No new Azure VM permission request. Next potential external gate is Entra application and OIDC federation for pipeline identity. |
| 2026-08-18 | Terraform apply preflight | No authorization failure; cluster storage health was unsafe for a new workload | `UserStorage_2` was `Warning` / `Incomplete` with a suspended repair job and one physical disk in `Lost Communication`. | Apply deferred until storage recovery and a fresh health baseline pass. |
| 2026-08-18 | First live Terraform plan | AzureRM attempted `Microsoft.Cache/register/action` automatically and received 403 | Not an Azure Local VM requirement. The module now sets `resource_provider_registrations = "none"` so Terraform cannot auto-register unrelated providers. | Rerun the same plan and record only the next Azure Local, schema, or RBAC gate. |

## Scope rules

- Resource-group roles cannot grant a subscription provider-registration action.
- Contributor includes general resource CRUD but does not provide Microsoft.Authorization role assignment management.
- User Access Administrator is for role assignments. It is not a substitute for service-specific resource permissions.
- Owner is not a standard POC operating role. Use it only when the accountable subscription owner chooses to perform a subscription-wide operation.
- A dashboard or CI/CD runtime identity must be independent of human PIM sessions and limited to its exact read or deployment scope.

## Current verification gap

Older documentation differs on whether Contributor is permanent or PIM-eligible for this identity. Do not rely on either statement without checking the live PIM eligibility and active assignments before using Contributor as a workaround. The standard daily routine deliberately activates only Azure Stack HCI Administrator and RG-scoped User Access Administrator because those two have proven sufficient for normal Azure Local VM operations.

## Related records

- [External dependencies and POC lessons](../planning/external-dependencies-and-poc-lessons.md)
- [AKS on Azure Local and scale demonstration work plan](../../working/plans/aks-and-scale-work-plan.md)
- [Azure Local resource migration and deletion protocol](../runbooks/resource-migration-deletion-protocol.md)
- [PIM elevation routine](../../scripts/Invoke-PocPimElevation.ps1)

