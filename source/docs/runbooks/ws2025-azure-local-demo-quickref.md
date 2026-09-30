---
title: "Windows Server 2025 Azure Local demonstration quick reference"
domain: [compute]
layer: [cluster, application]
type: runbook
depth: quickref
status: current
proof: proven
audience: [engineer, leadership]
tags: [windows-server-2025, demo, quick-reference, live-migration, failover]
updated: 2026-08-13
---

# Windows Server 2025 Azure Local demonstration quick reference

Use this guide to reproduce the validated Windows Server 2025 Datacenter: Azure Edition Core demonstration on `AZL-CLUSTER-01`.

This is a proof-of-concept capability demonstration, not a production operating procedure. It deliberately includes a planned live migration and a planned host reboot. Run the reboot section only when the test window accepts temporary workload interruption and storage repair activity.

## What this proves

- Azure Local can import a compatible Windows Server 2025 image from Azure Marketplace.
- A Windows Server 2025 Core VM can be deployed, Arc-managed, started, stopped, restarted, and live-migrated.
- The cluster recovers the VM after a controlled reboot of its current host.
- Storage remains online during the outage and returns to healthy after the node rejoins.

## Current validated configuration

| Item | Value |
|---|---|
| Cluster | `AZL-CLUSTER-01` |
| Resource group | `rg-azlocal-poc-001` |
| Custom location | `azl-cluster-01-cl` |
| Marketplace provider | `Microsoft.EdgeMarketplace` |
| Core gallery image | `ws2025-azure-edition-core` |
| Supported Marketplace source | `microsoftwindowsserver:windowsserver:2025-datacenter-azure-edition-core:26100.33158.260711` |
| Demonstration VM | `ws2025-core-01` |
| VM dashboard tags | `slot=ws2025-core-1`, `role=ws2025-core` |

Important: the compatible Azure Local Marketplace SKUs are Windows Server 2025 Datacenter: Azure Edition, not the regular `2025-datacenter` SKUs. The standard Azure Compute catalog can resolve the regular SKU, but Azure Local Edge Marketplace rejects it.

## 1. Preflight

Run from the repository root in a PowerShell terminal.

```powershell
az provider show -n Microsoft.EdgeMarketplace --query registrationState -o tsv
.scripts\Invoke-PocPimElevation.ps1 -Reason 'Azure Local WS2025 demonstration' -Hours 8
az stack-hci-vm image list -g rg-azlocal-poc-001 --query "[].{name:name,state:properties.provisioningState,os:properties.osType}" -o table
```

Expected:

- Provider state is `Registered`.
- Both Azure Local PIM roles report `ACTIVE`.
- `ws2025-azure-edition-core` is `Succeeded`.

If a write operation immediately returns `AuthorizationFailed` after PIM activation, wait 2-3 minutes and retry once. The Azure Stack HCI resource provider can lag the active PIM state.

## 2. Import the Windows Server 2025 Core Marketplace image

Skip this section if `ws2025-azure-edition-core` already shows `Succeeded`.

```powershell
az stack-hci-vm image create `
  --resource-group rg-azlocal-poc-001 `
  --custom-location /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-azlocal-poc-001/providers/Microsoft.ExtendedLocation/customLocations/azl-cluster-01-cl `
  --location southcentralus `
  --storage-path-id /subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-azlocal-poc-001/providers/Microsoft.AzureStackHCI/storageContainers/UserStorage3-3639d8fb1ffc48e6b67938d0d8a81729 `
  --name ws2025-azure-edition-core `
  --os-type Windows `
  --publisher microsoftwindowsserver `
  --offer windowsserver `
  --sku 2025-datacenter-azure-edition-core `
  --version 26100.33158.260711
```

Check progress:

```powershell
az stack-hci-vm image show -g rg-azlocal-poc-001 --name ws2025-azure-edition-core `
  --query "{state:properties.provisioningState,progress:properties.status.progressPercentage,error:properties.status.errorMessage}" -o json
