---
title: "Documentation Guide"
domain: [docs]
layer: []
type: index
status: current
proof: documented
audience: [engineer, operator, leadership]
tags: [index, navigation, documentation-guide]
updated: 2026-08-28
---

# Documentation Guide

## What This Covers

Reproducing a baseline to get a working environment. That is the whole job.

If a document does not help someone at a terminal stand this cluster up, operate it, or understand a boundary they
will hit, it does not belong here. Product design, creative direction, and demonstration material live elsewhere.

This folder is the published set. Everything in it should be worth citing months from now. Sprint records, forward
work plans, and point-in-time findings are still tracked, but they live in [`working/`](../working/README.md)
because they document how the work went rather than how to repeat it.

This directory also excludes the pre-deployment trackers, one-time requests, wizard snapshots, and
point-in-time build procedures now preserved under [`archive/`](../archive/README.txt).

## Find By Topic

Every document carries YAML frontmatter with a controlled set of facets, and
[the tag index](tags.md) is generated from it.

| Facet | Values | What it answers |
| --- | --- | --- |
| `type` | decision, runbook, reference, evidence, plan, postmortem, index | What kind of document is this |
| `depth` | quickref, guide | How much hand-holding. Procedural documents only |
| `proof` | proven, documented, blocked, not-attempted | Was this demonstrated on real hardware |
| `domain` | platform, storage, network, identity, security, compute, containers, iac, observability, delivery, docs | Which technical area |
| `layer` | hardware, firmware, os, cluster, arc, kubernetes, application | Where in the stack |
| `status` | current, superseded, draft | Is this still authoritative |
| `audience` | leadership, engineer, operator | Who it is written for |

The `proof` facet is the important one. This project's credibility rests on being explicit about what was
demonstrated versus what was only designed, so that distinction is queryable rather than buried in prose.

The `depth` facet exists because the two reading modes are different jobs. A **quickref** assumes you know the
system and just need the exact commands in order. A **guide** assumes you are doing this for the first time and
need the failure modes called out. Writing one document that tries to be both serves neither.

Regenerate the index with `scripts\Build-DocIndex.ps1` after adding or retagging a document.

## Start With The Story

- [Current POC status](../STATUS.md)
- [Project narrative and proven outcomes](../README.md)
- [Deployment completion summary](POC-deployment-summary.md)
- [Engineering decisions](decisions/README.md)

## Evidence And Scope

- [Original acceptance criteria](planning/original-poc-acceptance-criteria.md)
- [Requirements gap audit](planning/poc-requirements-gap-audit.md)
- [Platform boundary research](planning/azure-local-platform-boundary-research.md)
- [Kubernetes and Terraform integration results](planning/kubernetes-terraform-integration-test-results.md)
- [Permissions and capability register](access/azure-permissions-and-capability-register.md)
- [Prerequisites from other roles](prerequisites.md)

## First Workload

The hello world that proves the environment works. Standing up infrastructure shows it exists. This shows it can
host and serve something, which is the most basic use beyond a structured environment.

- [Kubernetes-hosted Azure Local status dashboard](planning/kubernetes-self-referential-dashboard.md)

## Reusable Operations

Split by `depth`, because they are two different jobs.

**Quick references.** You know the system and need the exact commands in order.

- [PIM elevation routine](runbooks/pim-elevation-routine.md)
- [Windows Server 2025 demo quick reference](runbooks/ws2025-azure-local-demo-quickref.md)
- [Credential map](access/credential-map.md)
- [Storage switch configuration](network/storage-switch-config.md)
- [BIOS ideal state per node](storage-imaging/bios-ideal-state.md)

**Guides.** First time through, with the failure modes called out.

- [VM image and lifecycle runbook](runbooks/custom-vm-image-and-test-runbook.md)
- [Docker and Dockge runbook](runbooks/docker-dockge-on-rocky-runbook.md)
- [Node reimage checklist](storage-imaging/reimage-checklist.md)
- [USB install media and Secure Boot](storage-imaging/usb-install-secureboot.md)
- [Node 01 retired NVMe recovery boundary](runbooks/node01-retired-nvme-recovery.md)
- [Resource migration and deletion protocol](runbooks/resource-migration-deletion-protocol.md)
- [The sppsvc memory leak on Azure Local nodes](runbooks/sppsvc-memory-leak.md)

## Adjacent Work

The capstone is a separate product. It takes creative work, planning, and direction, rather than reproducing a
baseline, so its design material lives in [`capstone/`](../capstone/README.md) and not here.

- [Terraform, Docker, AKS, and Azure Local responsibility model](planning/terraform-docker-aks-responsibility-model.md)
- [Repository and delivery pipeline usage](pipelines/README.md)
- [Where Azure Local changes a delivery pipeline](pipelines/pipeline-differences-azure-local-vs-azure.md)

## Archive Policy

Move material to `archive/` when it is a one-time build aid, a sent request, a superseded plan, a point-in-time
diagnostic, or a historical snapshot. Move it to `working/` when it is a real record of how the work went but not
something a future reader would cite. Keep a document here when it explains an accepted decision, records executed
proof, or is a safe reusable operation.

