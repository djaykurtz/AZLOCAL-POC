---
title: "Decisions"
domain: [docs]
layer: []
type: index
status: current
proof: documented
audience: [engineer]
tags: [index, adr, decision-log, ooda]
updated: 2026-09-11
---

# Decisions

Lightweight decision log for the Azure Local POC.

## Index

- [0001 - Arc control-plane region = southcentralus](0001-arc-control-plane-region.md)
- [0002 - VT-x/SLAT false positive](0002-vtx-slat-false-positive.md)
- [0003 - Storage spec lock](0003-storage-spec-lock.md)
- [0004 - Four-node functional POC scope](0004-four-node-functional-poc-scope.md)
- [0005 - Plan-only Terraform/Docker/Kubernetes test surface](0005-plan-only-tooling-test-surface.md)
- [0006 - Docker operations run in disposable VM, not host nodes](0006-docker-operations-disposable-vm.md)
- [0007 - Recover storage mode by reimaging after AHCI/Non-RAID](0007-reimage-after-ahci-storage-mode.md)
- [0008 - ASUS card mechanically incompatible with 1U chassis](0008-asus-card-mechanical-incompatibility.md)
- [0009 - Node01 ISO recipe LCU skew](0009-node01-iso-recipe-lcu-skew.md)
- [0010 - NetAdapter failure was disabled Mellanox NICs, not missing hardware](0010-mellanox-nic-disabled-not-missing.md)
- [0011 - Standardize on 3 data NVMe disks per node](0011-three-data-disks-per-node.md)
- [0012 - Buy two-failure tolerance with a cloud witness, not with node 03](0012-cloud-witness-over-fifth-node.md)

## Why

We keep running into "wait, why did we pick X?" questions weeks later.
Each significant decision deserves a one-page record with the **evidence
that backed it at the time** so anyone (including future-us) can:

1. understand the call without re-doing the research,
2. defend it to a reviewer with primary sources,
3. know when it should be revisited.

## Format: OODA

We use the [OODA loop](https://en.wikipedia.org/wiki/OODA_loop)
(Observe / Orient / Decide / Act) because it forces evidence and
interpretation to be separated from the call itself - which is exactly
the failure mode of "we did X because it felt right" documents.

Every decision file follows this skeleton:

```markdown
# {NNNN} - {short title}

- **Status**: Active | Superseded by {NNNN} | Deprecated
- **Date**: YYYY-MM-DD
- **Owner**: who made the call
- **Revisit when**: condition that should trigger a re-read

## Observe
Raw facts. Doc quotes, error messages, measurements, CLI output.
Each item linked to a source (URL or repo file).

## Orient
Interpretation. What the observations mean. Alternatives considered.
Tradeoffs (latency vs documentation strength vs blast radius, etc.).

## Decide
The call. One sentence. No hedging.

## Act
What was done to implement. What validation was performed. Follow-up
tasks. Files/scripts touched.
```

## File naming

`NNNN-kebab-case-summary.md` where `NNNN` is a zero-padded sequence
number that never gets reused. If a decision is superseded, write a
new file with the next number and mark the old one
`Status: Superseded by NNNN`.

## Why Markdown (not .txt like the rest of the repo)

Decisions cite URLs, embed tables of alternatives, and need stable
heading structure for review. Markdown serves those; plain text doesn't.
Runbooks and checklists stay as `.txt`.

