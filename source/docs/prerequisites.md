---
title: "Prerequisites From Other Roles"
domain: [platform, identity, network, security]
layer: [hardware, os, arc]
type: reference
status: current
proof: documented
audience: [engineer, operator]
tags: [prerequisites, dependencies, active-directory, network, rbac, datacenter]
updated: 2026-09-15
---

# Prerequisites From Other Roles

The platform owner could not stand up this cluster alone. This page lists, by role, what the
platform owner needed from other roles before and during deployment. It replaces the individual
request documents that were written during the project.

Every item below was a hard gate at some point. Most of the elapsed time of the proof of concept
went into waiting for these, not into the engineering work.

## Directory role (Active Directory)

- **A dedicated OU** for the cluster (for example `OU=AzureLocal,...`), with **GPO inheritance
  blocked**. Enforced parent GPOs still apply, so they need a review for deny-logon rights, service
  disablement, WinRM or firewall lockdown, TLS hardening, forced Credential Guard/VBS, and LAPS.
- **A deployment (LCM) account** that is a standing member of any delegation group. Azure Local uses
  it unattended for lifecycle operations, so it cannot rely on just-in-time activation.
- **Direct ACEs for the deployment account on the OU.** The Azure Local validator checks ACEs on the
  account's own SID. It does not check group membership. The required rights are:
  - Create Child and Delete Child on the `computer` class (schema GUID
    `bf967a86-0de6-11d0-a285-00aa003049e2`)
  - Read Property on the OU
  - Generic All on descendant `msFVE-RecoveryInformation` objects (schema GUID
    `ea715d30-8f53-40d0-bd1e-6109186d782c`), which hold the BitLocker recovery keys
- **User rights on the nodes:** "Allow log on locally" and "Log on as a batch job" for the deployment
  account. These are user rights on the cluster nodes, applied by GPO. They are not attributes of
  the account.
- An alternative to manual delegation is the public `AsHciADArtifactsPreCreationTool` module, which
  pre-creates the OU and delegation.
- The OU must not be deleted after deployment, because it stores the BitLocker recovery keys.

See [accounts and dependencies](active-directory/accounts-and-dependencies.md) and
[deployment identity decisions](decisions/README.md).

## Network role

- A management subnet with a gateway and DNS servers, plus **static IPs** for every node, the cluster
  name, and the Arc resource bridge range.
- A **firewall allowlist** for the regional Azure Local endpoint list published on Microsoft Learn,
  with **no TLS inspection** on those endpoints.
- **Storage VLANs** (711 and 712 in this build) trunked to the storage ports, with LACP and the native
  VLAN removed from those ports.
- Switch-side confirmation of the port configuration when east-west storage traffic fails.

## Cloud governance role (Azure)

- Through PIM: **Azure Stack HCI Administrator**, **User Access Administrator** at resource group
  scope, and the Key Vault, Storage, and Arc onboarding roles that the deployment wizard needs.
- **Resource provider registration** on the subscription, including
  `Microsoft.AzureStackHCI`, `Microsoft.HybridContainerService`, `Microsoft.ResourceConnector`,
  `Microsoft.ExtendedLocation`, `Microsoft.KubernetesRuntime`, and `Microsoft.EdgeMarketplace`
  (for Marketplace VM images).
- The organization's tag schema and any cost-center values.
- A scoped exception for any policy-deployed monitoring agent that contends for the single
  monitoring-agent slot on the nodes (see
  [security posture and boundaries](access/security-posture-and-boundaries.md)).

## Datacenter technician role

- BIOS configuration (virtualization, storage controller mode, Secure Boot) per
  [the BIOS ideal state](storage-imaging/bios-ideal-state.md).
- OS imaging from USB media, the first local administrator password, and the first network
  configuration per [the reimage checklist](storage-imaging/reimage-checklist.md).
- Cabling for the storage NICs, KVM patching for each node, and physical card or drive swaps.
