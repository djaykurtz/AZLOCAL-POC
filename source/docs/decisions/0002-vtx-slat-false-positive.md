---
title: "0002 — VT-x / SLAT 'disabled' reading was a false positive"
domain: [platform]
layer: [firmware]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, virtualization, vt-x, slat, false-positive, wmi]
updated: 2026-08-20
---

# 0002 — VT-x / SLAT "disabled" reading was a false positive

- **Status**: Active
- **Date**: 2026-06-09
- **Owner**: labadmin
- **Revisit when**:
  - The detection logic in
    [scripts/Get-NodeHardware.ps1](../../scripts/Get-NodeHardware.ps1) is
    rewritten such that the Win32_Processor-only signal is removed,
    OR
  - A node ever shows `HypervisorPresent = False` (then the BIOS flags
    in Win32_Processor become trustworthy again and this decision needs
    re-reading), OR
  - Microsoft fixes the Win32_Processor reporting behaviour inside a
    running root partition (would invalidate the rationale, not the
    outcome).

## Observe

### O1. The original alarming signal
[scripts/Get-NodeHardware.ps1](../../scripts/Get-NodeHardware.ps1)
collected the standard WMI signals across all 6 nodes. Aggregated in
[out/_fleet_summary.txt](../../out/_fleet_summary.txt):

```
Node       : azl-node-01..06 (all 6 identical)
VT         : False
SLAT       : False
```

Backing JSON, e.g.
[out/_azl-node-01-live.json](../../out/_azl-node-01-live.json):

```json
"Virtualization": {
  "VirtualizationFirmwareEnabled": false,
  "VMMonitorModeExtensions": false,
  "SecondLevelAddressTranslationExtensions": false
}
```

That triggered a draft smart-hands BIOS pass, later canceled in place after the independent confirmation sweep.

### O2. Independent confirmation sweep
[scripts/Get-VirtualizationSignals.ps1](../../scripts/Get-VirtualizationSignals.ps1)
queried five independent signals on each node:

```
Node           W32_VirtFW W32_SLAT GCI_HVPresent GCI_VirtFW GCI_SLAT BCD_HVLaunch HV_FeatureState HV_VmmsState
azl-node-01      False    False          True                     Auto                         Running
azl-node-02..06  (same pattern)
```

Captured at [out/_virt_signals.txt](../../out/_virt_signals.txt) and
[out/_virt_signals.json](../../out/_virt_signals.json).

Key reads:
- `Get-ComputerInfo.HyperVisorPresent = True` on all 6
- `bcdedit /enum {current}` shows `hypervisorlaunchtype Auto` on all 6
- `Get-Service vmms` is `Running` on all 6
- `Get-ComputerInfo.HyperVRequirement*` is blank — `Get-ComputerInfo`
  returns `$null` for the Hyper-V *requirements* fields whenever a
  hypervisor is already present (it's a "can you install Hyper-V"
  check, not a "is Hyper-V installed" check)

### O3. systeminfo.exe confirmation
Direct invocation of `systeminfo.exe` on node 01 (representative):

```
Virtualization-based security: Status: Running
                               Base Virtualization Support
                               APIC Virtualization
Hyper-V Requirements:          A hypervisor has been detected.
                               Features required for Hyper-V will not
                               be displayed.
```

`systeminfo` is a separate code path that reads CPUID directly when the
hypervisor is *not* running, and explicitly reports "A hypervisor has
been detected" when it *is*. VBS = Running is a particularly strong
signal because VBS itself requires VT-x, VT-d, SLAT/EPT, and IOMMU all
enabled in BIOS — it cannot start otherwise.

### O4. The Microsoft-documented behaviour
`Win32_Processor` properties like `VirtualizationFirmwareEnabled` and
`SecondLevelAddressTranslationExtensions` are populated from data the
hypervisor presents to the root partition. When Hyper-V is running, the
root partition sees a paravirtualized CPU descriptor; some of these
fields are not faithfully passed through and report `False` even when
the underlying silicon and firmware have them enabled.

Reference (general background, behaviour is consistent across Win10/11
and Server 2019+):
<https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processor>

## Orient

We had a single signal (`Win32_Processor.VirtualizationFirmwareEnabled`)
saying VT-x was off, and four independent signals
(`HyperVisorPresent = True`, `hypervisorlaunchtype = Auto`,
`vmms = Running`, `systeminfo` reporting "hypervisor detected" + VBS
Running) saying it must be on.

Hyper-V cannot launch the hypervisor without VT-x + EPT enabled in
firmware. Therefore the only self-consistent reading is that the BIOS
flags *are* enabled and the WMI value is wrong.

The mistake on our side was that
[scripts/Get-NodeHardware.ps1](../../scripts/Get-NodeHardware.ps1) trusted
`Win32_Processor` blindly and presented its output as authoritative
fleet state without cross-checking against `HypervisorPresent`. We
nearly burned a smart-hands trip and a maintenance window on a no-op.

Alternatives considered:
1. **Remove the WMI virtualization fields entirely** — too lossy; the
   fields *are* correct when the hypervisor is not running, which will
   apply to fresh installs before Hyper-V auto-starts.
2. **Always read via Get-ComputerInfo or systeminfo instead** — these
   are slower and less structured; not a fit for the hardware
   inventory script's purpose.
3. **Add `HypervisorPresent` alongside the WMI fields, plus a Note
   string that tells the reader when to discount them** — pragmatic,
   keeps existing JSON shape additive, prevents the same confusion
   next time. Chosen.

## Decide

**VT-x, VT-d, and SLAT are enabled in BIOS on all six lab nodes.
No smart-hands BIOS pass is needed.**

For future inventory runs, treat `Win32_Processor` virtualization flags
as unreliable whenever `Win32_ComputerSystem.HypervisorPresent` is
`True`. The authoritative cross-check is
[scripts/Get-VirtualizationSignals.ps1](../../scripts/Get-VirtualizationSignals.ps1).

## Act

Implementation:
- [scripts/Get-NodeHardware.ps1](../../scripts/Get-NodeHardware.ps1) —
  Virtualization block now also captures `HypervisorPresent` from
  `Win32_ComputerSystem` and emits a `Note` string explaining when the
  BIOS flags can/cannot be trusted. Header comment links to this ADR.
- [scripts/Get-VirtualizationSignals.ps1](../../scripts/Get-VirtualizationSignals.ps1)
  — new authoritative cross-check, runs over all 6 nodes by default,
  writes [out/_virt_signals.txt](../../out/_virt_signals.txt) and
  [out/_virt_signals.json](../../out/_virt_signals.json).
- The retired smart-hands configuration snapshot was replaced with a cancellation notice; this decision and
  `Get-VirtualizationSignals.ps1` are the retained evidence.

Validation already performed:
- Sweep across all 6 nodes confirms `HypervisorPresent = True`,
  `hypervisorlaunchtype = Auto`, `vmms Running`.
- `systeminfo` on node 01 explicitly reports the hypervisor detected
  and VBS Status: Running.

Follow-ups:
- Re-run [scripts/Get-NodeHardware.ps1](../../scripts/Get-NodeHardware.ps1)
  on all 6 nodes after the patch to refresh `out/_azl-node-NN-live.json`
  with the new `HypervisorPresent` + Note fields. (Cosmetic; not
  blocking.)
- Hard-blocker list shrinks: data drives remain the only on-prem
  hardware gap before cluster deploy.

