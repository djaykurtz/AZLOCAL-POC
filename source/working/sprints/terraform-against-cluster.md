---
title: "Sprint S6 - Test Terraform provisioning against cluster resources"
domain: [iac]
layer: [cluster]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [sprint, terraform, azapi, sprint-s6]
updated: 2026-08-19
---

# Sprint S6 - Test Terraform provisioning against cluster resources

Sprint S6 (PoC Validation Part 2). Status: complete - human-operated lifecycle proven; pipeline identity and remote state deferred.
Cluster: AZL-CLUSTER-01. Custom location: azl-cluster-01-cl.

## Objective

Prove Terraform can provision Azure Local resources (Arc VM, logical network, and/or AKS Arc) against the
POC cluster. Terraform is a POC tooling target, not the primary deployment path (Bicep remains primary per
ADR 0005). Stay plan-only until a small apply is explicitly promoted.

## Capstone baseline - 2026-08-18

The earlier manually created tenant demo VMs are not Terraform targets:

- `ws2025-core-01` was stopped on 2026-08-18.
- `rocky-docker-01` was already stopped and remains stopped.
- Their gallery images, Azure Local logical network, AKS Arc cluster, and Kubernetes Lab workload remain as
  reusable platform evidence.

Terraform must not import, modify, or destroy either manual demo VM. The first promoted Terraform apply must
create one new, explicitly Terraform-owned disposable VM and then destroy only that same VM. This gives the
capstone a clean ownership boundary without discarding proven Azure Local platform evidence.

## Source-only CI first

The initial workflow at `.github/workflows/validate.yml` is intentionally credential-free. It runs Terraform
formatting, backend-free initialization, validation, and a non-mutating provider-free plan; client-side
Kubernetes manifest validation; and PowerShell syntax parsing. It does not authenticate to Azure, push an image,
deploy to AKS, create state, or run `terraform apply`.

This layer is the first CI/CD proof. Add OIDC, a remote Terraform state design, a registry, and deployment
permissions only after the provider feasibility module and exact Terraform-owned Azure Local resource contract
are reviewed.

## Prerequisites

- Terraform CLI on the DevBox (starter module today is provider-free and validates shape; the real test
  needs the azapi and/or azurerm provider).
- az login context with the POC sub/RG and PIM active.
- The same custom-location id and logical-network inputs used by S1.

## Provider approach

- Azure Local Arc VM and AKS Arc resources are Azure Resource Manager resources under
  Microsoft.AzureStackHCI, HybridContainerService, and ExtendedLocation.
- The Azure Local VM provisioning resource is **not** a top-level ARM resource. It is
  `Microsoft.AzureStackHCI/virtualMachineInstances`, fixed name `default`, scoped as an extension resource
  beneath the new `Microsoft.HybridCompute/machines/<vm-name>` parent. The parent is the Arc machine identity;
  the extension resource contains the VM hardware, storage, network, and guest configuration.
- A generic top-level `az resource show` for `Microsoft.AzureStackHCI/virtualMachineInstances` therefore fails
  even though the resource type exists. This was confirmed read-only on 2026-08-18. Do not treat that failure as
  an Azure RBAC denial.
- Microsoft documents both an ARM/Bicep contract and an Azure Verified Terraform module for this resource.
  Prefer the Azure Verified Module first. Use direct `azapi_resource` only if the module cannot represent the
  exact cluster contract after a plan-only test.

