---
title: "Security posture and boundaries"
domain: [identity, security, platform]
layer: [os, cluster]
type: reference
depth: full
status: current
proof: proven
audience: [engineer, leadership, security]
tags: [security-posture, boundaries, inherited-controls, residual-risk, threat-surface]
updated: 2026-08-31
---

# Security posture and boundaries

## Why this document is not a threat model

The original acceptance criteria asked for a threat model. This is not that, and the difference
is deliberate rather than an evasion.

A threat model is a structured exercise. It enumerates actors, assets, and attack paths, and it
is worth doing properly or not at all. Producing a shallow one that nobody can defend would be
worse than producing nothing, because it would create the appearance of analysis where there was
none.

What this document does instead is answer the question a security reviewer actually asks first.
Which controls are you relying on, who provides them, and what is left over?

That question has a clean and genuinely interesting answer, because Azure Local sits in an unusual
place. Half the security story is inherited from Azure and needs no defending. The other half is a
rack of machines in the lab, and Azure cannot see it at all.

That gap is the most useful security finding this POC produced.

## The three layers

```text
Layer 1  Azure control plane      inherited, not re-argued here
Layer 2  Platform defaults        applied by deployment, evidence below
Layer 3  The physical estate      neither of the above reaches it
```

Most security conversations about hybrid infrastructure blur these together. Keeping them apart
is what makes the residual risk visible.

## Layer 1. What Azure carries

Everything that reaches the control plane is protected by controls this project did not build,
cannot weaken, and does not need to re-justify.

- Entra ID authentication for every operator action against Azure resources
- PIM elevation with time bound role activation, currently eight hour windows
- RBAC scoped to the subscription and to resource group `rg-azlocal-poc-001`
- Conditional access as enforced by the tenant
- Arc agent identity for machine to control plane communication
- Key Vault RBAC governing access to `azl-cluster-01-kv`

The permission surface is already written down in full at
[Azure permissions and capability register](azure-permissions-and-capability-register.md), including
the requests that were denied and never escalated.

The important point for a reviewer is that no custom authentication was invented anywhere in this
project. Every path to a resource goes through Entra.

## Layer 2. What the platform switched on by itself

This is the part people underestimate. Azure Local applied a hardened baseline during deployment
without anyone configuring it by hand, and the deployment log recorded each step.

From [POC deployment summary](../POC-deployment-summary.md):

```text
0.24 Encrypt CSVs                Success   <- BitLocker on cluster volumes
0.25 Encrypt the OS volume       Success   <- BitLocker on OS
0.35 Apply security policies     Success (~6 min)
```

The security level chosen at deployment covers more than encryption. From the prerequisite
checklist notes:

> "Azure Local supports BitLocker, Credential Guard, WDAC, SMB signing/encryption."

BitLocker on both the OS volume and the cluster shared volumes is not a claim, it is two deployment
steps that returned Success. The same applies to the security policy application in Phase C.

Worth stating plainly, because it is the good news in this document: none of that was configured by
hand. It arrived with the deployment, and nobody had to remember to ask for it.

## Layer 3. What neither layer reaches

Here is the part that matters, and the part that has no cloud equivalent.

### Physical access

The machines live in the lab. A person standing in front of them does not encounter
PIM, conditional access, or RBAC. This is not hypothetical for this POC specifically, because the
nodes were imaged over KVM virtual media, which means booting arbitrary media at the console is a
demonstrated capability rather than a theoretical one.

BitLocker is the control that matters here, and it is on. Data at rest is protected even with the
drives removed. Console access to a running node is a different question and is not mitigated.

### Out of band management

Raritan Dominion KX3 KVM units and iDRAC controllers are a second door into the hardware, and
neither one authenticates against Entra. They have their own credentials and their own lifecycle.

The iDRACs on these machines are unlicensed, which the project recorded as a cost constraint. It
is worth noting that an unlicensed iDRAC is not a disabled iDRAC.

Any future production use of this pattern needs an explicit answer for who can reach out of band
management and how those credentials are governed. This POC does not have one.

### Credential material on a single workstation

The credential map is honest about this and says so directly:

> "the working credentials were only ever stored as DPAPI blobs on a single machine, and that is a
> single point of failure."

The mitigation exists and it was built. Every credential now has a copy in `azl-cluster-01-kv`,
which is durable, soft delete enabled, and RBAC governed. The local `.creds\*.cred` files are
DPAPI encrypted to one user on one machine and are gitignored.

Two things remain true anyway. The DevBox holds usable credential material at rest, and DPAPI
protects it from other users rather than from someone with that user's session.

