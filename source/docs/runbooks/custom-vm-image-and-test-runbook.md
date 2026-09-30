---
title: "Runbook: custom VM image + VM battery on Azure Local (path B)"
domain: [compute]
layer: [cluster, application]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [vm-image, gallery-image, qemu-img, vhdx, lifecycle, cloud-init]
updated: 2026-07-29
---

# Runbook: custom VM image + VM battery on Azure Local (path B)

Audience: a human who wants to repeat this by hand. Every step lists the exact command, what it does,
and what you should see. Cluster: AZL-CLUSTER-01. Resource group: rg-azlocal-poc-001.

This is the "path B" workflow: bring your own disk image (no Azure Marketplace), register it as a gallery
image, boot a VM from it, then run the lifecycle / live-migration / node-outage battery.

--------------------------------------------------------------------------------
## 0. What the tools are (with docs)

- qemu-img - converts disk images between formats (qcow2, vhd, vhdx). It is the only tool that reads the
  qcow2 cloud images the distros publish. Docs: https://www.qemu.org/docs/master/tools/qemu-img.html
  We use a standalone Windows build so nothing is installed system-wide:
  https://cloudbase.it/qemu-img-windows/
- CirrOS - a tiny (~20 MB) test Linux used to smoke-test a cloud/hypervisor. Boots in seconds, no real
  package manager. Good for "does VM create/migrate/reboot work". https://download.cirros-cloud.net/
- Rocky Linux cloud images - a real RHEL-compatible distro. GenericCloud qcow2 is the standard KVM/Hyper-V
  cloud image; it has cloud-init and Hyper-V integration services. https://download.rockylinux.org/pub/rocky/
- az stack-hci-vm - the Azure CLI extension that drives Azure Local VMs, images, NICs, logical networks.
  Docs: https://learn.microsoft.com/en-us/cli/azure/stack-hci-vm
- Azure Local custom VM images (concept): https://learn.microsoft.com/en-us/azure/azure-local/manage/virtual-machine-image-storage-account

Rule: do NOT install tooling on the Azure Local host nodes (locked appliance OS). Convert on the DevBox;
only the finished VHDX is copied to the cluster.

--------------------------------------------------------------------------------
## 1. Prerequisites (once per session)

1. Azure login + correct subscription:
   az account show    # should be contoso-lab-sub
