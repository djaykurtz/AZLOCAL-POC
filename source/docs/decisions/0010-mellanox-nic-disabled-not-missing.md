---
title: "0010 - NetAdapter CRITICAL failure was disabled Mellanox NICs, not missing/uncabled hardware"
domain: [network]
layer: [hardware]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, mellanox, connectx-5, pnp, disabled-device]
updated: 2026-07-10
---

# 0010 - NetAdapter CRITICAL failure was disabled Mellanox NICs, not missing/uncabled hardware

- **Status**: Active
- **Date**: 2026-07-10
- **Owner**: labadmin
- **Revisit when**:
  - The deployment wizard rejects the inbox Mellanox driver (would force the
    WinOF-2 swap tracked below to become a hard prerequisite), OR
  - A node re-images and the Mellanox ports come back disabled again (re-run
    the enable step as part of the network pre-flight gate).

## Observe

- `Invoke-AzStackHciHardwareValidation -PassThru` on node 01 returned the single
  CRITICAL failure `AzStackHci_Hardware_Test_NetAdapter`. The validator's NIC
  gate filter (read from the module at runtime) is:
  `NdisMedium -eq 0 -and Status -eq 'Up' -and NdisPhysicalMedium -eq 14 -and PnPDeviceID -notlike 'USB\*'`.
- The two Mellanox ConnectX-5 100GbE cards (PCI `VEN_15B3&DEV_1017`, Slots 4/5)
  did **not** appear as `NetAdapter` objects. Initial assumption (recorded in the
  earlier risk register and in ADR-adjacent notes) was "driver not installed
  and/or not cabled" -> which fed a DAC-cable procurement scramble.
- `Get-PnpDevice` for the Mellanox devices actually showed `Status=Error` with
  **Problem code 22 = administratively DISABLED**. The devices were present and
  bound, just disabled.
- `Enable-PnpDevice -InstanceId <id> -Confirm:$false` per device (no driver
  install, no reboot, no cabling change) brought both ports back:
  - PnP Problem code -> 0
  - enumerate as `Port3` / `Port4`, `Status=Up`, `LinkSpeed=100 Gbps`
  - `NdisMedium=0`, `NdisPhysicalMedium=14`, `MediaConnectionState=Connected`
- `MediaConnectionState=Connected` at 100 Gbps means the ports were **already
  cabled** to something - the "not plugged in" assumption was wrong for node 01.
- After enable, node 01 dropped from 2 hardware failures to 1 (GPU WARNING only);
  the CRITICAL NetAdapter gate PASSES. Reproduced on node 02 (2 NICs pass the gate).
- The enabled ports run the **inbox** driver (`DriverProvider=Microsoft`,
  `v2.53.23539.0`). Microsoft docs say inbox drivers are not supported for Azure
  Local deployment, but the **hardware validator does not check driver provider** -
  the gate passes on the inbox driver.

## Orient

- The blocker was never a hardware/procurement problem; it was a
  software/administrative state (disabled device). The fix is free, reversible,
  and needs no parts. The DAC-cable procurement scramble is very likely
  unnecessary for the nodes whose ports already show `Connected`.
- Root process failure: there was no network pre-flight gate. Storage had one
  (Phase 0a); networking did not, so the disabled-NIC state and the CRITICAL
  NetAdapter row sat unread until a full validation pass. Same class of miss as
  the storage documentation-failure pattern (ADR 0003 fallout).
- The inbox-driver caveat is real and fires at a **different stage**: it is a
  deployment-wizard blocker, not a hardware-validation gate. It is still a
  BLOCKER for deploy - WinOF-2 must be in place before the wizard runs. Staged
  later != optional.
- `NdisPhysicalMedium=14` (802.3) is the true pass criterion and appears in **no**
  Microsoft Learn page - it is discover-at-runtime only (captured separately in
  `poc_doc_gap_evidence.txt`, Gap 1). This is why planning could not pre-empt it.

## Decide

The NetAdapter CRITICAL failure at the HARDWARE-VALIDATION stage is resolved by
**enabling the already-present, already-cabled Mellanox ConnectX-5 ports**
(`Enable-PnpDevice`); no cabling, driver, or hardware change is required to pass
hardware validation. This does NOT clear the path to deploy: the inbox driver is
a **deferred blocker** that is expected to be rejected by the deployment wizard,
so the NVIDIA WinOF-2 swap is a REQUIRED pre-deploy step, not an optional followup.

## Act

- Enabled both Mellanox ports on nodes 01 and 02; verified `Up / 100 Gbps /
  NdisPhysicalMedium=14 / Connected` and a passing `AzStackHci_Hardware_Test_NetAdapter`.
- Updated `poc_risk_register.txt`: B1 moved from CRITICAL blocker to RESOLVED,
  with the WinOF-2 swap retained as a tracked followup.
- Repo memory (`/memories/repo/azure-local-poc.md`) records the Enable-PnpDevice
  fix and the PhysMedium=14 / already-cabled findings.
- **Followups:**
  1. Add a network pre-flight gate to `poc_prereq_checklist.txt` (Phase 0b):
     enable Mellanox + verify `PhysMedium=14` per node, mirroring storage Phase 0a.
  2. When the user supplies WinOF-2, `pnputil /add-driver` across the fleet and
     re-verify the ports, then re-run the deployment-readiness checks.
  3. Re-run the enable + verify on nodes 03-06 as they return from the 3x-NVMe
     hardware change; they are likely disabled the same way.