### Domain accounts and the reach they have

The cluster nodes are domain joined to `sim.example.internal` as part of deployment step 0.16. Reaching
them over WinRM uses `sim\labadmin`, a domain admin account.

Two accounts are worth a reviewer's attention:

| Account | Reach |
| --- | --- |
| `sim\labadmin` | Domain admin. The working path to every node. |
| `sim\AZLCL-DEPLOY-ADM` | Deployment and lifecycle account. Denied for general remote admin, which is the correct restriction. |

The node local `Administrator` credential was rotated by deployment and is now lifecycle managed,
which removed a static shared secret from the estate. The pre-deployment copy in `.creds` is stale
and should be treated as such.

Node 03 is the exception to all of this. It remains workgroup joined and outside the cluster, so it
is outside the domain and outside the deployment managed credential lifecycle.

### Supply chain

There is no private registry. Container images pull from Microsoft Container Registry. That is a
reasonable dependency for a POC and it is a stated one rather than an unexamined one, but it does
mean image provenance is inherited rather than controlled.

### Infrastructure state

Terraform state was held locally during the lifecycle test. State files can contain sensitive
values. Any move toward routine use needs remote state with access control before it needs
anything else.

## Deviations we made on purpose

Two decisions in this project run against normal corporate security posture. Both were required,
both are documented, and both should be said out loud rather than discovered.

### The security monitoring extension opt out

Azure Local deployment could not proceed because an incumbent corporate security monitoring agent
already occupied the single monitoring agent slot on the nodes. The resolution was a scoped
`SkipSecurityMonitoringAgent=true` opt out applied at resource and resource group scope, tracked as a
formal security exception.

This is the one that will draw a question, and it deserves a straight answer. A security monitoring
agent was opted out of on these specific machines so that the platform's own observability could
install. The scope is the POC resource group, the exception is recorded, and the full evidence
including how the conflict was identified is at
[The security monitoring extension and observability agent conflict evidence](../../working/findings/security-agent-observability-conflict-evidence.md).

### Interactive and batch logon for the deployment account

The Azure Local deployment account requires logon rights that a service account would normally
never be granted. This is a documented product requirement, not a local shortcut.

> "Interactive logon. The deployment user must be allowed to log on interactively."

Source: [Prepare Active Directory for Azure Local deployment](https://learn.microsoft.com/en-us/azure/azure-local/deploy/deployment-prep-active-directory)

The same page requires "Log on as a batch job" for the same account. Anyone reviewing the AD
configuration will see rights that look wrong in isolation, and this is why they are there.

## What this actually tells you about hybrid

The finding worth carrying out of this project is short.

Moving a workload from Azure to on-premises hardware does not reduce the security surface. It adds
to it. You keep every control the cloud gave you, because Entra, PIM, and RBAC still govern the
control plane. Then you add a building, a rack, a set of out of band management controllers, and a
domain, and none of those are things a subscription ever asked you to think about.

The platform helps more than expected. BitLocker, Credential Guard, WDAC, and SMB signing arrive
switched on. That closes a lot of the traditional on-premises gap without an operator doing
anything.

What it cannot close is physical, and physical is exactly what you signed up for when you chose to
own the hardware.

## Residual risks accepted for this POC

DECISION REQUIRED. Accepting a risk is a judgment, not a fact, and this section needs the project
owner to confirm or amend each line before it is presented or circulated.

Draft list, based on what is documented above:

1. Physical and console access to the nodes is not controlled beyond lab access. Accepted because
   this is a lab POC with no production data.
2. Out of band management credentials are outside Entra governance and have no defined owner.
   Accepted for POC. Blocking for production use.
3. Credential material exists at rest on one workstation. Partially mitigated by Key Vault backup.
4. The security monitoring extension is opted out on the POC nodes under a recorded exception scoped to one resource group.
5. Container images are pulled from Microsoft Container Registry with no private registry or image
   scanning in the path.
6. Terraform state was local during testing rather than remote and access controlled.
7. Node 03 sits outside the cluster, the domain, and the managed credential lifecycle.
8. No formal threat model exists. This document records posture and boundaries instead.

## Related records

- [Azure permissions and capability register](azure-permissions-and-capability-register.md)
- [Credential map](credential-map.md)
- [POC requirements gap audit](../planning/poc-requirements-gap-audit.md)
- [Azure Local platform boundary research](../planning/azure-local-platform-boundary-research.md)
- [External dependencies and POC lessons](../planning/external-dependencies-and-poc-lessons.md)
