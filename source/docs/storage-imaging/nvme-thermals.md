---
title: "NVMe temperatures on the RIITOP carrier: what they are and how to read them"
domain: [storage]
layer: [hardware]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [nvme, thermals, temperature, riitop, carrier-card, storage-spaces-direct, smart]
updated: 2026-09-03
---

# NVMe temperatures on the RIITOP carrier: what they are and how to read them

## Why this was measured

[ADR 0003](../decisions/0003-storage-spec-lock.md) selected the ASUS Hyper M.2 X16 Gen 4 partly
because it "ships with active fan + per-slot heatsinks so we are not improvising thermals".
[ADR 0008](../decisions/0008-asus-card-mechanical-incompatibility.md) then replaced it with the
RIITOP quad carrier for a purely mechanical reason, because the ASUS cooler stood proud of its own
bracket and the rack lid would not close.

The RIITOP has heatsinks but no fan. That trade was made for fit, not for cooling, and nobody
measured what it cost. This page is the measurement.

## The finding

Read 2026-09-03 with the cluster running its normal light load. Full capture in
[nvme-thermals-20260903.csv](nvme-thermals-20260903.csv).

| Node | Slot (PCI bus) | Model | Temp C |
| --- | --- | --- | --- |
| AZL-NODE-01 | 181 | Samsung PM9A1 512GB | 34 |
| AZL-NODE-01 | 182 | Samsung PM9A1 512GB | 35 |
| AZL-NODE-02 | 180 | Samsung PM9A1 512GB | 36 |
| AZL-NODE-02 | 181 | Samsung PM9A1 512GB | 41 |
| AZL-NODE-02 | 182 | Samsung PM9A1 512GB | 39 |
| AZL-NODE-04 | 180 | Samsung PM9A1 512GB | 35 |
| AZL-NODE-04 | 181 | Samsung PM9A1 512GB | 39 |
| AZL-NODE-04 | 182 | Samsung PM9A1 512GB | 38 |
| AZL-NODE-06 | 180 | KIOXIA KXG80ZNV512G | 36 |
| AZL-NODE-06 | 181 | KIOXIA KXG80ZNV512G | 42 |
| AZL-NODE-06 | 182 | KIOXIA KXG80ZNV512G | 42 |

Every drive reports a rated ceiling of 83 C through `TemperatureMax`. The hottest drive in the
cluster sits 41 C below that. The passive carrier is adequate for this workload.

Node 01 shows two data drives rather than three. That is the retired NVMe, covered in
[node01-retired-nvme-recovery.md](../runbooks/node01-retired-nvme-recovery.md).

Node 06 runs KIOXIA where the others run Samsung. [ADR 0011](../decisions/0011-three-data-disks-per-node.md)
allows this, because the spec is capacity and media rather than vendor.

## There is a slot gradient

Averaged across nodes, the three M.2 positions on the carrier do not cool equally.

| Slot (PCI bus) | Drives | Min C | Avg C | Max C |
| --- | --- | --- | --- | --- |
| 180 | 3 | 35 | 35.7 | 36 |
| 181 | 4 | 34 | 39.0 | 42 |
| 182 | 4 | 35 | 38.5 | 42 |

Slot 180 runs three to four degrees cooler than the other two, consistently, on every node. With no
fan on the card that is the expected shape. The gradient is small enough not to matter at these
absolute temperatures, but it is the number to watch if the cluster ever takes a sustained write
workload.

## The failed drive was in the coolest slot

The NVMe that died in node 01 was on PCI bus 180, recorded as `Error width=x2 PCI bus 180` in the
recovery runbook. Bus 180 is the coolest position on the carrier.

ADR 0011 had already noted that node 01 had "one of the two data drives trained at PCIe x2 instead
of x4", and called it "a marginal seat". The failure presented as a link width drop, in the best
cooled slot. Heat does not explain it. Seating does.

## What this does not cover

- A single point sample, not a time series. It says nothing about behaviour over a day.
- The cluster was under light load. This is not a stress test.
- No lifetime maximum and no throttle history. See the SMART limitation below for why.
- No chassis inlet or ambient reading. The lab iDRACs are unlicensed, so the usual sensor path is
  not available.

To answer "are they hot all the time" properly, sample on a timer or drive a sustained write and
watch where they settle.

## How to read it

### The quick way

Run on any one cluster node. `Get-PhysicalDisk` is cluster wide on Storage Spaces Direct, so a
single node returns every drive in the cluster.

```powershell
Get-PhysicalDisk | Where-Object BusType -eq 'NVMe' | ForEach-Object {
  [pscustomobject]@{
    Node  = ((($_ | Get-StorageNode -PhysicallyConnected).Name) -split '\.')[0]
    Id    = $_.DeviceId
    Slot  = if ($_.PhysicalLocation -match 'Bus (\d+)') { $Matches[1] } else { '' }
    Model = $_.FriendlyName
    TempC = ($_ | Get-StorageReliabilityCounter).Temperature
  }
} | Sort-Object Node, Slot | Format-Table -Auto
```

### The full way

```powershell
.\scripts\Get-NvmeThermals.ps1
.\scripts\Get-NvmeThermals.ps1 -Csv .\docs\storage-imaging\nvme-thermals-20260903.csv
```

Connects with `sim\labadmin` per [credential-map.md](../access/credential-map.md), stops at the
first node that answers, and adds the per slot and per node rollups.

## Four traps, all of which produced convincing wrong answers

Recorded because each one returns plausible numbers rather than an error.

**The SMART throttle counters are at offsets 192 and 196.** Warning Composite Temperature Time and
Critical Composite Temperature Time sit at bytes 192 to 195 and 196 to 199 of NVMe log page 0x02.
Byte 128 is Power On Hours. Reading 128 and 132 as the throttle counters reports every drive as
having throttled for thousands of minutes, which is really just uptime.

**`Get-Disk` returns clustered virtual disks too.** `UserStorage_1` through `4`,
`Infrastructure_1` and `ClusterPerformanceHistory` appear alongside real hardware. They have no
temperature, and their blank disk numbers collide on any join keyed to disk number, which silently
copies one real drive's reading onto all of them.

**Pool members have no `\\.\PhysicalDriveN` path.** Storage Spaces claims them, so
`Get-CimInstance Win32_DiskDrive` on node 01 lists only `PHYSICALDRIVE0` and `PHYSICALDRIVE3`. Any
`DeviceIoControl` approach, including `IOCTL_STORAGE_QUERY_PROPERTY` for the raw SMART log, cannot
reach a pooled drive. That is why written bytes, wear percentage and throttle history are not
available for the data disks, and only the boot drive answers.

**Node attribution runs disk to node, not node to disk.** Piping a storage node into
`Get-PhysicalDisk` returns only the boot drive, and adding `-PhysicallyConnected` to that pipeline
does not change it. The association that works is the reverse:

```powershell
$disk | Get-StorageNode -PhysicallyConnected
```

Without it, every node reports all twelve cluster drives under the same identifiers and the data
looks four times larger than it is.

## What is trustworthy here

`Get-StorageReliabilityCounter` is proxied cluster wide by Storage Spaces Direct and returns a real
per drive temperature for pooled disks. Temperature, slot position from `PhysicalLocation`, and the
rated ceiling are sound. Everything sourced from the raw SMART log applies to the boot drive only.