```

Expected final result:

```text
state: Succeeded
progress: 100
error: ""
```

Observed on 2026-08-13: source version `26100.33158.260711`, download completed successfully, and the source image presented a 130,050 MB OS disk.

## 3. Create the Core demonstration VM

The script creates the Azure Local NIC, generates a break-glass password internally, stores it in Key Vault, creates the VM, and applies dashboard tags. Do not put passwords on the command line.

```powershell
.scripts\New-AzLocalTestVm.ps1 `
  -VmName ws2025-core-01 `
  -ImageName ws2025-azure-edition-core `
  -AdminUser azureuser `
  -Role ws2025-core `
  -Slot ws2025-core-1 `
  -EnableAgent
```

Expected:

```text
Name     Prov       Power    Host
-------  ---------  -------  --------------
default  Succeeded  Running  <cluster-node>
```

Observed on 2026-08-13: the VM initially ran on `azl-node-04`, used 4 vCPU and 4 GB memory, and the MOC guest agent connected successfully.

## 4. Verify Arc management and dashboard tags

```powershell
az resource show -g rg-azlocal-poc-001 -n ws2025-core-01 `
  --resource-type Microsoft.HybridCompute/machines `
  --query "{name:name,status:properties.status,os:properties.osSku,version:properties.osVersion,agent:properties.agentVersion,tags:tags}" -o json
```

Expected:

```text
status: Connected
os: Windows Server 2025 Datacenter Azure Edition
tags: role=ws2025-core, slot=ws2025-core-1
```

Refresh the Azure Local workbook after the Arc machine is connected. The VM should appear in the tenant-VM section under its `slot` and `role` tags.

## 5. Demonstrate lifecycle operations

```powershell
.scripts\Invoke-VmLifecycle.ps1 -VmName ws2025-core-01
```

Expected:

```text
start state: Running
power after stop: Stopped
power after start: Running
power after restart: Running
```

Observed on 2026-08-13: graceful stop, start, and restart all succeeded.

## 6. Demonstrate planned live migration

First list eligible VM roles and their current hosts:

```powershell
.scripts\Invoke-LiveMigrationTest.ps1 -ListOnly
```

Then move the VM to a different active node. Change `AZL-NODE-01` if the VM already runs there.

```powershell
.scripts\Invoke-LiveMigrationTest.ps1 `
  -VmRoleName ws2025-core-01 `
  -TargetNode AZL-NODE-01 `
  -Execute
```

Expected:

```text
Owner moved: <source-node> -> <target-node>
State: Online
```

Observed on 2026-08-13: `ws2025-core-01` moved from `AZL-NODE-04` to `AZL-NODE-01` and remained `Online`.

What happens: Hyper-V transfers the running VM's memory and device state to the target. The virtual disks remain on shared Azure Local Storage Spaces Direct storage, so the disk contents are not copied. Failover Clustering then changes VM ownership to the target host.

## 7. Demonstrate host-reboot resilience

Warning: this reboots a cluster node. It is a controlled resilience test, not a live migration. Put the VM on the chosen target node first, and run the script from a different connection node.

```powershell
.scripts\Invoke-NodeFailureTest.ps1 `
  -TargetNode AZL-NODE-01 `
  -TargetFqdn azl-node-01.lab.example.com `
  -ConnectNode azl-node-02.lab.example.com `
  -Mode Reboot `
  -Execute
```

Expected progression:

```text
AZL-NODE-01 = Down
pool: Warning
vdisks: Warning=<count>, but online
AZL-NODE-01 = Up (rejoined)
pool: Healthy
vdisks: Healthy=6
storage jobs idle
```

Expected VM verification:

```powershell
az stack-hci-vm show -g rg-azlocal-poc-001 --name ws2025-core-01 `
  --query "{state:properties.provisioningState,power:properties.status.powerState,host:properties.hostNodeName}" -o json
```

Expected final result: `Succeeded`, `Running`, and a surviving host node.

Observed on 2026-08-13:

- Node 01 went `Down` and later rejoined after approximately 26 minutes.
- Storage temporarily reported `Warning`; all six virtual disks returned to `Healthy`.
- `ws2025-core-01` recovered automatically as `Running` on `azl-node-02` with guest agent `Connected`.

## 8. Desktop Experience status

