---
title: "Azure Local platform boundary research"
domain: [platform]
layer: [os, cluster]
type: reference
status: current
proof: documented
audience: [engineer, leadership]
tags: [platform-boundary, supportability, custom-images, constraints]
updated: 2026-08-31
---

# Azure Local platform boundary research

## Purpose

This note tests the original POC opportunity list against first-party product documentation. It avoids a personal
judgment about the request authors. The evidence instead shows that several items use public-Azure resource names for
capabilities that Azure Local provides through different mechanisms, or that belong to an adjacent product entirely.

The right test is:

```text
Requested named resource
-> documented product that owns it
-> documented Azure Local mechanism, if any
-> POC evidence and remaining decision
```

## Findings

### 1. VM Scale Sets do not exist on Azure Local, and the autoscaling outcome does

This one matters more than the others, so it gets treated properly rather than dismissed.

**Short answer.** There is no VMSS resource on Azure Local and there is no way to autoscale a group
of plain Azure Local VMs. There is, however, a documented and supported way to automatically scale
the number of VMs backing a Kubernetes workload. Those two facts sit together and the second one is
usually what the request was actually after.

#### The structural reason, from the VMSS side

The strongest evidence is not an absence in the Azure Local docs. It is what VMSS itself requires.

VMSS is `Microsoft.Compute/virtualMachineScaleSets`. Its resource definition requires a subnet id
from `Microsoft.Network/virtualNetworks`, an `imageReference` naming a publisher, offer, and SKU
from the Azure image catalog, a `managedDisk.storageAccountType` such as `Premium_LRS`, an Azure VM
SKU name such as `Standard_B12ms`, and optionally `availabilityZones`.

Source: [Virtual Machine Scale Sets AVM module](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/compute/virtual-machine-scale-set)

Every one of those is an Azure regional construct. Azure Local has none of them. It has logical
networks rather than VNets, its own image gallery rather than the Azure Marketplace catalog, storage
paths on Storage Spaces Direct rather than Azure Managed Disks, and no availability zones at all.

Then the definitional statement, which is the one to quote if you only get to use one. Microsoft
describes Azure Local VMs as:

> "Windows and Linux VMs hosted outside Azure, on your corporate network, running on Azure Local."

