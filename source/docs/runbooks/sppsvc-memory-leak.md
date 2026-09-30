---
title: "The sppsvc memory leak on Azure Local nodes"
domain: [platform]
layer: [cluster]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [memory, sppsvc, licensing, capacity, placement, leak]
updated: 2026-09-08
---

# The sppsvc memory leak on Azure Local nodes

`sppsvc`, the Windows Software Protection Platform service, grows without bound on these nodes. It
should hold tens of megabytes. On this cluster it reached 7.3 GB on a single node, and 19.2 GB
across four nodes, which was roughly 15 percent of all the memory in the cluster doing nothing.

This matters more than it sounds, because memory is the binding constraint on this hardware and
not storage. Read the capacity section before dismissing it.

## How it was found

Nodes were failing to start a 4 GB guest with `0x8007000E`, out of memory, on nodes that appeared
to have 5 GB free. The first assumption was that the Azure Local platform simply has a large
appetite. Measuring the idle node disproved that.

Node 04 was running **zero guests** and still had 19.2 GB of 31.5 GB in use. The process list
explained why:

```text
sppsvc                                                   7476 MB
Microsoft.AzureStack...HostModel.WinSvcHost              1088 MB
Microsoft.AzureStack...HostModel.WinSvcHost               853 MB
MonitoringPlatformAgent                                   390 MB
HciSvc                                                    376 MB
```

One licensing service was using more than the entire Azure Stack platform stack beneath it.

## The evidence that it is a leak

Consumption tracks uptime almost linearly, and resets on reboot. Measured 2026-09-08:

| Node | sppsvc | Uptime | Rate |
| --- | --- | --- | --- |
| AZL-NODE-01 | 1.89 GB | 10.9 days | 0.17 GB/day |
| AZL-NODE-02 | 5.26 GB | 41.1 days | 0.13 GB/day |
| AZL-NODE-04 | 7.30 GB | 42.1 days | 0.17 GB/day |
| AZL-NODE-06 | 4.81 GB | 43.0 days | 0.11 GB/day |

Node 01 is the control. It holds the least because it was rebooted 10.9 days earlier during the
retired NVMe recovery. The other three had been up around six weeks.

Call it **0.11 to 0.17 GB per node per day**. On a six week cycle that is 5 to 7 GB per node.

## The fix

`sppsvc` is trigger started and has **no dependent services**. Stop it, then touch the licensing
API to bring it back. Do not try to start it directly, because a direct start is often refused.

```powershell
Stop-Service sppsvc -Force
Start-Sleep -Seconds 6
# Any licensing query re-triggers the service.
Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" | Select-Object -First 1
```

Check activation before and after. It should be unchanged.

```powershell
Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
  Select-Object Name, LicenseStatus, GracePeriodRemaining
```

`LicenseStatus=1` means Licensed. `GracePeriodRemaining=0` on an activated node is correct and is
not a warning.

## Result, 2026-09-08

Run one node at a time and confirm cluster health between each.

| Node | Reclaimed | Free before | Free after | Guests |
| --- | --- | --- | --- | --- |
| AZL-NODE-04 | 7.3 GB | 12.3 GB | 19.6 GB | 0, unaffected |
| AZL-NODE-06 | 4.8 GB | 5.7 GB | 10.4 GB | 1, stayed running |
| AZL-NODE-02 | 5.3 GB | 5.4 GB | 10.7 GB | 1, stayed running |
| AZL-NODE-01 | 1.8 GB | 4.6 GB | 6.4 GB | 3, stayed running |

**19.2 GB reclaimed.** Cluster free memory went from 28.2 GB to 47.1 GB. No node left `Up`, no
virtual disk left `Healthy`, no guest restarted, and activation was unchanged on all four.

Nodes 02 and 06 roughly doubled their headroom, and those are the nodes where guest placement had
been failing.

## What this corrected about platform overhead

Before this was found, the idle footprint of Azure Local looked like about 20 GB per node. That
figure was wrong because it included the leak.

The honest number, measured on node 04 with no guests running and `sppsvc` freshly restarted, is
**11.9 GB of 31.5 GB**. Across nodes carrying guests the implied platform share lands in the same
region, roughly 12 to 13 GB.

That is still a real constraint. It is about **38 percent of a 32 GB node consumed before any
workload exists**, which leaves near 20 GB for guests. On a catalogued Azure Local server with 256
or 512 GB the same 12 GB is 2 to 5 percent and nobody notices. On 32 GB workstations it decides
what will fit.

## It will come back

Restarting the service does not fix the leak, it drains it. At 0.11 to 0.17 GB per node per day it
returns to several gigabytes within about six weeks.

Options, in order of preference:

- Check `sppsvc` whenever a guest fails to start with `0x8007000E`, before concluding the node is
  genuinely full.
- Add it to routine health checks alongside `Get-StorageJob`, since like a suspended repair it is
  silent and nothing alerts on it.
- A scheduled monthly service restart would hold it flat. It is a stop and a licensing query, and
  it does not interrupt guests.

Do not reboot a node purely to reclaim this. The service restart achieves the same thing with no
workload movement, and rebooting a node on this cluster has its own documented hazards. See
[node01-retired-nvme-recovery.md](node01-retired-nvme-recovery.md).

## Related

- [Windows Server 2025 demo quick reference](ws2025-azure-local-demo-quickref.md) records the
  `0x8007000E` placement failures this leak was contributing to, and the `Move-ClusterGroup`
  workaround for when a node genuinely is full.
