---
title: "0006 — Docker operations run in disposable VM, not Azure Local host nodes"
domain: [containers]
layer: [application]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, docker, disposable-vm, host-hygiene]
updated: 2026-08-20
---

# 0006 — Docker operations run in disposable VM, not Azure Local host nodes

- **Status**: Active
- **Date**: 2026-06-18
- **Owner**: labadmin
- **Revisit when**:
  - Microsoft documentation or deployment tooling explicitly requires host-level Docker for this POC, OR
  - The POC changes from "normal Docker operations" to a supported host-container runtime scenario, OR
  - A disposable VM path cannot be deployed and Docker operations remain a required POC target.

## Observe

- The user wants a thorough Azure Local test with Docker and normal Docker operations.
- Azure Local host nodes are the cluster substrate. Mutating them with a general-purpose Docker daemon creates risk and may be unsupported or at least unhelpful for a functional POC.
- The desired Docker operations are normal lifecycle checks: build, tag, run, inspect, logs, exec, stop, restart, publish, push/pull.
- The POC also has a Kubernetes/AKS surface for orchestrated container workloads, using [scripts/Invoke-AksSmokeValidation.ps1](../../scripts/Invoke-AksSmokeValidation.ps1) and manifests under [tests/kubernetes/smoke/](../../tests/kubernetes/smoke/).

## Orient

- There are two different questions:
  1. Can Azure Local host a VM that supports a normal Docker developer workflow?
  2. Can Azure Local host Kubernetes workloads through AKS on Azure Local?
- Question 1 is best tested in a disposable Linux VM running on Azure Local. This proves platform VM/network/storage functionality without touching cluster hosts.
- Question 2 is best tested through AKS on Azure Local using a small MCR-hosted workload.
- Installing Docker directly on Azure Local host nodes mixes the questions and increases blast radius without improving POC evidence.

## Decide

Test normal Docker operations inside a **disposable Linux VM on Azure Local**, and test orchestrated container workloads through **AKS on Azure Local**. Do not install Docker directly on Azure Local host nodes for this POC.

## Act

- Added the Docker operations plan:
  - [poc_docker_operations_test_plan.txt](../../archive/docs/test-plans/poc_docker_operations_test_plan.txt)
- Updated [poc_runbook.txt](../../archive/docs/runbooks/poc_runbook.txt) with a plan-only Docker phase.
- Updated the POC plan (not published) with an entry pointing to the Docker operations plan.
- The plan explicitly treats host-node Docker installation as a no-go condition.