Corrected 2026-09-04. An earlier version of this section said the Desktop Experience image import
had failed and was pending cleanup. That was wrong, and it sent the reader after the wrong object.
There were two unrelated failures with similar names, and the image everyone actually wants is fine.

### The Desktop Experience image imported successfully

```text
ws2025-azure-edition-desktop   Succeeded   100%
```

Source URN, which is the correct one to use:

```text
microsoftwindowsserver:windowsserver:2025-datacenter-azure-edition:26100.33158.260711
```

Nothing is blocked on this image. A Desktop Experience VM can be created from it today.

### The failed image is a different one, from a malformed URN

```text
ws2025-datacenter-desktop   Failed
  GenerateTokenFromEdgeMarketplaceServiceFailed
  Failed to generate SAS token for the URN: MicrosoftWindowsServer:WindowsServer
  Status code: NotFound
```

The URN is publisher and offer only, with no SKU and no version, so the marketplace service had
nothing to resolve. This is a typo in the original request, not a cluster or connectivity fault.
Always pass the full four-part URN.

That failed image was deleted on 2026-09-04. Nothing referenced it, and the two working Windows
images were confirmed present first.

### The failed Desktop VM was the memory boundary, not the image

`ws2025-desktop-01` sat in `Failed` provisioning and never had a power state. The reason was not
the image:

```text
nodename = azl-node-06.sim.example.internal
Failed to start the Virtual Machine [ws2025-desktop-01-...]
Not enough memory in the system to start the virtual machine ws2025-desktop-01
with ram size 4096 megabytes
could not initialize memory: Not enough memory resources are available
to complete this operation. (0x8007000E)
```

Same error code, same 4 GB guest, and a different node than the `ws2025-core-01` case in section 9.
Node 06 runs the Arc Resource Bridge control plane and had 5.5 GB free. Three occurrences on two
nodes make this a property of the cluster: **the control plane starts a guest on the node that owns
it and fails rather than relocating to a node with capacity.**

To recreate a Desktop Experience VM, check free memory across the nodes first and target one with
real headroom, per the capacity check in section 9. The image is ready whenever that is wanted.

The failed VM was deleted on 2026-09-04. The old warning that cleanup requests time out did not
hold: the delete returned in 66.6 seconds. On the host side it left nothing behind. No cluster
role, no Hyper-V VM on any node, no VHD under `C:\ClusterStorage`, and the pool stayed Healthy with
six of six virtual disks Healthy.

```powershell
az stack-hci-vm delete -g rg-azlocal-poc-001 --name ws2025-desktop-01 --yes
```

Pass `--yes`. Without it the command waits on a confirmation prompt that never arrives when there
is no terminal attached, which is the likely origin of the reported timeout.

**Deleting the VM does not delete its network interface.** `ws2025-desktop-01-nic` survived as an
orphan in `Succeeded` state, which is easy to miss because it does not look like wreckage. Sweep
for NICs with no matching VM after any VM deletion:

```powershell
az stack-hci-vm network nic list -g rg-azlocal-poc-001 -o table
az stack-hci-vm network nic delete -g rg-azlocal-poc-001 --name <orphan> --yes
```

After cleanup on 2026-09-04 the resource group held six images all `Succeeded`, two NICs matching
the two running VMs, and no resource in `Failed` state.

## 9. Planned node drain, and the placement boundary

Tested 2026-09-04. This is the section to read if someone asks whether Windows Server survives
maintenance on this cluster. The short answer is yes, and the constraint is memory, not Windows.

### Placement will fail before it will relocate

Starting `ws2025-core-01` failed on its owning node with the guest never leaving `Stopped`:

```text
nodename = AZL-NODE-02
Not enough memory in the system to start the virtual machine ws2025-core-01
with ram size 4096 megabytes
'ws2025-core-01' could not initialize memory (0x8007000E)
```

Node 02 had 5.0 GB free and the guest asks for 4 GB, so it fits on paper. Hyper-V needs headroom
above the guest allocation, so it does not.

The important part is what did not happen. **The control plane tried the owning node and stopped.
It did not look for a node with capacity.** The fix is to move the cluster group first, then start:

```powershell
Move-ClusterGroup -Name ws2025-core-01 -Node AZL-NODE-01
az stack-hci-vm start -g rg-azlocal-poc-001 --name ws2025-core-01
```

