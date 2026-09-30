---
title: "0009 - Reimage flow: same media + full updates; do NOT pin specific KBs"
domain: [platform]
layer: [os]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, image-recipe, lcu, windows-update, sconfig]
updated: 2026-06-25
---

# 0009 - Reimage flow: same media + full updates; do NOT pin specific KBs

> **Amended 2026-09-02 by later deployment evidence.** The core decision below still
> stands: do not pin specific KBs or MSUs in tooling. What changed is *when* updates
> happen. Running updates at image time, through SConfig option 6 or public Windows
> Update, is the wrong move and broke Arc bootstrap on this project. Install from clean
> media, do **not** update, and let the platform bring the node to the correct version
> after hardware validation. See [POC deployment summary](../POC-deployment-summary.md),
> section 3, and the [node reimage checklist](../storage-imaging/reimage-checklist.md).
> This ADR was written mid project, when several nodes sat at different partial patch
> levels and levelling them up looked like the fix. The real fix was not to start.

- **Status**: Active for the KB pinning decision, amended on update timing
- **Date**: 2026-06-25
- **Owner**: labadmin
- **Revisit when**:
  - Microsoft changes the Azure Local install flow so updates are no longer a
    post-image wizard step, OR
  - A fully-updated node still fails `Invoke-AzStackHciArcInitialization` recipe
    validation even after the solution version is aligned to the patched build.

## Observe

- Every node is installed from the **same media**, then the documented flow is:
  install -> establish network connectivity -> (step 4) **run updates through the
  wizard**. Updating to a consistent, fully-patched state is part of the process,
  not damage.
- `Invoke-AzStackHciArcInitialization` on reimaged nodes failed early with
  `ImageRecipeValidationTestsFailedException` /
  `AzStackHci_OSImageRecipeValidation_LCU` ("Latest Cumulative Update matches recipe").
  Evidence: [out/azl-node-01-DiagnosticsResult-20260625_143726.json](../../out/azl-node-01-DiagnosticsResult-20260625_143726.json).
- The failures correlate with nodes being **partially** updated, not with the media:
  - Node 1 build `26100.32690` running, `26100.32995` rollup already STAGED.
    Hotfixes `KB5094125`/`KB5094137` were installed automatically by
    `NT AUTHORITY\SYSTEM` on 2026-06-25 (WU events 06-20..06-25). So node 1 is
    mid-update, not at a clean recipe point.
  - Nodes 3/4/6 had drifted further (build `32995`) and were missing `KB5082417`.
- The `EnvironmentChecker` recipe on the node is a point-in-time module
  (`10.2604.1.2084`) that pins exact MSU filenames for the 2604 LCU set. When the OS
  is updated past that point, a naive per-KB presence check no longer matches.

## Orient

- The divergence between nodes is **how far each got through the update step**, not an
  ISO/media difference. Same media in, different patch levels out because updates were
  applied unevenly and partially.
- Pinning a specific KB (e.g. installing exactly `KB5082063` offline) is the WRONG fix:
  it hard-codes a single point on a moving update train into our tooling, fights the
  "image + full update" design, and breaks the next time the baseline rolls forward.
- The recipe check passes when a node is at a **consistent, fully-updated build AND the
  Azure Local solution/EnvironmentChecker version being validated matches that build**.
  That is why `-TargetSolutionVersion` exists; it failed earlier only because the node
  under test was partially updated, not because the approach is wrong.

## Decide

- Do NOT pin specific KBs/MSUs in our install or remediation tooling. Removed the
  KB-pinning helper that an earlier draft introduced (`scripts/Install-NodeRecipeLcu.ps1`).
- Standard flow per node: **install from the same media -> network connectivity ->
  run full updates via the wizard until the node is fully patched and rebooted ->** then
  run Arc bootstrap, aligning `-TargetSolutionVersion` to the patched build when needed.
- Treat "recipe LCU mismatch" as a **"node not fully updated yet / solution version not
  aligned"** signal, not as a missing-single-patch problem.

## Act

- Owner is running full updates on nodes 03/04/05/06 (2026-06-25). Node 1 also has the
  `32995` rollup staged and will converge on reboot.
- After each node is fully updated + rebooted, run:
  `.\scripts\Onboard-ArcMachine.ps1 -NodeFqdn <node>.lab.example.com` and, if the local
  recipe check still flags, add `-TargetSolutionVersion <version matching the patched build>`.
- Keep hostnames `AZL-NODE-0X`. Node 2 stays out of scope (reimage to AHCI/Non-RAID, ADR 0007).
- Evidence retained:
  - [out/azl-node-01-DiagnosticsResult-20260625_143726.json](../../out/azl-node-01-DiagnosticsResult-20260625_143726.json)
  - Node 1 WU history showing automatic `KB5094125`/`KB5094137` installs and the staged
    `26100.32995` rollup over running `26100.32690`.

## Amendment (2026-09-02): where updates actually come from

The flow recorded in Decide above levels a node up by hand before Arc bootstrap. Deployment
proved that is the wrong order, and the automatic Windows Update activity noted in the
evidence above is part of why: a node left to update itself drifts off the signed recipe
without anyone choosing to do it.

The rule, stated plainly:

1. Install from clean media.
2. Establish network connectivity.
3. Do **not** run SConfig option 6, `wuauclt`, or any public Windows Update. Disable or
   avoid anything that would update the node on its own before deployment.
4. Run Arc bootstrap and let deployment and hardware validation proceed.
5. After that, the platform owns updates. `Get-SolutionUpdate` and `Start-SolutionUpdate`
   deliver the operating system, agents, drivers and firmware together as one validated
   solution version, rolled node by node.

The distinction that matters is which mechanism, not whether to patch. Updating at image
time uses the public channel and breaks the recipe. Updating after deployment uses the
Azure Local solution channel and is the supported path. Both are called an update, and
only one of them works here.

Live example, `azl-node-01` on 2026-09-02: solution version `12.2604.1003.1006`, state
`UpdateAvailable`, with `2026.08 Cumulative Update` at `12.2608.1003.9` reported `Ready`.
One version number covering OS, agents, drivers and firmware, with `OemVersion 2.1.0.0`
as the Dell solution builder extension.

