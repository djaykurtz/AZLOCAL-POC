---
title: "PIM elevation routine"
domain: [identity]
layer: [arc]
type: runbook
depth: quickref
status: current
proof: proven
audience: [engineer, operator]
tags: [pim, rbac, elevation, key-vault, azure-stack-hci-administrator, user-access-administrator]
updated: 2026-08-26
---

# PIM elevation routine

Run this at the start of any working session that touches Azure. The POC roles are PIM-eligible, not
standing, so nothing Azure-side works until they are activated.

## Commands

```powershell
# Check whether today's roles are already active
.\scripts\Invoke-PocPimElevation.ps1 -Status

# Activate for 8 hours
.\scripts\Invoke-PocPimElevation.ps1

# Activate with an explicit justification
.\scripts\Invoke-PocPimElevation.ps1 -Reason 'POC day work 26-Aug'
```

## What it activates

| Role | Scope |
| --- | --- |
| Azure Stack HCI Administrator | Subscription `contoso-lab-sub` |
| User Access Administrator | Resource group `rg-azlocal-poc-001` |

Contributor is deliberately not in the list. It is a standing permanent assignment on the POC
subscription, so attempting to self-activate it always fails with "No eligible roles matched".

Activating User Access Administrator is what makes the resource-group Key Vault, storage, and Arc
roles usable, including Key Vault Secrets Officer on `azl-cluster-01-kv`.

## Known behavior

**Wait two to three minutes before Azure Local writes.** The `Microsoft.AzureStackHCI` resource
provider lags behind activation. Immediately after elevating, VM create and delete calls can fail with
a transient `AuthorizationFailed` that reads "if access was recently granted, please refresh your
credentials". The role really is active and a token refresh does not help. Wait, then retry one
resource at a time.

**Expiry surfaces as an authorization error.** The window is 8 hours. When it lapses, the first
symptom is usually `AuthorizationFailed` on a `galleryImages/write` or similar call rather than
anything that mentions PIM. Re-run the routine before assuming a permissions problem.

## Related

- [Azure permissions and capability register](../access/azure-permissions-and-capability-register.md)
- [Credential map](../access/credential-map.md)
