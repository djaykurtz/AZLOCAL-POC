---
title: "Database as a service on Azure Local: what could have met the requirement"
domain: [platform]
layer: [runtime, application]
type: reference
status: current
proof: documented
audience: [leadership, engineer]
tags: [database, sql-managed-instance, arc-data-services, postgresql, deferred, capacity]
updated: 2026-09-14
---

# Database as a service on Azure Local: what could have met the requirement

Acceptance criterion 5 is deferred and the recorded reason is that no workload was chosen. That is
true and it is also the least interesting half of the answer. This walks the options that exist,
what each one would have cost on this cluster, and how two real applications would actually sit on
them.

Nothing here was deployed. It is analysis, not evidence, and it is labelled that way throughout.

## What was actually asked for

From [original-poc-acceptance-criteria.md](original-poc-acceptance-criteria.md):

> 5. Azure database software as a service.
>    - Deploy highly available/scalable databases with less manual SQL/OS maintenance.

Two lines, and no product named. The bar is three properties: highly available, scalable, and less
manual SQL and OS maintenance. That matters because the deck used to say the ask was "SQL Managed
Instance with failover", which came from our own planning file rather than from the requirement.
SQL Managed Instance is the heaviest way to clear that bar, not the only way.

The same document's future work list says the same thing from the other direction:

> 7. Database and Azure Storage opportunities after a specific application workload justifies them.

## The options, and what each one costs here

### 1. SQL Managed Instance enabled by Azure Arc

The closest thing to genuine database as a service on hardware you own. It runs on Kubernetes, so
on this cluster it would land on AKS Arc.

