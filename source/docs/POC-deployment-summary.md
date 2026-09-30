---
title: "Azure Local POC - Deployment Completion Summary"
domain: [platform]
layer: [cluster, arc]
type: evidence
status: current
proof: proven
audience: [leadership, engineer]
tags: [deployment, ece, 54-steps, 2h13m, milestone, storage-spaces-direct]
updated: 2026-07-27
---

# Azure Local POC - Deployment Completion Summary

Cluster: AZL-CLUSTER-01 (4 nodes: AZL-NODE-01, 02, 04, 06)
OS: Azure Local 24H2 (SKU 406, build 26100)
Domain: sim.example.internal (NetBIOS SIM)
Subscription: contoso-lab-sub (00000000-0000-0000-0000-000000000001)
Resource group: rg-azlocal-poc-001 | Arc region: southcentralus
Deployment completed: 2026-07-27 20:05 (build wall time ~2h13m, 17:52-20:05)
Final state: provisioningState=Succeeded, cluster status=ConnectedRecently,
Arc Resource Bridge (AZL-CLUSTER-01-arcbridge) + custom location (azl-cluster-01-cl) up.

Hardware note: nodes are Dell Precision 7960 Rack = WORKSTATION class. Dell does NOT
certify Windows Server or Azure Local on this model. The entire POC ran Azure Local on
hardware the OEM does not support for it, which is the source of much of the friction below.

--------------------------------------------------------------------------------
## Part 1 - The ECE deployment sequence (54 steps that ran on 2026-07-27)

The Azure Local deploy is driven by the Enterprise Cloud Engine (ECE). After a full
environment re-validation pass, it executed the following build steps. All completed with
status Success (or Skipped where noted).

Read that as scoped to this run. Within these 54 steps there were no failures and no retries.
That is not the same as saying the deployment never needed retrying. Getting to a clean pass
took repeated validation cycles and earlier attempts, and quoting "zero retries" without that
qualifier overstates what happened.

Phase A - Prep and agents (17:52 - 18:00, ~35 min; longest single step was 0.3 at ~27 min)
  0.1  Check and resolve requirements            Success
  0.2  Validate environment                      Skipped
  0.3  Resolve requirement                       Success (~27 min)
  0.4  Install OpenSSH Client                     Success
  0.5  Clean up after update                     Success (~10 min)
  0.6  Evaluate proxy configuration              Success
  0.7  Configure required proxy bypass list      Success
  0.8  Adjust the number of infrastructure VMs   Success
  0.9  Configure DNS (Local+KeyVault identity)   Success
  0.10 Set up certificates                       Success
  0.11 Reload certificate                        Success
  0.12 Full AgentLifecycleManager Deployment     Success (~10 min)
  0.13 Validate network settings for servers     Success
  0.14 Configure settings on servers             Success (~10 min)
  0.15 Set Azure cloud for AzureLocal            Success

Phase B - Cluster, network, storage (18:00 - 18:35)
  0.16 Create the cluster                        Success (~15 min)  <- failover cluster + domain join
  0.17 Configure networking                      Success (~6 min)   <- Network ATC: SET team + RDMA/RoCEv2/PFC
  0.18 Configure Cloud Management                Success
  0.19 Register with Azure                       Success
  0.20 Set up observability                      Success
  0.21 Unlock virtual disks                      Success
  0.22 Config storage                            Success (~6 min)   <- Storage Spaces Direct pool
  0.23 Repair key protectors                     Success
  0.24 Encrypt CSVs                              Success            <- BitLocker on cluster volumes
  0.25 Encrypt the OS volume                     Success            <- BitLocker on OS
  0.26 Set permissions on file share             Success
  0.27 Copy and prepare files                    Success
  0.28 Refresh Active Directory permissions      Success
  0.29 Set observability to listen mode          Success
  0.30 Install additional agents                 Success
  0.31 Create additional infrastructure subnets  Success
  0.32 Reserve IPs for the Arc infrastructure    Success            <- consumed the .200-.207 infra block
  0.33 Cluster the deployment orchestrator       Success
  0.34 Stage hardware updates via SBE            Success

Phase C - Security, Arc infrastructure (18:35 - 19:45)
  0.35 Apply security policies                   Success (~6 min)
  0.36 Install hardware updates via SBE          Success
  0.37 Reserve/migrate Network Controller REST IP Success
  0.38 Prepare to create infrastructure VMs      Success
  0.39 Verify Cluster DNS Resolution             Success
  0.40 Deploy Arc infrastructure components      Success (~64 min)  <- Arc Resource Bridge + MOC (heaviest step)

Phase D - Finalization (19:45 - 20:05)
  0.41 Log environment validation results        Success
  0.42 Send telemetry                            Success
  0.43 Turn on SMB encryption                    Success
  0.44 Migrate deployment orchestrator service   Success
  0.45 Create MAA endpoint                       Success
  0.46 Set up trusted launch for VMs             Success (~6 min)
  0.47 Create MAA policy                         Success
  0.48 Register the updates extension            Success
  0.49 Update ECE Proxy Configuration            Success
  0.50 Add custom cloud VMs to cluster           Success
  0.51 Configure custom cloud CLI tooling        Success
  0.52 Finalize security                         Success (~10 min)
  0.53 Finalize encryption                       Success
  0.54 Clean up temporary content               Success (~4 min)
  ==> provisioningState=Succeeded at 20:05:25

