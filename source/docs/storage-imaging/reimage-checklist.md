---
title: "Node reimage checklist"
domain: [platform]
layer: [os, firmware]
type: runbook
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [reimage, azure-stack-hci-os, secure-boot, sconfig, winrm, arc-onboarding, install-media]
updated: 2026-06-24
---

# Node reimage checklist

Step-by-step for reimaging a node from ISO through to Arc onboarding.

The single most important rule is in here: do not run SConfig option 6 or Windows Update. Public
Windows Update pushes the node past the signed image recipe and causes a deployment failure that
takes rollup uninstalls to recover from.

That is not the same as never patching. Updates are the platform's job, after deployment and
hardware validation, through the Azure Local solution channel rather than the public one. See
[ADR 0009](../decisions/0009-node01-iso-recipe-lcu-skew.md) for the amendment and
`Get-SolutionUpdate` / `Start-SolutionUpdate` for the mechanism. Skipping updates at image time is
correct precisely because something else takes over.

## Reference content

```text
Azure Local POC - Local Admin BIOS and Configuration Checklist
Date: 2026-06-22

Scope
-----
- Node set: AZL-NODE-01 through AZL-NODE-06, as assigned by the platform team.
- This checklist applies to any node being prepared or reimaged.
- Goal: fix RAID/VROC storage presentation first, then clean Azure Stack HCI OS install.

BIOS check before OS install
----------------------------
- Boot mode: UEFI.
- Secure Boot: Enabled.
- TPM: Enabled.
- Intel Virtualization Technology / VT-x: Enabled.
- VT-d / IOMMU: Enabled.
- Execute Disable / XD bit: Enabled.
- sSATA operation: AHCI.
- tSATA operation: AHCI.
- NVMe mode: Non-RAID / plain NVMe. If BIOS does not use AHCI wording for NVMe, use Non-RAID.
- Intel VROC / VMD / RAID for the NVMe path: Disabled where BIOS exposes the option.
- Slot 6 bifurcation: x4/x4/x4/x4.

PCIe M.2 carrier and NVMe install
---------------------------------
- Power the node down before adding or reseating PCIe hardware.
- Do not use the returned ASUS Hyper M.2 X16 Gen 4 cards; the cooler stands proud of its own bracket and the lid will not close.
- Replacement card selected: RIITOP Quad PCIe NVMe Adapter, PCIe 4.0 x16 to 4Ports M.2 NVMe Converter Card, Amazon listing B0DPG4GLLX.
- Install the RIITOP replacement PCIe M.2 carrier card in the assigned PCIe slot.
- Use the bracket that matches the riser/chassis. The RIITOP package includes a half-height bracket.
- Confirm the chassis closes normally after the card is installed. Do not force the lid closed.
- The RIITOP card still requires PCIe bifurcation; verify actual riser/bracket/lid fit before treating it as accepted.
- If the assigned slot is Slot 6, it must stay bifurcated as x4/x4/x4/x4.
- Install the assigned KIOXIA KXG80ZNV512G 512 GB M.2 NVMe drives on the replacement carrier card.
- Use the carrier card's documented M.2 positions for a 2-drive install unless the local SOP says otherwise.
- Mellanox ConnectX-5 NICs remain in Slots 4 and 5.
- After install, boot back into BIOS and confirm the storage path is still Non-RAID/plain NVMe.

Important storage rule
----------------------
- Do not leave the main drive or data drives in RAID, VROC, RST, or VMD RAID mode.
- If the node was installed while storage was RAID/VROC, set the final Non-RAID BIOS state and reimage.

Official OS image source
------------------------
- Microsoft Learn: https://learn.microsoft.com/en-us/azure/azure-local/deploy/download-23h2-software
- Azure portal path: Azure portal > Azure Local > Get started > Download software.
- Select the recommended version in the portal. English is the only supported language for deployment.
- The portal download produces the ISO used to install Azure Stack HCI OS on each node.

OS install
----------
- Install Azure Stack HCI OS from the ISO downloaded from the Azure portal.
- Install after the BIOS storage settings above are already final.
- Keep the node name exactly as assigned:
  - AZL-NODE-01
  - AZL-NODE-02
  - AZL-NODE-03
  - AZL-NODE-04
  - AZL-NODE-05
  - AZL-NODE-06
- Keep the assigned static management IP for each node.
- Use the agreed local Administrator password.
- Do not join the domain. Azure Local deployment handles domain join later.

SConfig setup blocks
--------------------
- Domain/workgroup:
  - Workgroup: WORKGROUP
  - Domain: none
  - Do not join the domain during local setup.
- Computer name:
  - AZL-NODE-01
  - AZL-NODE-02
  - AZL-NODE-03
  - AZL-NODE-04
  - AZL-NODE-05
  - AZL-NODE-06
- Remote management:
  - Enabled
- Remote desktop:
  - Optional. Enable only if the site imaging SOP or platform team asks.
- Update setting:
  - Download only is acceptable during staging.
- Network settings:
  - Set only the connected management NIC to static once the correct NIC/IP is known.
  - If the correct NIC/IP is not known yet, disable DHCP on physical NICs and leave the node reachable by KVM until platform team confirms the mapping.
  - IP address: use the node-specific table below.
  - Subnet mask: 255.255.252.0
  - Prefix length: 22
  - Gateway: 10.10.1.1
  - Preferred DNS: 10.20.50.50
  - Alternate DNS: 10.20.10.50
  - DNS suffix: lab.example.com

Management network settings
---------------------------
- Subnet: 10.10.0.0/22
- Subnet mask: 255.255.252.0
- Gateway: 10.10.1.1
- DNS servers: 10.20.50.50 and 10.20.10.50
- DNS suffix: lab.example.com
- Static IP assignments:
  - AZL-NODE-01: 10.10.1.187
  - AZL-NODE-02: 10.10.1.188
  - AZL-NODE-03: 10.10.1.189
  - AZL-NODE-04: 10.10.1.190
  - AZL-NODE-05: 10.10.1.191
  - AZL-NODE-06: 10.10.1.192

Remote access expectation
-------------------------
- The platform team should reach nodes by FQDN, not by raw IP address.
- Expected FQDNs:
  - azl-node-01.lab.example.com
  - azl-node-02.lab.example.com
  - azl-node-03.lab.example.com
  - azl-node-04.lab.example.com
  - azl-node-05.lab.example.com
  - azl-node-06.lab.example.com
- Each FQDN should resolve to the static IP assignment above.
- WinRM should listen on TCP 5985 and respond to WSMan over the FQDN.
- Targets are workgroup joined, so remote credentials use SAM format:

  azl-node-01\Administrator

- Replace the node number for each host. Do not use bare Administrator from a remote workstation.
- Expected platform team-side checks from the DevBox:

  Resolve-DnsName azl-node-01.lab.example.com
  Test-NetConnection azl-node-01.lab.example.com -Port 5985
  Test-WSMan azl-node-01.lab.example.com -Authentication Negotiate -Credential (Get-Credential)

- Local node checks if FQDN WinRM fails:

  Test-WSMan localhost
  winrm enumerate winrm/config/listener
  Get-Service WinRM

Set static management IP
------------------------
- Run these commands in an elevated local PowerShell session on the node.
- First, identify the connected management NIC. Do not assume the same alias on every node.

  Get-NetAdapter | Sort-Object ifIndex | Format-Table ifIndex,Name,Status,LinkSpeed,InterfaceDescription,MacAddress -AutoSize

- If the correct management NIC or static IP is not known yet, do not leave physical NICs on DHCP. Use KVM access and disable DHCP on physical `Port*` adapters until the mapping is known. Do not change Remote NDIS or disconnected virtual adapters unless platform team asks.

  Get-NetAdapter | Where-Object { $_.Name -like 'Port*' } | ForEach-Object {
    Set-NetIPInterface -InterfaceAlias $_.Name -AddressFamily IPv4 -Dhcp Disabled
    Get-NetIPAddress -InterfaceAlias $_.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  }

- After platform team confirms which NIC is cabled for management, set the static IP on that one NIC.

- Set these two values for the node you are configuring. Example below is AZL-NODE-04.

  $InterfaceAlias = 'Port1'
  $IPAddress = '10.10.1.190'

- Apply the static IP, gateway, DNS servers, and DNS suffix.

  Set-NetIPInterface -InterfaceAlias $InterfaceAlias -Dhcp Disabled
  Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  Remove-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -PrefixLength 22 -DefaultGateway '10.10.1.1'
  Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses '10.20.50.50','10.20.10.50'
  Set-DnsClient -InterfaceAlias $InterfaceAlias -ConnectionSpecificSuffix 'lab.example.com'

- Quick local checks after applying the settings:

  Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
  Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
  Test-NetConnection 10.10.1.1

- Disable IPv4 DHCP on other connected physical NICs so the node does not ask the lab network for extra addresses. Do not include the management NIC alias in this list. Do not change Remote NDIS or disconnected virtual adapters unless the platform team asks.

  $NonManagementAliases = @('Port2','Port3','Port4')
  foreach ($Alias in $NonManagementAliases) {
    Set-NetIPInterface -InterfaceAlias $Alias -AddressFamily IPv4 -Dhcp Disabled
    Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '169.254.*' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  }

- Quick DHCP check after cleanup:

  Get-NetIPInterface -AddressFamily IPv4 | Sort-Object InterfaceIndex | Format-Table InterfaceIndex,InterfaceAlias,Dhcp,ConnectionState -AutoSize

- Live check before this handoff found AZL-NODE-04 using Port1 and AZL-NODE-06 using Port2, so choosing the correct connected NIC matters.

Initial OS setup
----------------
- Complete first boot and SCONFIG prompts.
- Confirm hostname is correct.
- Confirm management NIC has the assigned static IP, gateway, and DNS servers.
- Use the management network settings above.
- Enable Remote Management / WinRM.
- Enable RDP only if the site imaging SOP requires it for handoff.
- Leave the server in WORKGROUP.

Ideal Handoff criteria
----------------
- Node boots cleanly after reimage.
- Hostname and static IP match the assigned node.
- Remote Management / WinRM is enabled.
- The two added NVMe data drives are visible in Windows and are not configured as RAID.
- Data drives are left raw/poolable for platform team validation.
```
