---
title: "Credential map"
domain: [identity, security]
layer: []
type: reference
depth: quickref
status: current
proof: proven
audience: [engineer, operator]
tags: [credentials, key-vault, dpapi, recovery, disaster-recovery]
updated: 2026-08-26
---

# Credential map

Where every Azure Local POC credential lives, what it is for, and whether it still works.

This file contains **no secret values**. It is a pointer index. It exists because the working
credentials were only ever stored as DPAPI blobs on a single machine, and that is a single point
of failure.

Last verified: 2026-08-26

## The two storage layers

| Layer | What it is | Durability |
| --- | --- | --- |
| `.creds\*.cred` | DPAPI SecureString, encrypted to **one user on one machine** | Lost permanently if this DevBox is reimaged. Gitignored. |
| `azl-cluster-01-kv` | Azure Key Vault, resource group `rg-azlocal-poc-001` | Durable. Survives machine loss. Soft delete enabled. |

Reading a Key Vault secret needs an active **Key Vault Secrets Officer** or **Key Vault Secrets User**
role. Run `scripts\Invoke-PocPimElevation.ps1` first, then allow two to three minutes for RBAC
propagation.

## Credentials

| Account | Purpose | Key Vault secret | Local file | Status |
| --- | --- | --- | --- | --- |
| `sim\labadmin` | Domain admin. **The working way to reach the nodes over WinRM.** | `poc-cred-sim-domain-admin` | `sim-example-internal-admin.cred` | Working |
| `sim\AZLCL-DEPLOY-ADM` | Azure Local deployment and lifecycle account | `poc-cred-sim-lcm` | `sim-azlcl-deploy-adm.cred` | Active for deployment. Denied for general remote admin. |
| `<node>\Administrator` | Node local administrator, pre-deployment | `poc-cred-node-local-admin-predeploy` | `azloc-local-admin.cred` | **Stale.** Deployment rotated this and now manages it. |
| `CORP\AZLCL-DEPLOY-ADM` | Original corporate AD deployment account | `poc-cred-corp-lcm-superseded` | `azlcl-deploy-adm.cred` | Superseded by the `sim.example.internal` pivot. History only. |
| `azureuser` | SSH private key for Linux Azure Local VMs | `poc-ssh-vm-key` | `poc-vm-key` | Working, no passphrase |

## Deployment-managed secrets

These two were created by the deployment wizard and are managed by lifecycle management. Do not
overwrite them by hand.

| Secret | Holds |
| --- | --- |
| `AZL-CLUSTER-01-AzureStackLCMUserCredential-00000000-...` | base64 of `AZLCL-DEPLOY-ADM:<password>` |
| `AZL-CLUSTER-01-LocalAdminCredential-00000000-...` | Node local administrator |

The value must be written **without a byte order mark**. PowerShell `[Text.Encoding]::UTF8` adds one,
and lifecycle management then rejects the secret with "invalid object was returned from key vault".
Use `[Text.Encoding]::ASCII`.

## Known access gap

`kv-lab-secrets` in resource group `rg-other-01` returns `ForbiddenByRbac` with
`Assignment: (not found)`. Several older documents point at it for `sim-lcm-azlcl-deploy-adm`,
`sim-example-internal-admin`, and `poc-vm-admin`. Those references cannot currently be resolved, and whether
the secrets still exist there is unconfirmed. The POC PIM roles are scoped to
`rg-azlocal-poc-001`, which does not reach that vault.

This is not blocking. Every credential listed above now has a copy in `azl-cluster-01-kv`.

## Recovering a credential

```powershell
.\scripts\Invoke-PocPimElevation.ps1
az keyvault secret show --vault-name azl-cluster-01-kv --name poc-cred-sim-domain-admin --query value -o tsv
```

Connecting to a node, which is the most common need:

```powershell
$pw   = ConvertTo-SecureString (Get-Content .creds\sim-example-internal-admin.cred -Raw).Trim()
$cred = New-Object PSCredential('sim\labadmin', $pw)
Enter-PSSession -ComputerName azl-node-01.lab.example.com -Credential $cred -Authentication Negotiate
```

Use the `lab.example.com` name, not `sim.example.internal`. The DevBox resolver has no forwarder for the sim zone,
and `lab.example.com` is what the TrustedHosts entry matches.

## Refreshing the backup

`scripts\Backup-PocCredentialsToKeyVault.ps1` re-reads the local files and writes them to the vault.
It is additive and safe to re-run. Run it after any credential rotation.

