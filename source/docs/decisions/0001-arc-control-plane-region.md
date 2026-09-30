---
title: "0001 — Arc / Azure Local control-plane region: South Central US"
domain: [platform]
layer: [arc]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, arc, region, southcentralus]
updated: 2026-08-20
---

# 0001 — Arc / Azure Local control-plane region: South Central US

- **Status**: Active
- **Date**: 2026-06-04
- **Owner**: labadmin
- **Revisit when**:
  - Microsoft adds another candidate region (`westus2`, `westus3`,
    `westcentralus`) to the Azure Local supported-regions list, OR
  - We deploy a second cluster with different region requirements, OR
  - Cross-region latency from the lab site to `southcentralus` becomes a
    measured problem during real workload operation.

## Observe

### O1. Hardware location
- All six nodes (`azl-node-01..06.lab.example.com`) physically live in a
  local lab, represented by rack `rack-01`. Source: the
  project's physical inventory plan.

### O2. Candidate Azure regions

The evaluation considered `westus2`, `westus3`, `westcentralus`,
`southcentralus`, `canadacentral`, and `eastus`. A candidate's proximity
does not make it a supported Azure Local control-plane region.

### O3. Officially documented Azure Local control-plane regions
Microsoft Learn, **Azure Local system requirements** (azloc-2605):
<https://learn.microsoft.com/en-us/azure/azure-local/concepts/system-requirements-23h2#azure-requirements>

> Azure regions: Azure Local is supported for the following regions:
> (Azure public)
> - East US
> - West Europe
> - Australia East
> - Southeast Asia
> - India Central
> - Canada Central
> - Japan East
> - **South Central US**

The `westus2`, `westus3`, and `westcentralus` candidates do not appear on the list.

### O4. FAQ confirms this is an explicit architectural constraint
<https://learn.microsoft.com/en-us/azure/azure-local/faq>

> Azure Local is available:
> - In the geographic regions where our OEMs serve the physical hardware.
> - **In the Azure regions where the Azure Local control plane is available.**

I.e. hardware location and control-plane region are decoupled by design,
and the control-plane region is explicitly a Microsoft-managed allowlist.

### O5. Runtime evidence — bootstrap cmdlet enforces the allowlist
First attempt at Arc bootstrap (region `westus3`) on
`azl-node-01.lab.example.com` on 2026-06-04 returned:

> Bootstrap reported error: Region 'westus3' is not supported.
> Supported regions are: `eastus, eastus2euap, westeurope,
> australiaeast, southeastasia, centralindia, canadacentral, japaneast,
> southcentralus, germanywestcentral`.

Captured in the generated onboarding log at the time of the decision. The retained deployment and cluster context is
summarized in [the deployment completion summary](../POC-deployment-summary.md).

Note: the cmdlet allows two extra regions beyond the public doc list
(`eastus2euap`, `germanywestcentral`), likely preview/staging slots.
Not relevant to us.

### O6. Validation that southcentralus works
Second attempt (region `southcentralus`) on the same node, same day,
completed in ~3 minutes with sequence
`ArcConfiguration → ConnectivityValidation → ArcRegistration → Succeeded`.

`az connectedmachine list -g rg-azlocal-poc-001 -o table` confirms:

```
Name           Location        ProvisioningState  Status
AZL-NODE-01 southcentralus  Succeeded          Connected
```

AgentVersion `1.63.03384.2896`, OS image `10.0.26100.32690` (Azure Stack
HCI 23H2).

## Orient

The `westus2` candidate is not on Microsoft's allowlist for Azure Local.
The comparison therefore focused on supported candidates: `eastus`,
`canadacentral`, and `southcentralus`.

| Region | Documentation footprint | Role in the evaluation |
|---|---|---|
| `southcentralus` | Listed in official supported regions | Selected after latency comparison |
| `canadacentral` | Listed | Alternative supported candidate |
| `eastus` | Listed; common in samples/docs | Documentation-oriented alternative |

Tradeoffs:

- **Latency vs documentation strength.** Picking `southcentralus`
  optimizes for the observed management-plane latency.
  Picking `eastus` optimizes for matching every Microsoft Learn sample
  verbatim, which is mostly a convenience for future me.
- **Blast radius.** Both options are single-region; neither gives DR.
  No tiebreaker here.
- **Cost.** No price delta between these regions for the resources we
  use (Arc machines, ARB, Key Vault, LAW).
- **Compliance / data residency.** Select a supported region that meets
  the deploying organization's residency requirements. This POC recorded
  no residency requirement that preferred one candidate over another.

For a POC where we control everything and management-plane
responsiveness during deploy/troubleshoot is the daily pain point,
**latency wins** over docs-matching.

## Decide

**Arc / Azure Local control-plane region for this POC is
`southcentralus`.**

Resource group (`rg-azlocal-poc-001`) keeps its `westus3` location
since RG location is metadata only and resources inside an RG can live
in any region — that's confirmed by the successful node-01 registration
in `southcentralus` within a `westus3` RG (see O6).

## Act

Implementation:
- [scripts/Onboard-ArcMachine.ps1](../../scripts/Onboard-ArcMachine.ps1)
  — default `-Region` changed from `westus3` to `southcentralus`,
  with a doc-comment block referencing this decision and the
  supported-regions list.
- The POC plan (not published) — `poc_naming.arc_region` added with
  value `"southcentralus"`; `poc_naming.location` still
  `"westus3"` (RG metadata). Both labelled in the file's comments.

Validation already performed (see O6):
- `AZL-NODE-01` is `Connected` in `southcentralus` /
  `rg-azlocal-poc-001`.
- The generated bootstrap log is intentionally excluded from the curated source surface; the successful deployment
  and cluster state are summarized in [the deployment completion summary](../POC-deployment-summary.md).

Follow-ups (open todos at time of decision):
- Fan-out Arc onboard to nodes 02–06 in the same region.
- Run AzStackHci.EnvironmentChecker connectivity validator from each
  node so we have per-node evidence the southcentralus endpoints are
  reachable, not just node 01.
- When we provision Key Vault and Log Analytics Workspace for the
  cluster, co-locate them in `southcentralus` to avoid cross-region
  control-plane hops (the plan still says `westus3` for these — needs a
  follow-up edit, tracked separately, not in scope for this decision).
