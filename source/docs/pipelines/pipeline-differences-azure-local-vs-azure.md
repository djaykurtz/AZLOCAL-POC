---
title: "Where Azure Local changes a delivery pipeline"
domain: [delivery]
layer: [cluster, arc]
type: reference
depth: full
status: current
proof: proven
audience: [leadership, engineer]
tags: [pipelines, ci-cd, github-actions, azure-devops, azure-local, oidc, terraform]
updated: 2026-09-09
---

# Where Azure Local changes a delivery pipeline

## Why this document exists

The acceptance criteria asked for "Azure DevOps pipelines and hybrid workers", with the stated
intent of "tighter use of local compute for compile, pipelines, and tools such as Ansible or
Terraform".

The obvious way to answer that is to stand up a pipeline and point at a green run. This project did
not do that, and the honest reason is that it would have proved almost nothing. A pipeline is
mostly the same on Azure Local as it is against any Azure subscription. Most of its stages never
learn what platform they are eventually targeting.

What is worth writing down is the small number of places where the platform genuinely does change
the pipeline, because those are the places a future team will lose a week. Every one of them below
was hit by this project during the Terraform lifecycle work.

## The honest starting position

Say this first, before any of the analysis, because someone will ask.

**No pipeline has ever executed in this project.** A GitHub Actions workflow exists at
`.github/workflows/validate.yml`. It is authored, valid, and has never run. From
[STATUS.md](../../STATUS.md):

> "The GitHub Actions source-validation workflow is **authored but has never run**. This repository
> is owned by an Enterprise Managed User account, and GitHub-hosted runners are not available to EMU
> user-owned repositories, so `runs-on: ubuntu-latest` can never be scheduled."

That is a GitHub account-model constraint. It has nothing to do with Azure Local, and nothing to do
with Azure DevOps, which has its own separate agent model. The validation commands themselves were
run by hand on the DevBox instead.

## The stage by stage answer

| Stage | Changes on Azure Local? | What actually differs |
| --- | --- | --- |
| Source control and trigger | **No** | Git is git. Branch, PR, and path filters behave identically. |
| Agent or runner | **Yes, and this is the point of the requirement** | Hosted agents are somebody else's machine. Azure Local can host the agent itself, which is what "local compute" meant. |
| Build, lint, unit test | **No** | Same toolchain, same containers. Nothing here knows where the artifact lands. |
| Container image and registry | **Partly** | Azure Local pulls from a registry the same way anything else does. This POC never stood one up, so images come from Microsoft Container Registry and provenance is inherited rather than controlled. |
| Infrastructure code shape | **Yes** | The Azure Local VM is not a top level ARM resource. This is the single most surprising difference. |
| Pipeline identity | **Yes** | Human PIM cannot drive automation. A federated identity with narrow roles is required, and it does not exist yet. |
| Plan | **Mostly no, one trap** | Provider auto-registration reaches for actions the pipeline identity will not have. |
| Apply | **Yes** | ARM reports completion before the hypervisor agrees, so the pipeline must poll and reconcile. |
| State | **No, but it was never done** | Same remote state and locking requirement as anywhere. This POC ran state locally. |
| Deployment target | **Yes** | Custom location, logical network, and gallery image must already exist and be referenced by ID. There is no ambient region equivalent. |
| Provider registration | **Yes** | Subscription scoped gates that a resource group role can never satisfy. |
| Verification | **Yes** | ARM success is not the same as the workload running. The truth lives on the cluster. |
| Logging and observability | **Mostly no** | Arc and Log Analytics behave normally, with one local conflict noted below. |

## The five that actually matter

Everything above collapses to five things. If a future team reads only this section, they have the
useful part.

### 1. The VM is not the resource you think it is

In Azure, a virtual machine is a top level resource and your IaC addresses it directly. On Azure
Local it is not. From the
[permissions register](../access/azure-permissions-and-capability-register.md), dated 2026-08-18:

> "`Microsoft.AzureStackHCI/virtualMachineInstances` returned `InvalidResourceType` in global scope
> ... Not a role gap. The VM instance is an extension resource named `default` under its
> `Microsoft.HybridCompute/machines/<vm-name>` parent."

So a Terraform or Bicep module has to model a parent Arc machine, then an extension resource with a
fixed name, then a separate Azure Local NIC. Three objects where a cloud VM is one. Use the Azure
Verified Module or a parent scoped azapi contract rather than inventing the shape.

### 2. ARM finishes before the hypervisor does

This is the one that breaks unattended automation. From the
[integration test results](../planning/kubernetes-terraform-integration-test-results.md):

> "Azure Local VM extension remained ARM `Accepted` after Hyper-V runtime success and after the
> runtime delete, requiring local Terraform state reconciliation."

The VM was genuinely running. Hyper-V reported `Running` and `Operating normally`, and the clustered
role was `Online` on `AZL-NODE-04`. ARM had simply not caught up. A pipeline that trusts the ARM
provisioning state will either hang or record a false failure, so apply steps need polling,
reconciliation, and a timeout policy that a cloud only pipeline would never bother writing.

The [gap audit](../planning/poc-requirements-gap-audit.md) states the consequence plainly: add
"retry/poll and reconciliation design to CI/CD acceptance criteria; do not claim unattended pipeline
readiness yet."

