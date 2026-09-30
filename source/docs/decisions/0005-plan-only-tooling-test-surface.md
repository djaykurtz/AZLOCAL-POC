---
title: "0005 — Plan-only Terraform/Docker/Kubernetes test surface"
domain: [iac, containers]
layer: []
type: decision
status: superseded
proof: proven
audience: [engineer]
tags: [adr, plan-only, test-surface, terraform, docker, kubernetes]
updated: 2026-08-28
---

# 0005 — Plan-only Terraform/Docker/Kubernetes test surface

- **Status**: Superseded on 2026-08-28. Its own revisit condition fired.
- **Date**: 2026-06-18
- **Owner**: labadmin
- **Revisit when**:
  - Terraform is promoted from tooling target to deployment source of truth, OR
  - Docker/Kubernetes artifacts are no longer smoke-test artifacts and become production workload definitions, OR
  - The POC needs real deployment automation before the hardware is validated.

## Outcome

This decision was correct for the period it covered and is no longer in force. It was written while the
hardware was still blocked, and it holds Terraform, Docker and Kubernetes at plan-only "until the Azure
Local hardware and cluster path are ready". That condition was met on 2026-07-27 and all three have since
run for real.

- Cluster deployed 2026-07-27, 54 of 54 steps Succeeded, no retries, wall time about 2h 13m.
  See [docs/POC-deployment-summary.md](../POC-deployment-summary.md).
- Terraform executed a full human-operated lifecycle on 2026-08-19. It created `tf-poc-linux-01`
  with its NIC and virtual machine instance, the clustered VM came up Online on `AZL-NODE-04`,
  and `terraform destroy` removed it. The final `terraform plan -destroy` reported nothing left.
  See [working/sprints/terraform-against-cluster.md](../../working/sprints/terraform-against-cluster.md).
- Docker ran for real on 2026-07-30. Docker CE 29.x and Compose v5.3.1 on Rocky Linux 10.2 in a
  guest VM on the cluster, with Dockge answering HTTP 200 from off the box.
  See [docs/runbooks/docker-dockge-on-rocky-runbook.md](../runbooks/docker-dockge-on-rocky-runbook.md).
- Kubernetes runs continuously. AKS Arc v1.33.5 with a dashboard Deployment, replica scale from two
  to three and back, and pod self-heal, all with zero restarts.
  See [docs/planning/kubernetes-terraform-integration-test-results.md](../planning/kubernetes-terraform-integration-test-results.md).

The one hardware fault worth recording: a single NVMe in `AZL-NODE-01` failed and was retired. It
was a spare beyond the three data disks per node, so pool capacity was unaffected.
See [docs/runbooks/node01-retired-nvme-recovery.md](../runbooks/node01-retired-nvme-recovery.md).

What remains deferred is narrower than this ADR implies: pipeline identity and remote state for
Terraform. Docker staying in a guest VM rather than on the cluster hosts is not a leftover of this
decision, it is the deliberate call recorded in
[0006-docker-operations-disposable-vm.md](0006-docker-operations-disposable-vm.md), which is still current.

## Observe

*Written 2026-06-18. Preserved as the record of what was true then, not what is true now.*

- Hardware is still blocked on storage installation and post-install validation.
- The user asked to use the waiting period to write good tests for Terraform, Docker, and Kubernetes.
- Existing repo IaC is Bicep under [infra/](../../infra/). There were no Terraform modules, Dockerfiles, or Kubernetes manifests before this pass.
- The user explicitly framed this as preliminary script/design work: "you are just writing scripts for deployment at this point not actually deploying."
- The local validation suite now passes with no deployment:
  - [scripts/Invoke-LocalValidation.ps1](../../scripts/Invoke-LocalValidation.ps1)
  - latest run: PASS 29, SKIP 2 (`terraform` and `kubectl` not in PATH)

## Orient

- Useful tests can exist before the target system exists if they validate deployment materials, assumptions, and toolchain readiness rather than the future cluster itself.
- Terraform can safely validate the 4-node/6-node POC shape without Azure credentials if the starter module stays provider-free and resource-free.
- Docker can be tested locally or in a future disposable VM without pushing images or deploying to AKS.
- Kubernetes manifests can be statically checked now and later dry-run/applied when `kubectl` and AKS exist.
- A single local harness helps prevent drift across PowerShell, Bicep, Terraform, Docker, and Kubernetes artifacts while hardware is unavailable.

## Decide

Make Terraform, Docker, and Kubernetes part of the POC **test surface**, but keep them **plan-only/no-deploy** until the Azure Local hardware and cluster path are ready.

## Act

- Added no-deploy validation harness:
  - [scripts/Invoke-LocalValidation.ps1](../../scripts/Invoke-LocalValidation.ps1)
- Added dedicated helper scripts:
  - [scripts/Invoke-TerraformPlanOnly.ps1](../../scripts/Invoke-TerraformPlanOnly.ps1)
  - [scripts/Invoke-DockerSmokeBuild.ps1](../../scripts/Invoke-DockerSmokeBuild.ps1)
  - [scripts/Test-KubernetesManifests.ps1](../../scripts/Test-KubernetesManifests.ps1)
- Added starter artifacts:
  - [tests/terraform/poc-smoke/main.tf](../../tests/terraform/poc-smoke/main.tf)
  - [tests/docker/smoke/Dockerfile](../../tests/docker/smoke/Dockerfile)
  - [tests/kubernetes/smoke/00-namespace.yaml](../../tests/kubernetes/smoke/00-namespace.yaml)
  - [tests/kubernetes/smoke/10-deployment.yaml](../../tests/kubernetes/smoke/10-deployment.yaml)
  - [tests/kubernetes/smoke/20-service.yaml](../../tests/kubernetes/smoke/20-service.yaml)
- Added plan documents:
  - [poc_test_design.txt](../../archive/docs/test-plans/poc_test_design.txt)
  - [poc_terraform_test_plan.txt](../../archive/docs/test-plans/poc_terraform_test_plan.txt)
  - [poc_docker_operations_test_plan.txt](../../archive/docs/test-plans/poc_docker_operations_test_plan.txt)
  - [poc_kubernetes_test_plan.txt](../../archive/docs/test-plans/poc_kubernetes_test_plan.txt)
- Updated the POC plan (not published) so these are visible in the POC target list.

