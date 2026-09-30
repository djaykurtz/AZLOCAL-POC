---
title: "Storage switch + port config - confirmed state"
domain: [network]
layer: [hardware]
type: reference
depth: quickref
status: current
proof: proven
audience: [engineer, operator]
tags: [arista, switch-config, vlan-711, vlan-712, trunk, pfc, storage-fabric]
updated: 2026-07-20
---

# Storage switch + port config - confirmed state

Last updated: 2026-07-20

Authoritative record of the top-of-rack storage network config for the
Azure Local POC. Ports confirmed from live `show run int` and `show int trunk`
on the switches. See STATUS.md for overall status.

## Switches
- SW1 = stor-sw-01 (Arista 7050) -> storage fabric A, VLAN 711
- SW2 = stor-sw-02 (Arista 7050) -> storage fabric B, VLAN 712

## Port map (same interface number on both switches)
Interface `/1` = the port on that switch. Match by MAC if unsure.

| Node | Interface (SW1 and SW2) | SW1 VLAN | SW2 VLAN | Port3 MAC (SW1) | Port4 MAC (SW2) |
|------|-------------------------|----------|----------|-----------------|-----------------|
| 01 | Ethernet9/1  | 711 | 712 | 00-00-5E-00-53-01 | 00-00-5E-00-53-06 |
| 02 | Ethernet10/1 | 711 | 712 | 00-00-5E-00-53-02 | 00-00-5E-00-53-05 |
| 03 | Ethernet11/1 | 711 | 712 | 00-00-5E-00-53-0F | 00-00-5E-00-53-11 |
| 04 | Ethernet12/1 | 711 | 712 | 00-00-5E-00-53-08 | 00-00-5E-00-53-07 |
| 05 | Ethernet13/1 | 711 | 712 | (offline)         | (offline)         |
| 06 | Ethernet14/1 | 711 | 712 | 00-00-5E-00-53-0A | 00-00-5E-00-53-09 |

## Confirmed-correct per-port config (from live show run)

SW1 storage ports (Ethernet9/1 - Ethernet14/1):
```
interface EthernetN/1
   description azl-node-0X
   mtu 9214
   dcbx mode ieee
   switchport trunk allowed vlan 711
   switchport mode trunk
   priority-flow-control on
   priority-flow-control priority 3 no-drop
   spanning-tree portfast edge
```

SW2 storage ports (Ethernet9/1 - Ethernet14/1): identical except
`switchport trunk allowed vlan 712`.

Rules baked in (all confirmed present/correct):
- NO channel-group / LACP on storage ports (SET is switch-independent; verified
  via host packet capture: LACPDUs went from ~70 to 0 after removal).
- NO native storage VLAN. Native = default VLAN 1. Storage VLAN carried TAGGED.
  (Setting native 711/712 breaks tagged delivery - proven.)
- mtu 9214 on the storage switch ports.
- PFC priority 3 no-drop, dcbx mode ieee, portfast edge.

## Operational state confirmed (show int trunk, SW1)
All ports Et9/1-14/1: Status=trunking, Native vlan=1, Vlans allowed=711,
"Vlans allowed and active in management domain"=711, "Vlans in spanning tree
forwarding state"=711. So VLAN 711 is created, active, and forwarding.

## Required global config (verify present)
```
vlan 711     ! on SW1
vlan 712     ! on SW2
```
A trunk forwards a VLAN only if it is both allowed on the port AND active in the
VLAN database. `show int trunk` shows 711 active, so `vlan 711` exists on SW1.

## Current state (measured 2026-08-31)

Tagged VLAN 711 and 712 both carry storage traffic. The section below it recorded a fault that was
open on 2026-07-20 and is now closed. It is kept as history, not as current state.

Measured on all four cluster nodes:

- Port3 on VLAN 711, Port4 on VLAN 712.
- Network ATC intents `compute_management` and `storage` both report Success and Completed.
- Host MTU is 1500 and `*JumboPacket` is 1514. Jumbo frames are not enabled on the hosts even
  though the switch ports are set to 9214. That is an open performance question, not a fault.

Switch side configuration was last confirmed 2026-07-17. The hosts return `Not Available` for every
DCBX Remote field, so there is no switch side confirmation available from the host. Re-run
`scripts/_lldp-cabling-map.ps1` if cabling or switch configuration changes.

## History: tagged VLAN validation (opened 2026-07-20, closed by the 2026-07-27 deployment)

Port config was correct, but end-to-end TAGGED VLAN 711 had not yet passed:
- Untagged (native 711 era): PASSED - proves cabling, links, L2, jumbo all work.
- Tagged 711: FAILS via BOTH the physical-adapter VlanID method AND the proper
  Hyper-V vSwitch + Set-VMNetworkAdapterVlan -Access method (real 802.1Q).
- Next diagnostic: `show mac address-table vlan 711` on SW1 while tagged traffic
  flows. If host MACs (98-03-9B-*) appear on VLAN 711 -> switch forwarding issue;
  if absent -> host/Mellanox VLAN handling issue.
Tools: scripts/Test-StorageFabricTagged.ps1 (valid 802.1Q test),
scripts/Test-StorageFabric.ps1 (physical-property; not valid for tagged),
scripts/Test-SlowProtoFrames.ps1 (LACP/LLDP capture).

