---
title: "Azure Local Learning Environment capstone"
domain: [docs]
layer: [application]
type: index
status: current
proof: documented
audience: [engineer, leadership]
tags: [index, capstone, presentation]
updated: 2026-08-25
---

# Azure Local Learning Environment capstone

This directory is the product-definition area for the Azure Local capstone. It turns the proven POC artifacts
into an integrated learning environment that visibly evolves as each technology layer is introduced and verified.

The capstone is not a slide deck and it is not an unrestricted operations console. It is an evidence-led product
that explains real Azure Local, GitHub Actions, Terraform, container, and Kubernetes behavior.

## Documents

- [Vision design questions](vision-design-questions.md): **start here.** Settled research, open decisions, and an answer sheet that converts the vision into a build specification.
- [Product architecture](product-architecture.md): managed shell, internal build pane, command stream, workspace model, and safety tiers.
- [Build roadmap](build-roadmap.md): staged implementation and evidence dependencies.

## Current preview

The live dashboard has an initial `Under the hood` flow canvas that combines recorded Terraform lifecycle evidence
with live AKS worker, ClusterIP Service, EndpointSlice, and pod state. It is the first small preview of the
capstone main build pane; the managed shell and workspace experience remain next-sprint work.

## Existing evidence

The capstone consumes, but does not replace, the existing project records:

- [Kubernetes and Terraform integration test results](../docs/planning/kubernetes-terraform-integration-test-results.md)
- [Terraform and CI/CD capstone plan](terraform-cicd-plan.md)
- [Self-building Azure Local learning demo](self-building-learning-demo.md)
- [Command Center design direction](command-center-design.md)
- [Self-building demo interaction research](interaction-research.md)