### 3. A human PIM session is not a pipeline identity

Every operation in this POC ran under an eight hour PIM activation. That works for a person and
fails for a schedule. It failed during this project, mid lifecycle:

> "PIM expired during NIC cleanup. | Future automation cannot depend on human PIM. | Use dedicated
> OIDC pipeline identity with exact roles, protected apply/destroy approvals, and remote state."

The permissions register already sizes the replacement. A pipeline that creates and destroys only
its own VM and NIC needs **Azure Stack HCI VM Contributor** at the resource group, not the broad
Azure Stack HCI Administrator a human uses. Remote state needs **Storage Blob Data Contributor** on
a dedicated account. Both rows are recorded as future pipeline identity only, and the register is
honest that the second is "Not yet assigned because the pipeline identity does not exist."

Creating that identity is itself an external gate. The register flags it:

> "Create GitHub OIDC Entra identity | Entra application registration and federated credential write
> permission | Entra tenant | **Not verified for current user** | Potential external gate."

### 4. Provider registration is a subscription action, and no resource group role grants it

Two providers gated real capability in this project. `Microsoft.EdgeMarketplace` had to be
registered before Marketplace images could be imported, and `Microsoft.KubernetesRuntime` was denied
on 2026-08-18 and deliberately not escalated. The register states the rule:

> "Provider registration cannot be granted from an RG-scoped role."

There is a pipeline specific version of this trap. The Terraform AzureRM provider tries to register
providers on its own behalf, and it reaches for things unrelated to the work:

> "AzureRM provider auto-registration was disabled because it attempted unrelated
> `Microsoft.Cache/register/action`."

A least privilege pipeline identity will fail on that before it fails on anything real. Turn the
behaviour off explicitly rather than widening the identity to accommodate it.

### 5. Verification has to ask the cluster, not the control plane

A cloud pipeline verifies by asking ARM. Here ARM is one of two sources of truth and it is the
slower one. Real verification means cluster side checks: `Get-ClusterGroup` for role ownership and
state, `Get-VirtualDisk` and `Get-StoragePool` for storage health, and Hyper-V event log reads for
whether a guest actually stayed up.

The live migration evidence makes the point sharply. The
[WS2025 quick reference](../runbooks/ws2025-azure-local-demo-quickref.md) warns against the obvious
check:

> "Do not use `(Get-VM).Uptime` as the continuity check. **That counter resets on the destination
> host** because the worker process there is new, so a successful live migration looks like a
> restart."

A pipeline that verifies the wrong counter will report a reboot that never happened.

## What does not change, and is worth saying out loud

The agent question is the one people assume is exotic, and it is not. Microsoft's own definition,
quoted in the
[platform boundary research](../planning/azure-local-platform-boundary-research.md):

> "A self-hosted agent is an agent that you set up to run jobs and manage yourself."
> "You can install the agent on Linux, macOS, and Windows machines. You can also install the agent
> on a Docker container."

That research concludes:

> "an ADO hybrid worker is a delivery-platform choice that can run on many machine types. Azure
> Local can host a VM that runs one, but it neither requires nor gains its foundational value from
> deploying one."

Azure Local hosting a Linux or Windows VM is proven several times over in this project. An agent is
a process on such a VM. There is no Azure Local specific problem to solve there, which is exactly
why running one would not have taught anybody anything.

## One local conflict worth knowing

Observability is otherwise ordinary, with a single exception recorded in the
[security posture](../access/security-posture-and-boundaries.md). An incumbent corporate security monitoring
Monitoring Agent held the single monitoring agent slot on the nodes and blocked Azure Local's own
observability, which needed a scoped `SkipSecurityMonitoringAgent=true` opt out. A
pipeline that deploys monitoring extensions on these hosts needs to know that slot is contested.

## The shopping list for a real pipeline

Nothing here is exotic. It is five items, and four of them are permissions.

1. An Entra application with a federated credential for the pipeline. Verify the requester can
   create one before planning around it.
2. **Azure Stack HCI VM Contributor** at the POC resource group for that identity.
3. A dedicated storage account for Terraform state, with **Storage Blob Data Contributor** and
   locking.
4. Any provider registrations the target capability needs, obtained at subscription scope, plus
   AzureRM provider auto-registration disabled.
5. Apply steps that poll for hypervisor truth rather than trusting the ARM provisioning state, and
   verification steps that read cluster state rather than resource state.

An agent to run it on is the easy part. The cluster already hosts VMs.

## Sources

- [STATUS.md](../../STATUS.md), current boundaries
- [Azure permissions and capability register](../access/azure-permissions-and-capability-register.md)
- [Kubernetes and Terraform integration test results](../planning/kubernetes-terraform-integration-test-results.md)
- [Azure Local POC requirements gap audit](../planning/poc-requirements-gap-audit.md)
- [Azure Local platform boundary research](../planning/azure-local-platform-boundary-research.md)
- [Security posture and boundaries](../access/security-posture-and-boundaries.md)
- [WS2025 Azure Local demonstration quick reference](../runbooks/ws2025-azure-local-demo-quickref.md)
- [Sprint S6, Terraform against cluster](../../working/sprints/terraform-against-cluster.md)
- Microsoft Learn, [Azure Pipelines agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents?view=azure-devops#self-hosted-agents)