This is the same `0x8007000E` that stopped `ws2025-azure-edition-desktop` on node 06. One failure
looked like a one-off. Two on different nodes is a property of the cluster.

Check free memory on every node before starting or failing over a Windows guest:

```powershell
Invoke-Command -ComputerName azl-node-01.lab.example.com,azl-node-02.lab.example.com,
  azl-node-04.lab.example.com,azl-node-06.lab.example.com -Credential $cred -Authentication Negotiate `
  -ScriptBlock { $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{ Node = $env:COMPUTERNAME
      FreeGB = [math]::Round($os.FreePhysicalMemory/1MB,1) } }
```

Measured 2026-09-04: node 01 14.1 GB free, node 04 9.0 GB, node 06 5.5 GB, node 02 5.0 GB. Nodes 02
and 06 hold the AKS and Arc control planes and are effectively full.

### Live migration

`ws2025-core-01` moved AZL-NODE-01 to AZL-NODE-04 in **16.4 seconds**, role stayed `Online`.

```text
Microsoft-Windows-Hyper-V-VMMS-Admin  id=20418
  successfully completed the live migration of virtual machine 'ws2025-core-01'
```

No `18502` power-off and no `18504` reset in the Hyper-V-Worker log, and all six integration
services stayed OK. That is the proof the guest did not reboot.

Do not use `(Get-VM).Uptime` as the continuity check. **That counter resets on the destination host**
because the worker process there is new, so a successful live migration looks like a restart. Read
the VMMS event and the absence of power transitions instead.

The destination also logged, which is a memory pressure signal rather than an error:

```text
id=3054  successfully allocated memory, but a subset of the physical pages
         was allocated on a remote NUMA node
```

### Planned drain

```powershell
Suspend-ClusterNode -Name AZL-NODE-04 -Drain -Wait
```

| Step | Result |
|---|---|
| Drain duration | 34.8 seconds |
| Node state | `Paused` |
| Groups left on the node | 0 |
| `rocky-docker-01` | moved to node 01, stayed `Online` |
| `ws2025-core-01` | moved to node 01, stayed `Online` |
| Pool during pause | `Healthy` / `OK` |
| Virtual disks during pause | 5 of 6 `Warning`, all online |

Both guests evacuated with no interruption. Degraded-but-online virtual disks are the expected
state while a node is paused, not a fault.

### Resume, and the suspended repair jobs

```powershell
Resume-ClusterNode -Name AZL-NODE-04
```

Immediately after resume, five repair jobs appeared as `Suspended` at `0%`. That is alarming if you
have read [node01-retired-nvme-recovery.md](node01-retired-nvme-recovery.md), where the same state
persisted for ten days. **It is not the same thing.** Here it cleared without intervention:

```text
t+30s   vdisks Healthy=5 Warning=1   jobs Suspended:0%
t+60s   vdisks Healthy=6             no jobs
```

A planned drain resyncs in about a minute. Suspended at zero is only worth escalating if it is
still there after several minutes, and the drive-failure case is a different problem.

## 10. Current status summary

| Capability | Core result |
|---|---|
| Marketplace image import | Passed |
| VM create | Passed |
| Arc guest management | Passed |
| Dashboard tags | Passed |
| Graceful lifecycle | Passed |
| Live migration | Passed, re-confirmed 2026-09-04 |
| Current-host reboot and failover | Passed |
| Planned node drain and resume | Passed 2026-09-04 |
| Start on a memory-constrained node | Fails `0x8007000E`, move the group first |
| Desktop Experience image import | Passed, `ws2025-azure-edition-desktop` |
| Desktop Experience VM | Deleted 2026-09-04, failed on node 06 memory, recreate when wanted |

## 11. Demo safety rules

- Never reboot the same node used as `-ConnectNode`.
- Run `-ListOnly` or a dry run first whenever the current VM owner is uncertain.
- Do not migrate or reboot Azure Resource Bridge/control-plane VM roles for the demonstration.
- Do not hard-power-off a node without a person present at the iDRAC console.
- Wait for `Get-StorageJob` to return idle and all virtual disks to report Healthy before the next disruptive test.
