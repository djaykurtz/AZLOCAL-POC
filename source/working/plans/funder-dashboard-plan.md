---
title: "Plan: funder-facing dashboard for the Azure Local PoC"
domain: [observability]
layer: [arc]
type: plan
status: current
proof: proven
audience: [leadership, engineer]
tags: [azure-monitor-workbook, dashboard, resource-graph, funders]
updated: 2026-08-03
---

# Plan: funder-facing dashboard for the Azure Local PoC

Goal: a shareable "here is what we built and it is running" panel for the people funding the project -
cluster health, the VMs we run (distro/version/status), and (later) Docker and Kubernetes workloads.

Bottom line: Azure provides this natively; we do NOT build a custom app. Phase 1 is an Azure Dashboard
built from Azure Resource Graph (ARG) queries; a polished version is an Azure Monitor Workbook. Docker and
Kubernetes are added as they come online.

All queries below were validated against the live tenant on 2026-07-31.

--------------------------------------------------------------------------------
## What ARG can and cannot see (important, drove this plan)

- ARG DOES index `microsoft.hybridcompute/machines` - this covers BOTH the physical cluster nodes
  (kind = '') and the Azure Local VMs (kind = 'HCI'). For each it gives name, guest OS, OS SKU
  (= the distro, e.g. "Rocky Linux 10.2 (Red Quartz)"), OS version (kernel/build), Arc status
  (Connected), and agent version. So distro + version + up/down is native.
- ARG does NOT index the Azure Local VM child resources: `microsoft.azurestackhci/virtualMachineInstances`,
  `/networkInterfaces`, `/galleryImages` all return zero. So POWER STATE, PRIVATE IP, and IMAGE NAME are
  NOT available in ARG. Those come from the stack-hci-vm CLI / ARM REST only.
- Implication: a pure-ARG board shows the fleet + distro + status cleanly; to add IP/power/image you either
  use a Workbook with an ARM (Azure Resource Manager) data source, or push a scheduled inventory into Log
  Analytics and read that. See "Filling the gap" below.

--------------------------------------------------------------------------------
## Phase 1 - inventory board (ARG, pin to an Azure Dashboard)

### Tile 1: cluster nodes (physical hosts)
```kql
resources
| where type =~ 'microsoft.hybridcompute/machines' and kind == ''
| where name has 'AZLOCAL'                    // scope to this cluster's nodes (env-specific)
| project Node=name, OS=tostring(properties.osSku), Build=tostring(properties.osVersion),
          Status=tostring(properties.status), Agent=tostring(properties.agentVersion)
| order by Node asc
```
Shows: the nodes, "Azure Stack HCI", build 10.0.26100.x, Connected. Good "the cluster is healthy" tile.

### Tile 2: tenant VMs (what we run on the cluster) - distro + version + status
```kql
resources
| where type =~ 'microsoft.hybridcompute/machines' and kind =~ 'HCI'
| project Slot=tostring(tags.slot), Role=tostring(tags.role), VM=name,
          Distro=tostring(properties.osSku), Kernel=tostring(properties.osVersion),
          Status=tostring(properties.status), Agent=tostring(properties.agentVersion)
| order by Slot asc, VM asc
```
Shows e.g. docker-1 | docker-host | rocky-docker-01 | Rocky Linux 10.2 (Red Quartz) | 6.12.0-... |
Connected. This is the "what distro is running where" answer, native, no build.

### Slot model (end-game demo) - dashboard is name-agnostic, VMs self-label
The VMs tile filters by TYPE + kind, never by hostname, so ANY Azure Local VM auto-appears/drops off as
it is created/deleted - zero per-VM tile edits, which matters because the test VMs are transitory. To make
it read as labelled "scaling slots" instead of a raw name list, VMs carry two tags on their Arc machine
record (Microsoft.HybridCompute/machines, which is what the tile queries):
- `slot`  = a stable position label independent of the VM name (e.g. docker-1, k8s-1, k8s-2)
- `role`  = what runs there (e.g. docker-host, k8s-node)
New-AzLocalTestVm.ps1 stamps these via -Slot/-Role at create time (az tag update ... --operation Merge on
the hybridcompute/machines id). Whatever is "loaded" into a slot shows up under that slot automatically.

