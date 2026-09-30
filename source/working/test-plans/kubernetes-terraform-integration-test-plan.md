---
title: "Kubernetes and Terraform integration test plan"
domain: [containers, iac]
layer: [kubernetes]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [test-plan, kubernetes, terraform, validation-contract]
updated: 2026-08-19
---

# Kubernetes and Terraform integration test plan

## Purpose

Validate the two control loops that form the capstone foundation:

- Kubernetes maintains application replicas and routes traffic to ready pods.
- Terraform plans, creates, verifies, and removes an isolated Azure Local VM without touching shared POC resources.

This is a low-impact POC test. It does not add an AKS worker, create a new Azure Local VM during execution, mutate
storage, or perform a load test.

## Preconditions

- PIM roles are active for any Azure Local control-plane operation.
- The existing `azure-local-dashboard` Deployment has two ready replicas.
- The dashboard Service is `ClusterIP` and all activity remains inside the existing AKS worker.
- The Terraform lifecycle result is available from the isolated `tf-poc-linux-01` test.
- The node 01 retired-disk condition is recorded as a degraded-state maintenance item; no storage action is part
  of this test.

## Test cases

### INT-T01 - Dashboard baseline

1. Record Deployment desired, ready, and available replicas.
2. Record pod names, worker placement, restart counts, and Service ready endpoints.
3. Verify `/api/kubernetes/state` and `/api/work` through a temporary Service port-forward.

Pass:

- Deployment is `2/2` ready.
- Two Service endpoints are ready.
- API responses identify a serving pod and bounded work duration.

### INT-T02 - Controlled replica scale

1. Scale `azure-local-dashboard` from two to three replicas using `kubectl scale`.
2. Wait for rollout completion.
3. Verify three ready pods and three Service endpoints.
4. Run a fixed ten-request bounded work burst through the Service.
5. Capture the distinct serving pod names observed.

Pass:

- Deployment reaches `3/3` ready.
- A new pod is scheduled and Ready without restart loops.
- Service state shows three ready endpoints.
- Work responses complete successfully.

### INT-T03 - Deployment self-healing

1. Delete exactly one Ready dashboard pod.
2. Wait for the Deployment to restore three ready replicas.
3. Verify the deleted pod name is absent and a replacement pod name is present.
4. Capture relevant Deployment/ReplicaSet/Event evidence.

Pass:

- The Deployment restores `3/3` ready replicas.
- The replacement pod is Ready with no unexpected restart loop.
- The observed Event stream records normal scheduling, pull, creation, or start behavior.

### INT-T04 - Restore steady state

1. Scale the Deployment from three replicas back to two.
2. Wait for rollout completion.
3. Verify `2/2` ready replicas and two Service endpoints.
4. Run one final `/api/work` request.

Pass:

- Deployment returns to `2/2` ready.
- No dashboard pod is in `Pending`, `Failed`, or `CrashLoopBackOff`.
- Service retains a working internal endpoint.

### INT-T05 - Terraform lifecycle evidence

Review the isolated `tf-poc-linux-01` lifecycle already executed:

```text
plan:    3 add, 0 change, 0 destroy
create:  Arc machine, NIC, and VM extension created
runtime: clustered VM Online on AZL-NODE-04
cleanup: VM extension, clustered VM, NIC, and Arc machine deleted
final:   terraform plan -destroy reported no managed objects
```

Pass:

- Terraform managed only the three `tf-poc-` resources.
- No manual demo VM, gallery image, logical network, AKS resource, or cluster foundation was modified.
- The ARM extension's `Accepted` status lag and resulting state reconciliation are recorded as an integration
  finding, not hidden as a successful clean drift result.

## Evidence capture

Capture sanitized output only:

- Deployment replica counts and endpoint counts before, during, and after scale.
- Pod names, status, node, and restart counts.
- Observed Service work-response pod names and durations.
- Event reason/message/timestamp subset.
- Terraform resource addresses, plan summaries, owner node, lifecycle result, ARM status lag, PIM-expiry NIC
  cleanup finding, and final no-destroy plan.

Do not place kubeconfigs, passwords, full Terraform state, tokens, or raw PIM output in the evidence.

## Safety boundaries

- Do not scale beyond three dashboard replicas.
- Do not change AKS node-pool count.
- Do not delete more than one dashboard pod at a time.
- Do not run a high-rate request generator or workload stress test.
- Always restore the dashboard to two replicas.
- Do not run another Terraform apply as part of this test.

## Result record

Populate the execution result in [Kubernetes and Terraform integration test results](../../docs/planning/kubernetes-terraform-integration-test-results.md) after the test completes.