2. PIM active (roles expire after 8 h; re-run when you get AuthorizationFailed on AzureStackHCI/*/write):
   .\scripts\Invoke-PocPimElevation.ps1
   Expect: "Azure Stack HCI Administrator ... ACTIVE" and "User Access Administrator ... ACTIVE".
3. The stack-hci-vm CLI extension is installed (auto-installs on first use).
4. WinRM to the cluster works: domain-admin cred sim\labadmin at .creds\sim-example-internal-admin.cred,
   connecting to the lab.example.com node names (they resolve and are in TrustedHosts).

--------------------------------------------------------------------------------
## 2. Stage a custom image  ->  gallery image

One reusable script does download -> convert -> copy-to-CSV -> create. It auto-handles .qcow2/.img
(qemu-img), .vhd (Convert-VHD), .vhdx (as-is), and .xz (decompress first).

CirrOS (tiny test image):
    .\scripts\New-AzLocalGalleryImage.ps1 -Name cirros-064 -OsType Linux `
        -SourceUrl 'https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img'

Rocky Linux 10.2 (real distro):
    .\scripts\New-AzLocalGalleryImage.ps1 -Name rocky-10-2 -OsType Linux `
        -SourceUrl 'https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'

What happens, in order (you will see these lines):
  Downloading ...                         # to out\img\ on the DevBox
  qemu-img convert -> .vhdx ...           # qcow2 -> dynamic VHDX on the DevBox
  Copying VHDX to C:\ClusterStorage\...   # over WinRM to a cluster CSV (large images take minutes)
  Creating gallery image <name> ...
Expect at the end:
  Name        Prov
  ----------  ---------
  <name>      Succeeded

Manual equivalent of the last step (if you ever want to run it yourself), note --image-path is a path
ON the cluster:
    az stack-hci-vm image create -g rg-azlocal-poc-001 `
        --custom-location <custom-location-id> --location southcentralus `
        --name rocky-10-2 --os-type Linux `
        --image-path 'C:\ClusterStorage\UserStorage_1\images\rocky-10-2.vhdx'

To repeat with ANY other image: change -Name and -SourceUrl. Local file instead of URL: use -SourcePath.

--------------------------------------------------------------------------------
## 3. Create a VM from the image

Needs a logical network with a free static IP pool. We use AZL-CLUSTER-01-TenantLNET (pool
10.10.1.240-.243, above the reserved infra block). Create it once (already exists):
    .\scripts\_pathb-create-lnet.ps1

Create the VM (also creates its NIC):
    .\scripts\New-AzLocalTestVm.ps1 -VmName rocky-testvm-01 -ImageName rocky-10-2
Expect:
  Creating NIC rocky-testvm-01-nic ...
  Creating VM rocky-testvm-01 ...
  Name     Prov       Power    Host
  -------  ---------  -------  --------------
  default  Succeeded  Running  azl-node-01

Notes:
- Password auth is used just to satisfy create; for a real login pass -SshKeyPath <pubkey>.
- --enable-agent false: the in-guest Arc agent is not provisioned (fine for lifecycle tests).

--------------------------------------------------------------------------------
## 4. Lifecycle: stop / start / restart

    .\scripts\Invoke-VmLifecycle.ps1 -VmName rocky-testvm-01
Expect: Running -> Stopped -> Running -> Running, all Succeeded.

Gotcha it handles for you: a graceful `stop` signals the guest to shut down. CirrOS has no integration
services, so its stop fails with 0x800710DF and the script retries with `--skip-shutdown` (hard power-off).
Rocky HAS integration services, so its graceful stop just works.

--------------------------------------------------------------------------------
## 5. Live migration (move a running VM between nodes)

    .\scripts\Invoke-LiveMigrationTest.ps1 -VmRoleName rocky-testvm-01 -TargetNode AZL-NODE-02 -Execute
Expect: "Owner moved: AZL-NODE-01 -> AZL-NODE-02", State Online the whole time. This rides the RDMA
storage/migration network, so it also exercises that fabric.
Tip: run with -ListOnly first to see the exact VM role names and current owners.

--------------------------------------------------------------------------------
## 6. Outage test (simple node reboot)

Two flavors, both via the same script:

a) Pure storage replication - reboot a node that does NOT host the VM:
    .\scripts\Invoke-NodeFailureTest.ps1 -Mode Reboot -TargetNode AZL-NODE-04 `
        -TargetFqdn azl-node-04.lab.example.com -Execute

b) VM failover under host outage - reboot the node that DOES host the VM (VM restarts on a survivor):
    .\scripts\Invoke-NodeFailureTest.ps1 -Mode Reboot -TargetNode AZL-NODE-02 `
        -TargetFqdn azl-node-02.lab.example.com -ConnectNode azl-node-01.lab.example.com -Execute

Always poll from a node you are NOT rebooting (-ConnectNode). What you see:
  baseline health (4 nodes Up, pool Healthy, 6 vdisks Healthy)
  node goes Down -> pool Warning, vdisks Degraded but Online (3-way mirror tolerates one node)
  node rejoins -> storage resync runs -> back to Healthy, jobs idle   (~5 min total)
Then confirm the VM:
    az stack-hci-vm show --name rocky-testvm-01 -g rg-azlocal-poc-001 --query "properties.status.powerState" -o tsv
Expect: Running.

Dry-run first (no -Execute) to see the plan. The HARD power-off (Stage 2) is intentionally never automated;
do that only with a human at the iDRAC.

--------------------------------------------------------------------------------
## 7. Teardown (when done)

    az stack-hci-vm delete --name rocky-testvm-01 -g rg-azlocal-poc-001 --yes
    az stack-hci-vm network nic delete --name rocky-testvm-01-nic -g rg-azlocal-poc-001 --yes
The gallery image and the CSV VHDX can stay (reusable). To remove the image:
    az stack-hci-vm image delete --name rocky-10-2 -g rg-azlocal-poc-001 --yes

--------------------------------------------------------------------------------
## 8. Gotchas learned (so you do not rediscover them)

- PIM expires after 8 h. Symptom: AuthorizationFailed on Microsoft.AzureStackHCI/*/write. Fix: re-run
  Invoke-PocPimElevation.ps1. Right after activation there can be ~1 min of RBAC propagation lag; a retry
  clears it.
- az.cmd cannot parse the vmSwitchName "ConvergedSwitch(compute_management)" (parentheses break the batch
  wrapper). All scripts call the CLI Python entrypoint instead:
  $py = Join-Path (Split-Path (Split-Path (Get-Command az).Source)) 'python.exe'; & $py -m azure.cli <args>
- This CLI version wants a pre-created NIC (--nics <name>), not inline --network-arguments.
- Sizing: this CLI exposes only --size (we use Default = 4 vCPU / 4 GB), not --memory-mb/--processors.
- Omit --os-type on create when the gallery image already carries it.
- ICMP is blocked DevBox->subnet, so do not trust ping as a reachability test; use owner-change + power
  state as proof.
- Do not install tooling on the host nodes; convert on the DevBox.

--------------------------------------------------------------------------------
## 9. What we actually observed (2026-07-28/29)

| image       | source                         | create | lifecycle                    | live migration        | node-reboot outage                          |
|-------------|--------------------------------|--------|------------------------------|-----------------------|---------------------------------------------|
| cirros-064  | CirrOS 0.6.2 qcow2 (~20 MB)    | Running (node06, Gen2) | stop needed --skip-shutdown  | node06 -> node01 Online | node04 reboot: resync degraded->Healthy ~5m |
| rocky-10-2  | Rocky 10.2 GenericCloud qcow2  | Running (node01, Gen2) | graceful stop worked         | node01 -> node02 Online | node02 (its host) reboot: VM failed over, Running; resync ->Healthy 4.9m |

Reusable scripts: New-AzLocalGalleryImage.ps1, New-AzLocalTestVm.ps1, Invoke-VmLifecycle.ps1,
Invoke-LiveMigrationTest.ps1, Invoke-NodeFailureTest.ps1, _pathb-create-lnet.ps1.