### Tile 3: cluster resource + region
```kql
resources
| where type =~ 'microsoft.azurestackhci/clusters'
| project Cluster=name, Status=tostring(properties.status),
          Version=tostring(properties.reportedProperties.clusterVersion), Location=location
```

### Tile 4: gallery images available (validate field names when building)
```kql
resources
| where type =~ 'microsoft.azurestackhci/galleryimages'
| project Image=name, OSType=tostring(properties.osType), State=tostring(properties.provisioningState)
```
NOTE: galleryimages showed zero in ARG on 2026-07-31 (child-resource indexing). If it stays empty, source
the image list from the CLI (az stack-hci-vm image list) via the Workbook ARM data source instead.

### How to pin
Portal -> Resource Graph Explorer -> paste query -> Run -> "Pin to dashboard" -> a new/shared Azure
Dashboard. Repeat per tile. Share the dashboard (RBAC) with the funders (Reader is enough to view).

--------------------------------------------------------------------------------
## Filling the gap: power state, IP, image (not in ARG)

Two supported options, pick per how polished it needs to be:

- Option A (quick, good enough for a demo): a scheduled PowerShell inventory (extends our existing
  New-AzLocalTestVm/az stack-hci-vm queries) that writes a table of VM | IP | power | image | host-node |
  distro to a CSV/JSON, and either shows it in the meeting or uploads it to a storage account a Workbook
  reads. Low effort, we already have all the queries.
- Option B (native, richer): an Azure Monitor Workbook. Workbooks support an ARM (Azure Resource Manager)
  data source that can call the stack-hci-vm REST endpoints directly, so a single Workbook can show the
  ARG inventory AND the CLI-only fields (IP/power/image) in one board, with sections, titles, and a
  refresh button. This is the recommended funder-facing artifact.

--------------------------------------------------------------------------------
## Phase 2 - Docker status (when we present the container work)

ARG cannot see inside a guest, so Docker container status needs telemetry off the host:
- The Docker host already has the Arc guest agent (Connected). Add the Azure Monitor Agent + a data
  collection rule, or the Container Insights path, so container/host metrics land in Log Analytics; then a
  Workbook tile runs a Log Analytics (KQL) query for container count / health / restarts.
- Lightweight alternative for the PoC: a tiny cron on the host that runs `docker ps` + `docker stats` and
  posts a summary (count, names, health) to a Log Analytics custom table via the HTTP Data Collector /
  DCR; the Workbook reads that table. Cheap and demo-ready.
- (Dockge itself at http://<host-ip>:5001 is the live operator UI, but it is not a funder board.)

--------------------------------------------------------------------------------
## Phase 3 - Kubernetes (after the AKS sprint)

- AKS on Azure Local surfaces in ARG as `microsoft.kubernetes/connectedclusters` and
  `microsoft.hybridcontainerservice/provisionedclusterinstances` - so cluster-level inventory (name,
  version, node count, status) becomes ARG tiles, same pattern as above.
- Workload detail (pods, deployments, services) comes from Container Insights (Azure Monitor for
  Containers) into Log Analytics, shown via the portal's Kubernetes resource views or a Workbook.
- The reserved .220-.228 slice covers the AKS node + LoadBalancer-VIP IPs when we get there.

--------------------------------------------------------------------------------
## Recommendation / sequencing

1. Now: build the Phase-1 ARG dashboard (Tiles 1-3 work today) and share it read-only. That alone is a
   credible "cluster is up, here is what runs on it, with versions and health" funder view.
2. For the presentation: promote to an Azure Monitor Workbook (Option B) so IP/power/image and a clean
   layout are in one board.
3. Add Docker (Phase 2) and Kubernetes (Phase 3) tiles as those workloads land.

No custom application needed at any phase - everything is Azure-native (ARG, Azure Dashboards, Azure
Monitor Workbooks, Log Analytics). Custom (e.g. Managed Grafana) only if the funders want a branded NOC wall.