Raw data: out/_deploy-latest.json (full nested step tree).
Tooling: scripts/Invoke-Deploy.ps1 (trigger), scripts/_monitor-deploy2.ps1 (progress monitor
reading reportedProperties.deploymentStatus.steps).

--------------------------------------------------------------------------------
## Part 2 - Challenge log: what it took to get here

This POC was not a straight line. Each of the following was a distinct blocker that had to be
diagnosed and cleared, most of them on hardware the OEM does not certify for this OS.

1. Hardware and storage build-out
   - Dell Precision 7960 Rack is workstation class; no Dell support for Windows Server / Azure Local.
   - First storage card (ASUS Hyper M.2) rejected on mechanical fit - heatsink overhung the bracket,
     rack lid would not close. Switched to a generic quad-M.2 carrier.
   - Bifurcation on this board is x4/x4/x8 (not x4/x4/x4/x4); drives had to go in specific sockets.
   - Drives arrived read-only / not raw; needed diskpart clear-readonly + Update-StorageProviderCache
     -DiscoveryLevel Full before they showed CanPool=True.
   - RAM sits at 31.5 GB visible, just under the 32 GB floor - accepted as a validation risk.

2. Secure Boot / VBS seal saga
   - USB installer would not boot under Secure Boot, so a tech disabled Secure Boot to install; the OS
     then sealed VBS against Secure-Boot-off and could not be flipped on in place (0xc0430001).
   - Proven across nodes 03/05/06 that in-place enable is dead; only a clean install with Secure Boot
     on from first boot works. Required reimaging with FAT32 / virtual-media media.

3. OS image recipe / Windows Update contamination
   - SConfig "Install updates" pushed nodes past the signed OS image recipe (KB mismatch), which is
     explicitly forbidden for Azure Local and caused Arc bootstrap to fail.
   - Recovered by uninstalling the superseding rollups to surface the recipe LCUs, and for one node
     by downloading the exact catalog MSU. Clean-image-plus-skip-updates proven as the correct path.

4. NIC drivers and a card swap
   - Mellanox ports were disabled (Problem 22) and on inbox drivers; enabled + installed WinOF-2.
   - Broadcom management NIC ran a 2007 inbox driver; Azure Local rejects inbox drivers on intent NICs,
     so a Dell OEM Broadcom driver had to be pushed to all nodes.
   - Node02 had a Mellanox card with a different SUBSYS id; both cards were physically swapped from a
     donor node to make the pair symmetric.

5. Corporate security monitoring monitoring agent collision
   - The mandatory Observability extension could never start because the corporate security monitoring agent already
     held the single per-host monitoring agent (MA) slot. Resolved with the documented SkipSecurityMonitoringAgent tag plus
     removing the SecurityMonitoringAgent Arc extension, at resource/RG scope.

6. Active Directory dead end and domain pivot
   - Corporate AD blocked the deployment: an enforced deny-interactive-logon GPO caught the
     LCM service account, and corp policy disallows the block-inheritance the wizard requires.
   - Pivoted the entire deployment off corp AD to a lab domain (sim.example.internal) where we hold Domain
     Admin, created the OU + LCM account + delegated ACEs, and repointed the deployment settings.

7. The storage fabric (the headline, weeks long)
   - Storage validation returned 0/6 east-west connectivity, and it looked like a switch problem.
   - Isolated host vs switch with a direct DAC cable: host NICs, drivers, and VLAN tagging all proven good.
   - Discovered via host-side LLDP capture that the Windows adapter NAMES were reversed on three of four
     nodes relative to the switches (node02's card swap had changed PCI enumeration order). Network ATC
     binds VLAN to adapter name, so on those nodes it was tagging 711 onto ports physically wired to the
     712 switch, splitting the storage VLAN endpoints across two non-interconnected switches.
   - Fixed with a MAC-driven rename so Port3 is the SW1/711 port and Port4 the SW2/712 port on every node.
     No recabling - the physical cabling was correct all along; our naming assumption was wrong.
   - Also caught that switch SW2 was missing "switchport mode trunk" on the storage ports (access mode
     drops tagged frames); the network team added it.
   - Proved each fabric with tagged tests through the switches, then validation passed 0/6 -> full pass.

8. NTP
   - Post-fix validation then failed NTP because node01's time source was the local CMOS clock and the
     other nodes were split across two DCs. Pointed all four at one external NTP source; gate cleared.

9. Deployment
   - Full validation passed clean, deployment ran all 54 ECE steps with no failures, and the cluster
     came up Connected. The one step flagged as highest risk (Configure networking / PFC / RDMA) passed
     in six minutes.

--------------------------------------------------------------------------------
## Part 3 - Root cause, in one line

The storage fabric failure that stalled the project for weeks was not the switch and not the
hosts. It was reversed Windows NIC naming on three nodes (from a card swap changing PCI
enumeration) combined with one missing "switchport mode trunk" line on the second switch.
Both were found from the host side via LLDP and fixed without moving a single cable.

Full technical detail and command-by-command history: /memories/repo/azure-local-poc.md