Source: [Compare management capabilities of VMs on Azure Local](https://learn.microsoft.com/azure/azure-local/concepts/compare-vm-management-capabilities)

A scale set creates Azure VMs inside an Azure region. An Azure Local VM is by definition hosted
outside Azure and projected into it through Arc. They are different resource types in different
places, and one cannot produce the other.

#### The confirming evidence, from the Azure Local side

The same page carries an exhaustive matrix titled "Azure VM management capability", comparing what
is available across Azure Local VMs, Arc-enabled servers, and unmanaged VMs. It is worth reading in
full, because what it contains is as informative as what it does not.

Every scaling capability listed is vertical and applies to one VM at a time:

| Capability | Azure Local VMs enabled by Azure Arc |
| --- | --- |
| Change vCPU count | Yes |
| Change memory amount | Yes |
| Change minimum memory | Yes |
| Change maximum memory | Yes |

There is no scale set row, no autoscale row, and no availability set row anywhere in the matrix. The
platform's answer to "I need more capacity" is to make one VM bigger, not to make more VMs.

The supported operations page adds one more constraint that is fatal rather than merely limiting.

> "Cloning or copying a VM. This can result in corruption, management errors, or failure to start."

Source: [Supported operations for Azure Local VMs enabled by Azure Arc](https://learn.microsoft.com/azure/azure-local/manage/virtual-machine-operations?view=azloc-2608#unsupported-vm-operations)

A scale set is a set of identical instances produced from one shared model. Azure Local explicitly
does not support copying a VM and warns that it causes corruption. Even setting aside the missing
resource type, the mechanic itself is prohibited.

#### Windows specifically, which is the sharper question

Kubernetes and Docker autoscaling are often assumed to be a Linux story. On Azure Local that
assumption is only half right, and the distinction decides whether the outcome is reachable.

AKS on Azure Local supports Windows worker nodes. The published default sizing table lists them
alongside Linux:

| System role | VM size | Memory, CPU |
| --- | --- | --- |
| AKS Linux worker node | Standard_A4_v2 | 8 GB, 4 vcpu |
| AKS Windows worker node | Standard_K8S3_v1 | 6 GB, 4 vcpu |

Source: [Scale requirements for AKS on Azure Local](https://learn.microsoft.com/azure/aks/aksarc/scale-requirements)

So Windows containers can run, and the cluster autoscaler can add and remove Windows worker nodes
with demand.

What is not available is a pool of Windows Server VMs that grows and shrinks on its own. If the
workload is a classic IIS server that must remain a VM, there is no autoscale path on Azure Local at
all. Reaching the autoscaling outcome means re-platforming that workload into a Windows container
first, which is a real piece of application work and not a configuration change.

That is the honest answer to the Windows Server question. Not "use Kubernetes instead", but "the
outcome is reachable only if the workload can become a container, and if it cannot, the answer is
no".

#### The honest split

| What you want | Azure Local answer |
| --- | --- |
| Scale VM count with demand, Linux containers | Yes. AKS Arc cluster autoscaler. |
| Scale VM count with demand, Windows containers | Yes. Windows node pools are supported. |
| Scale VM count with demand, Windows Server VMs | No. No primitive exists. Re-platform or accept it. |
| Scale VM count with demand, any plain VM | No. |
| Make one VM bigger | Yes. vCPU and memory are both changeable. |
| Identical instances from one model | No. Cloning a VM is explicitly unsupported. |
| Load balanced pool in front of those instances | Not Azure Load Balancer. MetalLB, see finding 3. |


#### What Azure Local does have

The outcome behind the request, which is VM count rising and falling with demand, is available. It
arrives through AKS on Azure Local rather than through a compute resource, and it is a first class
documented feature with its own CLI flags.

> "Create an AKS cluster using the `az aksarc create` command, and enable and configure the cluster autoscaler on the node pool for the cluster using the `--enable-cluster-autoscaler` parameter and specifying `--min-count` and `--max-count` for a node."

Source: [Use cluster autoscaler on an AKS cluster](https://learn.microsoft.com/azure/aks/aksarc/auto-scale-aks-arc)

The autoscaler creates and removes worker node VMs on the Azure Local instance in response to pods
that cannot be scheduled. It has a configurable profile covering scan interval, scale down delay,
and utilisation threshold, and it has published capacity limits.

> "When the autoscaler is enabled, AKS on Azure Local currently supports a maximum of 12 clusters per Azure Local environment."

Source: [Scale requirements for AKS on Azure Local](https://learn.microsoft.com/azure/aks/aksarc/scale-requirements)

#### The honest split

| What you want | Azure Local answer |
| --- | --- |
| Scale VM count with demand, containerised workload | Yes. AKS Arc cluster autoscaler, documented, with published limits. |
| Scale VM count with demand, plain VMs | No. No primitive exists. |
| Identical instances from one model | No. Cloning a VM is explicitly unsupported. |
| Load balanced pool in front of those instances | Not Azure Load Balancer. MetalLB, see finding 3. |

**Finding.** The request for VMSS was not unreasonable, it was expressed in a public cloud resource
name that does not transfer. Decomposed, most of it is available. Automatic node scaling is a
supported AKS on Azure Local feature. What is genuinely unavailable is autoscaling a group of
standalone VMs that are not Kubernetes nodes, and that is unavailable for a structural reason rather
than a roadmap reason.

**POC evidence and what was not tested.** Terraform completed a real Azure Local VM lifecycle.
Dashboard replicas scaled `2 -> 3 -> 2` and self-healed, operator initiated. The AKS Arc cluster
autoscaler was never enabled on this cluster, so this project has no evidence about it either way.
It is untested here, not unavailable. HPA additionally requires the Metrics Server, which is not
preinstalled and was not deployed.


### 2. Availability Sets are Azure VM regional topology, not Azure Local VM grouping

Microsoft scopes its availability-options document to Azure virtual machines and defines Availability Zones as
physically separate zones inside an Azure region.

> "This article provides an overview of the availability options for Azure virtual machines."
> "An Availability Zone is a physically separate zone, within an Azure region."

Source: [Availability options for Azure Virtual Machines](https://learn.microsoft.com/azure/virtual-machines/availability)

Azure Local instead documents operational primitives such as cluster-level live migration and automatic balancing.

> "Live migrate a VM to another node in the same cluster."

Source: [Supported operations for Azure Local VMs enabled by Azure Arc](https://learn.microsoft.com/azure/azure-local/manage/virtual-machine-operations?view=azloc-2608#supported-vm-operations)

Finding: an Availability Set is not an Azure Local deployment target. A valid local resiliency test is clustered VM
recovery/live migration or a replicated Kubernetes workload. The POC demonstrated VM migration, host reboot recovery,
and replicated dashboard self-healing; it did not claim cloud fault-domain semantics.

### 3. External Kubernetes reachability on Azure Local uses MetalLB, not Azure Load Balancer

Microsoft's AKS on Azure Local documentation describes an explicit MetalLB extension for external service IPs.

> "The MetalLB extension for Azure Arc enabled Kubernetes is a tool that allows you to generate external IPs for your
> applications and services."
> "MetalLB takes care of assigning and releasing these addresses as needed when you create services, but it only
> distributes IPs that are in its configured pools."

Source: [Overview of MetalLB for Kubernetes clusters](https://learn.microsoft.com/azure/aks/aksarc/load-balancer-overview)

The same documentation distinguishes the normal Kubernetes service roles.

> "Cluster IP: creates an internal IP address for use within the Kubernetes cluster. Use Cluster IP for internal-only
> applications that support other workloads within the cluster."

Source: [Container networking concepts](https://learn.microsoft.com/azure/aks/aksarc/concepts-container-networking#kubernetes-services)

Finding: a request for an "Azure integrated load balancer" must be translated. Internal application routing is a
Kubernetes Service/EndpointSlice concern; an external VIP is a MetalLB configuration and IP-governance concern. The
POC proved the former, including independent in-cluster request distribution. The latter is intentionally blocked on
subscription provider registration and is not being escalated.

### 4. Storage Spaces Direct is cluster block storage, not Blob, Queue, or Table APIs

Microsoft describes Storage Spaces Direct as a cluster storage technology.

> "Storage Spaces Direct is a software-defined storage solution that allows you to share storage resources in your
> converged and hyperconverged IT infrastructure."
> "It enables you to combine internal storage drives on a cluster of physical servers ... into a software-defined pool
> of storage."

Source: [Storage Spaces Direct overview](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-direct-overview#what-is-storage-spaces-direct)

Microsoft separately defines Azure Storage data services as object, messaging, and NoSQL services accessed through a
storage account.

> "Azure Blobs: A massively scalable object store for text and binary data."
> "Azure Queues: A messaging store for reliable messaging between application components."
> "Azure Tables: A NoSQL store for schemaless storage of structured data."
> "Each service is accessed through a storage account with a unique address."

Source: [Introduction to Azure Storage](https://learn.microsoft.com/azure/storage/common/storage-introduction#azure-storage-data-services)

Finding: Azure Local S2D provides the storage foundation for cluster workloads. It does not turn the cluster into the
Azure Storage service API. A Blob/Queue/Table requirement needs a specific application decision: use Azure Storage,
a compatible emulator for development, or choose a local workload-specific service. The original phrasing combines
these separate layers.

### 5. Azure DevOps agents are general-purpose execution machines, not Azure Local features

Microsoft defines an Azure Pipelines self-hosted agent as a machine chosen and operated by the customer.

> "A self-hosted agent is an agent that you set up to run jobs and manage yourself."
> "You can install the agent on Linux, macOS, and Windows machines. You can also install the agent on a Docker
> container."

Source: [Azure Pipelines agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents?view=azure-devops#self-hosted-agents)

Microsoft further defines Azure VM Scale Set agents as a specific Azure DevOps agent option that uses Azure VM Scale
Sets, while ordinary self-hosted agents run on customer-managed VMs.

> "Self-hosted agents ... are hosted on your virtual machines (VMs)."
> "Azure Virtual Machine Scale Sets agents ... uses Azure Virtual Machine Scale Sets and can be autoscaled to meet
> demands."

Source: [Azure Pipelines agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents?view=azure-devops)

Finding: an ADO hybrid worker is a delivery-platform choice that can run on many machine types. Azure Local can host a
VM that runs one, but it neither requires nor gains its foundational value from deploying one. Keeping the existing ADO
estate unchanged and proving source validation with GitHub Actions is a scope decision, not an Azure Local limitation.

## Overall conclusion

The source material does not support a claim that every named Azure service in the opportunity list should deploy on
Azure Local. It supports a narrower and more useful conclusion:

- Azure Local is documented to host and manage Arc-enabled VMs and AKS Arc workloads.
- VMSS, Availability Sets, Azure Load Balancer, Azure Storage APIs, and Azure DevOps agents belong to distinct Azure
  product surfaces with their own documented semantics.
- Several original requests are valid desired outcomes stated with a cloud-resource name that does not transfer
  literally to Azure Local.
- The POC should be judged on the translated operational outcome and the evidence produced, while leaving deliberate
  governance decisions and selected follow-on work visible.

## Related records

- [Original POC Acceptance Criteria](original-poc-acceptance-criteria.md)
- [Omitted POC Elements and Technology Equivalents](omitted-elements-and-technology-equivalents.md)
- [POC Requirements Gap Audit](poc-requirements-gap-audit.md)

