---
title: "Kubernetes and Terraform integration test results"
domain: [containers, iac]
layer: [kubernetes, cluster]
type: evidence
status: current
proof: proven
audience: [engineer]
tags: [terraform, kubernetes, integration-test, results, lifecycle]
updated: 2026-08-19
---

# Kubernetes and Terraform integration test results

Status: complete - 2026-08-19.

This record captures the bounded execution defined in [Kubernetes and Terraform integration test plan](../../working/test-plans/kubernetes-terraform-integration-test-plan.md).

## Terraform lifecycle baseline

| Check | Result |
| --- | --- |
| Module | Azure Verified Module wrapper for `tf-poc-linux-01` |
| Plan | `3 to add, 0 to change, 0 to destroy` |
| Created resources | Arc machine parent, Azure Local NIC, Azure Local VM extension |
| Runtime placement | Clustered VM `Online` on `AZL-NODE-04`; Hyper-V reported `Running` / `Operating normally` |
| Cleanup | VM extension, clustered VM, NIC, and Arc machine removed |
| Final cleanup check | `terraform plan -destroy`: no objects to destroy |
| Findings | Azure Local VM extension remained ARM `Accepted` after Hyper-V runtime success and after the runtime delete, requiring local Terraform state reconciliation. The residual NIC deletion required PIM reactivation after role expiry. AzureRM provider auto-registration was disabled because it attempted unrelated `Microsoft.Cache/register/action`. |

## Kubernetes execution

| Test | Result | Evidence |
| --- | --- | --- |
| INT-T01 baseline | Pass | Deployment `2/2` ready and available; pods `m94q2` and `zgnwp` Running with zero restarts; two ready Service endpoints. |
| INT-T02 scale | Pass | `kubectl scale` reached `3/3` ready. New pod `72jvt` was Running with zero restarts; EndpointSlice reported three ready endpoints. |
| INT-T02 bounded work | Pass, with port-forward limitation recorded | Ten independent port-forwarded `/api/work` requests returned HTTP success in `38.37-46.08 ms`. All responses came from `zgnwp`. A `kubectl port-forward service/...` selects one backing pod, so this validates bounded work and request correlation, not Service distribution. |
| INT-T02 in-cluster Service routing | Pass | Thirty independent requests from a dashboard pod to `azure-local-dashboard.azure-local-dashboard.svc.cluster.local/api/work` reached both ready backends: `m94q2=17`, `72jvt=13`. |
| INT-T03 self-heal | Pass | Deleted pod `zgnwp` was stopped. Replacement `kjdrh` became Running with zero restarts; Deployment returned to `3/3` ready and EndpointSlice retained three ready endpoints. Recent events recorded replica-set scale, scheduling, creation, start, and the deleted pod's stopping container event. |
| INT-T04 restore | Pass | Deployment restored to `2/2` ready and available. Remaining pods `72jvt` and `m94q2` were Running; EndpointSlice returned to two ready endpoints. Final `/api/work` response came from `m94q2` in `40.04 ms`. |

## Conclusions

- The current AKS worker can safely host the dashboard at two replicas and demonstrated the bounded `2 -> 3 -> 2` scale path.
- Deployment self-healing, readiness-driven endpoint membership, and bounded request processing are verified.
- The Terraform Azure Local VM test completed the planned lifecycle, but its evidence must explicitly include ARM completion lag, local state reconciliation, and PIM expiry during NIC cleanup.
- In-cluster Service routing is verified. A local service port-forward is intentionally not a load-balancing test, and an externally reachable VIP remains blocked by the unregistered Kubernetes Runtime provider.

