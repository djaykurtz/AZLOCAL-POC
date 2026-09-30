# Working Material

Real records of how the work went. Version controlled, deliberately not published.

The split is about what a future reader would cite. [`docs/`](../docs/README.md) is the reference set, so
everything in it has to earn a place someone would link to months from now. This folder holds the material that
was genuinely useful while the work was happening and would only be noise on a shelf.

Nothing here is scratch. It is all real, and several of these documents are the primary record of a proof that a
published document only summarises. If you are auditing a claim rather than reproducing an environment, this is
where the detail is.

## Sprints

Per-sprint execution records. Useful for tracing what was attempted and when, not useful as reference.

- [S1 - Deploy test VMs](sprints/deploy-test-vms.md)
- [S2 - Live migration](sprints/live-migration.md)
- [S3 - Node failure recovery](sprints/node-failure-recovery.md)
- [S4 - Docker on cluster](sprints/docker-on-cluster.md)
- [S5 - AKS on Azure Local](sprints/aks-on-azure-local.md)
- [S6 - Terraform against cluster](sprints/terraform-against-cluster.md)
- [S7 - Load balancer and scale set](sprints/loadbalancer-scaleset.md)

## Plans

Forward work and design plans. A plan for something already built belongs here, not in the reference set, because
the built thing is its own documentation.

- [AKS and scale work plan](plans/aks-and-scale-work-plan.md)
- [Unplanned node recovery boundary plan](plans/unplanned-node-recovery-boundary-plan.md)
- [Funder dashboard plan](plans/funder-dashboard-plan.md)

## Test plans

The plans that produced the published results. The results are the citable artifact. These are the method.

- [Kubernetes and Terraform integration test plan](test-plans/kubernetes-terraform-integration-test-plan.md)
- [Windows Server 2025 on cluster test plan](test-plans/windows-server-2025-on-cluster-test-plan.md)

## Findings

Point-in-time investigations. Accurate on the day they were written, and not maintained since.

- [Container surface findings](findings/container-surface-findings.md)
- [Security monitoring extension observability conflict evidence](findings/security-agent-observability-conflict-evidence.md)

The security agent evidence is here for a second reason beyond shelf life. It argues for suppressing a monitoring
agent on the cluster. That is a document you hand to a named reviewer with the surrounding context, not one you
leave open on a wiki for someone to find and act on out of context.