**It does not fit, and not by a small margin.** From
[Microsoft Learn, sizing guidance](https://learn.microsoft.com/en-us/azure/azure-arc/data/sizing-guidance):

> A minimum size Azure Arc-enabled data services deployment could be considered to be the Azure Arc
> data controller plus one SQL managed instance. For this configuration, you need at least 16-GB RAM
> and 4 cores of *available* capacity on your Kubernetes cluster. You should ensure that you have a
> minimum Kubernetes node size of 8-GB RAM and 4 cores and a sum total capacity of 16-GB RAM
> available across all of your Kubernetes nodes.

Measured on this cluster on 2026-09-09:

| | Required | Available |
| --- | --- | --- |
| Kubernetes node size | 8 GB RAM, 4 cores | 5.86 GiB allocatable, 4 vCPU |
| Available across all nodes | 16 GB RAM, 4 cores | about 4.3 GiB on the one worker |

The single worker node is smaller than the stated minimum node size before any capacity question is
asked. The same page also asks for headroom on top:

> Maintain at least 25% of available capacity across the Kubernetes nodes.

Adding a worker does not rescue it either. Each host has about 13 GB free after Windows, Storage
Spaces Direct, Azure Local and the existing AKS node, so an 8 GB worker fits on paper and two of
them would leave roughly 5 GB on each of two hosts. That is the configuration that passes a
spreadsheet and fails the first time anything moves.

One further constraint worth knowing before anyone plans around older guidance. Per the
[release notes](https://learn.microsoft.com/en-us/azure/azure-arc/data/release-notes), September
2025:

> Indirect mode is retired for SQL Managed Instance enabled by Azure Arc.

So the disconnected deployment style is gone. Direct mode is the only mode, which means continuous
connectivity to Azure and an Azure resource for the instance.

### 2. Azure Arc-enabled PostgreSQL

**This option no longer exists.** From the same release notes, July 14, 2025:

> Azure Arc-enabled PostgreSQL server is retired.

That is the single most important finding in this document, because PostgreSQL is what most of the
candidate workloads actually want. There is no Arc-managed PostgreSQL to deploy at any size.

### 3. SQL Server in a virtual machine, connected to Azure Arc

Not database as a service. It is a database you still run, with Azure management attached to it.
Azure gains inventory, best practice assessment, patching visibility, Microsoft Defender coverage
and licensing reporting. You keep the OS and the SQL instance.

This is the option that actually fits the hardware, and it partially clears the bar:

| Property asked for | Met? |
| --- | --- |
| Highly available | Partially. Cluster level resiliency only, which the node loss test already proved. No Always On availability group at this node count and memory. |
| Scalable | No, not without manual resizing. |
| Less manual SQL and OS maintenance | Partially. Visibility and assessment, not managed patching. |

### 4. Azure SQL Database or Azure Database for PostgreSQL in the cloud

Meets all three properties completely, and is the one option where nothing has to be sized against a
32 GB node. It also fails the spirit of the criterion, which sat under a broader goal of keeping
tools and services local without prematurely accruing cloud operating cost. Worth naming so the
choice is explicit rather than assumed away.

### 5. A database container on AKS Arc with no Arc data services

PostgreSQL or SQL Server as an ordinary Kubernetes workload on the existing cluster, backed by
Storage Spaces Direct through a persistent volume. Cheapest by far, and it proves the storage and
scheduling path rather than the managed database path. It clears none of the three properties on its
own, but it is the only one that could have been demonstrated on this hardware in an afternoon.

## How two real applications would sit on this

Conjecture, to make the options concrete. Neither was deployed.

### Atlassian Confluence

Confluence wants PostgreSQL. Given option 2 is retired, there is no Arc-managed database for it at
all, so the realistic shapes are:

- **Postgres in a VM on the cluster, Confluence in a container or a second VM.** Everything local.
  Resiliency comes from the cluster, not from the database. This is the only fully local shape.
- **Confluence local, Azure Database for PostgreSQL in the cloud.** Meets the maintenance goal and
  breaks the local goal. It also inherits a dependency on the corporate network path, which this
  project already has direct experience of: the existing Confluence instance could not reach its own
  mail relay from Azure Container Apps because no route existed.
- **Both in the cloud.** Not an Azure Local exercise.

The useful observation is that Confluence is a fair test *because* its database is PostgreSQL. It
demonstrates that the phrase "database as a service" does not survive contact with a specific
application. The moment you name the workload, the managed option disappears.

### Halo ITSM

Halo wants SQL Server and an IIS web tier, which is the better fit of the two:

- **SQL Managed Instance enabled by Arc, web tier on AKS or in a VM.** This is the textbook answer
  and the one the criterion was probably imagining. It needs the 16 GB the cluster does not have.
- **SQL Server in an Arc-connected VM, web tier in a second VM.** Fits today. Option 3 above, with
  its partial credit.

So of the two candidate applications, one has a managed path that this hardware cannot host, and the
other has no managed path at all.

## What this means for the criterion

The deferral stands, and the reason is now better than "no workload was chosen".

1. **No workload was chosen**, which remains the honest first answer. A database with no application
   behind it proves you can install software, not that the requirement was met.
2. **The managed option would not have fit.** SQL MI enabled by Arc needs 16 GB of free Kubernetes
   capacity and an 8 GB minimum node against a 5.86 GiB worker on 32 GB hosts. This was never a
   permissions problem. `Microsoft.AzureArcData` is `Registered` and the custom location
   `azl-cluster-01-cl` exists, so the platform was ready and the memory was not.
3. **For half the plausible workloads the managed option does not exist**, because Arc-enabled
   PostgreSQL was retired in July 2025.

If this is picked up later, the order of work is: name the application, then check whether its
database engine still has a managed Arc option, then size the cluster to the answer. Doing those in
any other order produces the deferral again.

## Sources

- [original-poc-acceptance-criteria.md](original-poc-acceptance-criteria.md), criterion 5 and the future work list
- [acceptance-criteria-verification.md](acceptance-criteria-verification.md), section G5
- [omitted-elements-and-technology-equivalents.md](omitted-elements-and-technology-equivalents.md), the Azure Database SaaS row
- [poc-requirements-gap-audit.md](poc-requirements-gap-audit.md)
- [Microsoft Learn, Azure Arc data services sizing guidance](https://learn.microsoft.com/en-us/azure/azure-arc/data/sizing-guidance)
- [Microsoft Learn, Azure Arc-enabled data services release notes](https://learn.microsoft.com/en-us/azure/azure-arc/data/release-notes)
- Cluster capacity read live on 2026-09-09 with [Show-ClusterEvidence.ps1](../../scripts/Show-ClusterEvidence.ps1)
