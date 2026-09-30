---
title: "SET versus LACP on storage ports"
domain: [network]
layer: [os, cluster]
type: reference
depth: guide
status: current
proof: proven
audience: [engineer, operator]
tags: [set, lacp, switch-embedded-teaming, storage-fabric, rdma, arista, vlan-711, vlan-712]
updated: 2026-08-14
---

# SET versus LACP on storage ports

Why link aggregation must not be configured on Azure Local storage ports. Written as a handout for
network engineers who are configuring the switch side.

## The incompatibility

Azure Local hosts team their NICs with Switch Embedded Teaming, which supports switch-independent
configuration only. Each NIC connects to a normal standalone switch port, and the host spreads
traffic in software by pinning each MAC address to one physical NIC.

LACP is the opposite model. It bundles ports into one logical link and requires the host to negotiate
the bundle with LACPDU frames. A SET host never sends those frames, so an LACP port stays suspended
and forwards nothing even though the link shows up at 100G.

That was the exact failure observed on this POC: link Up, ARP Incomplete, no traffic across VLAN 711.

A static LAG is no better. The switch would hash return traffic across both members while SET expects
each MAC on a single NIC, producing MAC flapping and broken RDMA. Storage makes this worse, because
SMB Direct and SMB Multichannel depend on the two NICs being separate paths on separate VLANs and
switches. A bundle collapses them into one.

## Target switch configuration

Remove all link aggregation from the storage ports. Leave each as a standalone trunk carrying its
single tagged storage VLAN.

| Setting | Value |
| --- | --- |
| Channel group | None. This is the critical one. |
| Mode | `switchport mode trunk` |
| Allowed VLAN | 711 on SW1, 712 on SW2 |
| MTU | 9214 |
| DCBX | `dcbx mode ieee` |
| Priority flow control | On, priority 3 no-drop |
| Spanning tree | `portfast edge` |

Network ATC on the host handles all teaming switch-independently.

## Source

[Host network requirements for Azure Local](https://learn.microsoft.com/en-us/azure/azure-local/concepts/host-network-requirements)

> "SET supports only switch-independent configuration"

> "SET is the only teaming technology supported by Azure Local"

## Related

- [Storage switch configuration](storage-switch-config.md)