Official source: [Create Azure Local Virtual Machines enabled by Azure Arc](https://learn.microsoft.com/en-us/azure/azure-local/manage/create-arc-virtual-machines).

Provider feasibility result, 2026-08-18:

- Module `Azure/avm-res-azurestackhci-virtualmachineinstance/azurerm` initialized successfully in a temporary,
  backend-free local test with no Azure authentication.
- Terraform resolved `hashicorp/azurerm v4.81.0`, `azure/azapi v2.12.0`, `azure/modtm v0.4.0`, and
  `hashicorp/random v3.9.0`.
- This proves the supported module dependency chain is reachable. It does not prove that a live plan has the
  correct Azure Local input IDs, RBAC, state backend, or capacity.

## Permission preflight - Terraform capstone

| Capability | Narrowest expected role or action | Scope | Current position | External decision needed? |
| --- | --- | --- | --- | --- |
| Local Terraform format, validate, provider-free plan | None | Local DevBox | Complete. Terraform 1.15.8 installed. | No. |
| Interactive Terraform plan of the disposable VM module | Azure Stack HCI Administrator | Subscription or POC RG containing the custom location and VM resources | Active PIM role already proven for Azure Local VM operations. | No new request expected. |
| Create/delete the Terraform-owned VM and its NIC | Azure Stack HCI VM Contributor | POC RG | A narrower future pipeline role; Azure Stack HCI Administrator is sufficient for the human POC operator. | No new request expected if current RG UAA can assign the role to the pipeline identity. |
| Create shared VM resources such as logical networks, images, or storage paths | Azure Stack HCI Administrator | POC RG or subscription | Existing POC role covers this, but first capstone module should reference existing shared resources and avoid this action. | No. |
| Create Entra application and service principal for GitHub OIDC | Microsoft Entra application registration and service-principal creation permission | Entra tenant | Not yet verified for this user. | Potential external gate. Verify before requesting. |
| Add GitHub OIDC federated credential | Permission to update the Entra application federated identity credentials | Entra tenant | Not yet verified. | Potential external gate. Include in the same request as app registration if needed. |
| Assign pipeline identity Azure Stack HCI VM Contributor | User Access Administrator or Owner | POC RG | RG-scoped UAA is active and previously used for POC role assignment. | No new request expected. |
| Create secure Terraform state storage account | Storage Account Contributor | POC RG | Deployment-era role was self-assigned; verify it remains active or assign it to the pipeline identity later. | No new request expected. |
| Read/write Terraform state blobs | Storage Blob Data Contributor | State storage account or POC RG | Not yet assigned to a future pipeline identity. | No external request expected if RG UAA can assign it. |
| Protect the GitHub apply environment | GitHub repository administration | GitHub repository | Repository owner control. | No Azure request. |

Microsoft states that Azure Stack HCI Administrator has full access to Azure Local VM resources and can create
shared logical networks, VM images, and storage paths. Azure Stack HCI VM Contributor can create/delete VMs and
their attached resources but cannot create those shared resources. [Source](https://learn.microsoft.com/en-us/azure/azure-local/manage/assign-vm-rbac-roles)

## Procedure

1. Static layer (no CLI apply): terraform fmt + validate on the starter module and a new azapi module that
   declares a custom-location data source + a logical network + a small Arc VM.
   Result: config is well-formed; variables for the 4-node vs 6-node shapes validate.
2. Plan-only layer: terraform init (download azapi/azurerm) + terraform plan against the real sub/RG.
   Result: a plan that shows the intended create with no apply.
3. Promoted apply (explicit decision only): terraform apply a single throwaway resource (a logical network
   or a small Arc VM using the path-B image), then terraform destroy.
   Result: create + destroy round-trip proves the Terraform path end-to-end.
4. Drift check: terraform plan after apply shows no unexpected diff.

## Executed lifecycle result - 2026-08-19

The isolated test executed with the existing human PIM role and created only the intended resources:

```text
Microsoft.HybridCompute/machines/tf-poc-linux-01
Microsoft.AzureStackHCI/networkInterfaces/tf-poc-linux-01-nic
Microsoft.AzureStackHCI/virtualMachineInstances/default
```

- The clustered VM was `Online` on `AZL-NODE-04`; Hyper-V reported `Running` and `Operating normally`.
- The Azure Local VM ARM extension stayed `Accepted` without an error after the Hyper-V runtime succeeded. Terraform
  had to be interrupted after its wait loop, then the already-created extension was imported into local state.
- The post-import plan proposed an in-place update because the live resource reported a newer Azure Local API
  version and the generated write-only administrator password differed from the apply input. No such update was applied.
- Terraform destroy removed the VM extension and Arc machine parent. The residual NIC deletion initially failed
  because PIM had expired; after reactivation and Azure Local provider propagation, the NIC was deleted.
- Final `terraform plan -destroy` reported no objects to destroy. The only remaining state address is the read-only
  resource-group data source.

This proves the human-operated create and cleanup path. The ARM `Accepted` reporting lag and PIM-expiry cleanup
behavior are required design inputs for the later CI/CD pipeline, not reasons to treat the lifecycle as cleanly
automated yet.

## Closure statement

S6 is complete for the POC scope. Terraform successfully planned, created, verified, reconciled state for, and
cleaned up a disposable Azure Local VM without touching cluster foundation, AKS, gallery images, logical networks,
or manually created demonstration VMs.

Deferred follow-on work:

- Remote state with locking.
- GitHub OIDC pipeline identity and protected apply/destroy environment.
- Pipeline-grade handling of Azure Local ARM `Accepted` completion lag.
- Automated preflight that checks PIM activation before cleanup actions.

## Success criteria

- fmt + validate + init + plan all succeed against the cluster resources.
- If promoted: a single resource applies and destroys cleanly with no leftover.

The next execution step requires no new external permission: create the module with existing resource IDs as
inputs, authenticate as the human POC operator with active Azure Stack HCI Administrator, and run a speculative
plan. Stop and record the first denial or schema mismatch. Do not design OIDC or request an Entra application
until that human plan demonstrates the exact Azure actions the pipeline would need.

First live-plan finding, 2026-08-18: AzureRM attempted to auto-register the unrelated
`Microsoft.Cache` resource provider and was denied `Microsoft.Cache/register/action` at subscription scope.
This is a provider default, not an Azure Local VM dependency. The wrapper explicitly sets
`resource_provider_registrations = "none"` so subsequent plans do not create provider-registration pressure.

Second live-plan result, 2026-08-18: with provider auto-registration disabled, a human-authenticated
speculative plan succeeded using the existing POC custom location, `ubuntu-2404` gallery image, and tenant
logical network. The plan contains exactly three creates and no changes or destroys:

```text
module.disposable_vm.azapi_resource.hybrid_compute_machine
module.disposable_vm.azapi_resource.nic
module.disposable_vm.azapi_resource.virtual_machine

Plan: 3 to add, 0 to change, 0 to destroy.
```

This proves the current human PIM role can plan the isolated VM without a new Azure permission request. The
first future external decision remains Entra application registration and OIDC federation for a pipeline identity,
not Azure Local VM RBAC.

Apply preflight result, 2026-08-18: **degraded-state risk accepted for the small Terraform VM test**.

- All four cluster nodes were `Up` and `SU1_Pool` was `Healthy` / `OK`.
- `UserStorage_2` reported `Warning` / `Incomplete`.
- The `UserStorage_2-Repair` storage job was `Suspended` at `0%`.
- Twelve physical disks reported `Healthy` / `OK`; one reported `Warning` / `Lost Communication`.
- Historical storage events included surprise removal and bad-block evidence.

This is an Azure Local maintenance condition, not a Terraform or permission issue. Three-way mirror and the
remaining data disks keep the pool operational, and the POC has ample capacity for the deliberately small
Terraform VM. Do not change storage configuration or use the Terraform test as a storage stress exercise. Record
the condition, keep the workload small and reversible, and monitor storage health during the test.

Detailed evidence and the non-destructive recovery ladder: [Node 01 retired NVMe recovery](../../docs/runbooks/node01-retired-nvme-recovery.md).

## Temporary workaround mode - storage-degraded POC

Until the node 01 NVMe controller path and `UserStorage_2` recovery are addressed, operate the POC in a
degraded-but-available maintenance posture:

| Allowed now | Deferred until storage health is green |
| --- | --- |
| Terraform format, init, validate, plan, small VM apply, drift check, and destroy | High-write workload, large VM, or repeated stress testing |
| GitHub Actions source-only validation | Remote Terraform state or pipeline Azure deployment identity |
| Terraform module and documentation development | Creating a shared logical network, image, or disk |
| Existing small Kubernetes Lab operations and read-only dashboard work | AKS worker-node scale or workload stress test |
| Local `kubectl port-forward` demonstrations | Any storage repair, disk removal, or forced repair-job action |

This is a deliberate POC workaround, not a claim that the storage condition is resolved. Preserve and monitor the
small Terraform workload only. Regenerate the plan immediately before apply and stop if pool, virtual-disk, or
node health materially worsens.

## Evidence

- out/_terraform-plan-*.txt.
- Reuse scripts/Invoke-TerraformPlanOnly.ps1 and scripts/Invoke-LocalValidation.ps1 for the static/plan layers.

## Risks / notes

- Never terraform apply against shared cluster infra without an explicit decision (ADR 0005). Default is
  plan-only.
- azapi api-versions must match what the deployed RP supports; pull the type/version from the Bicep in
  infra/ or from az resource show on an existing resource.

