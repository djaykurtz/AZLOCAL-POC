---
title: "0004 — Four-node functional POC scope"
domain: [platform]
layer: [cluster]
type: decision
status: current
proof: proven
audience: [leadership, engineer]
tags: [adr, scope, four-node, poc-boundary]
updated: 2026-08-20
---

# 0004 — Four-node functional POC scope

- **Status**: Active
- **Date**: 2026-06-18
- **Owner**: labadmin
- **Revisit when**:
  - AZL-NODE-05/06 receive matching storage/RAM/network validation and the POC needs scale-out evidence, OR
  - A validator hard-blocks the 4-node build on memory or another shared hardware floor, OR
  - The POC is asked to make production HA, DR, or performance claims.

## Observe

- The storage spec lock in [0003-storage-spec-lock.md](0003-storage-spec-lock.md) targets AZL-NODE-01..04 as the active build-out and keeps two adapter cards as spares for AZL-NODE-05/06.
- The current hardware plan has 8 KIOXIA NVMe data drives, which maps cleanly to 2 poolable data drives on each of 4 active nodes.
- All 4 active nodes report 31.5 GB visible RAM against a 32 GB Azure Local floor. Additional RAM is uncertain; user indicated this is a proof of concept and not production.
- The user clarified the POC goal: "I just need to test if it works." They also asked whether dropping from 6 nodes to 4 nodes and using 48 GB across 3x16 GB DIMMs would be better.
- The POC already had no-HA posture in the historical test plans: [poc_docker_operations_test_plan.txt](../../archive/docs/test-plans/poc_docker_operations_test_plan.txt), [poc_kubernetes_test_plan.txt](../../archive/docs/test-plans/poc_kubernetes_test_plan.txt), and [poc_terraform_test_plan.txt](../../archive/docs/test-plans/poc_terraform_test_plan.txt).

## Orient

- A 4-node Azure Local POC is the shortest credible path to proving deployment, storage validation, Arc/portal management, VM deployment, AKS scheduling, and simple workload execution.
- Attempting to build all 6 nodes before the 4-node system works adds storage, memory, validation, and smart-hands complexity without increasing the chance of first success.
- If 48 GB per active node becomes available and is supported by the platform population rules, it is materially better than 31.5 GB visible for validation risk. It is still not necessary to make 64 GB a production-style target for this POC.
- Nodes 05/06 are useful as future scale-out evidence, not as a first-cluster prerequisite.

## Decide

Run the Azure Local POC as a **4-node functional proof** on AZL-NODE-01..04, with AZL-NODE-05/06 deferred as an optional scale-out path.

## Act

- Keep storage installation focused on AZL-NODE-01..04.
- Treat RAM as a validation risk to measure, not a reason to block all other POC work. If 48 GB per active node becomes available, prefer it; otherwise run validation and let the validator decide.
- Document 4-node default / 6-node optional scale path in:
  - [poc_test_design.txt](../../archive/docs/test-plans/poc_test_design.txt)
  - [poc_docker_operations_test_plan.txt](../../archive/docs/test-plans/poc_docker_operations_test_plan.txt)
  - [poc_kubernetes_test_plan.txt](../../archive/docs/test-plans/poc_kubernetes_test_plan.txt)
  - [poc_terraform_test_plan.txt](../../archive/docs/test-plans/poc_terraform_test_plan.txt)
- Do not claim production HA, DR, or performance from the POC unless a later ADR explicitly changes scope.

