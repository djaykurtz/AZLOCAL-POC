---
title: "Azure Local POC - Current Status"
domain: [platform]
layer: []
type: index
status: current
proof: proven
audience: [leadership, engineer, operator]
tags: [status, current-state, boundaries, proven, scope]
updated: 2026-09-21
---

# Azure Local POC - Current Status

Last updated: 2026-09-21

`AZL-CLUSTER-01` is a completed four-node functional Azure Local POC. This file is the short current-state board;
the supporting evidence lives in the linked records below.

## Proven

- Four-node Azure Local cluster: `AZL-NODE-01`, `02`, `04`, and `06`.
- Azure Arc Resource Bridge, custom location, Storage Spaces Direct, and Azure management integration.
- Windows and Linux Azure Local VMs, including lifecycle operations, live migration, and planned host reboot recovery.
- Docker and Dockge in a Linux guest VM, not on Azure Local hosts.
- AKS Arc with a live two-replica dashboard workload, replica scale, pod self-healing, and in-cluster Service routing.
- Terraform human-operated Azure Local VM lifecycle: plan, create, verify, destroy, and reconciled clean state.
- Credential recovery path: every POC credential has a durable copy in `azl-cluster-01-kv`, verified 2026-08-26.

## Deliverables

- [Azure Local field guide](guide/azure-local-guide.html). Seven parts covering planning, permissions,
  machine preparation, deployment, workloads, operations, and a command reference. Standalone HTML that
  prints to PDF, cited to Microsoft's documentation, with no dependency on this repository.
- Capstone presentation. `scripts\Build-CapstoneSingleFile.ps1` bundles the deck into one portable HTML
  file with every stylesheet, script, and image inlined and no external references.

## Current Boundaries

- This is a functional POC, not a production supportability, HA, DR, performance, or capacity certification.
- Four functional nodes are the accepted scope. Nodes `03` and `05` remain optional future capacity or donor paths.
- The node `01` retired NVMe path is a maintenance risk. Avoid stress or scale claims until it is remediated.
- The dashboard is intentionally internal through ClusterIP and controlled local port-forward. External MetalLB VIP requires
  `Microsoft.KubernetesRuntime` provider registration, which is not being escalated for this POC.
- HPA, AKS node-pool scale, database and storage application workloads, formal threat modeling, and ADO hybrid workers
  are follow-on work only if separately promoted with a concrete requirement.
- The GitHub Actions source-validation workflow is **authored but has never run**. This repository is owned by an
  Enterprise Managed User account, and GitHub-hosted runners are not available to EMU user-owned repositories, so
  `runs-on: ubuntu-latest` can never be scheduled. Source validation runs locally instead. Moving the repository to an
  organization, or attaching a self-hosted runner, would be required to actually execute it.

## Start Here

- [Project story and current proof](README.md)
- [Original acceptance criteria and traceability](docs/planning/original-poc-acceptance-criteria.md)
- [Requirements gap audit](docs/planning/poc-requirements-gap-audit.md)
- [Azure Local platform boundary research](docs/planning/azure-local-platform-boundary-research.md)
- [Kubernetes and Terraform integration results](docs/planning/kubernetes-terraform-integration-test-results.md)
- [Deployment completion summary](docs/POC-deployment-summary.md)
- [Capstone definition for the next sprint](capstone/README.md)

## Repository Layout

- `docs/` contains current reference material, evidence, runbooks, and future design.
- `decisions/` contains the durable engineering decisions made during the build.
- `archive/` preserves superseded planning, requests, checklists, and point-in-time build material.
- `scripts/`, `infra/`, and `tests/` contain reusable source artifacts; generated output, secrets, downloaded media, and
  drivers remain excluded from the curated source surface.
