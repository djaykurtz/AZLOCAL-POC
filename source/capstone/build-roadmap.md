---
title: "Build roadmap"
domain: [docs]
layer: [application]
type: plan
status: draft
proof: not-attempted
audience: [engineer]
tags: [capstone, roadmap]
updated: 2026-08-20
---

# Build roadmap

## Phase 1 - Static shell and verified evidence

- Create the shell layout: header, stage rail, main pane, command stream, and control desk.
- Add `stages.json` and reviewed Terraform/Kubernetes evidence artifacts.
- Mount evidence through a read-only ConfigMap.
- Render the Terraform lifecycle and Kubernetes integration results.

Pass: a viewer can move from a plain entry state to verified Terraform and Kubernetes stages without any write
credential or live infrastructure action.

### Current POC preview

The existing dashboard now includes a verified `Under the hood` flow canvas. It is the first small implementation
of the main build-pane concept and renders:

```text
Source validation (planned evidence)
-> Terraform lifecycle (verified evidence)
-> AKS worker (live placement)
-> ClusterIP Service (live endpoints)
-> Kubernetes pods (live desired/ready state)
```

The preview is delivered through the existing ConfigMap-backed application and reads the live Kubernetes API using
the namespace-scoped read-only ServiceAccount. It does not yet provide workspace sessions, stage unlocks, a command
stream, a custom image, or CI artifact ingestion.

## Phase 2 - Live Kubernetes integration

- Move the current dashboard code into a versioned application source tree and Dockerfile.
- Keep the existing read-only Kubernetes API integration.
- Render Deployment, ReplicaSet, pod, EndpointSlice, and Event facts as live modules.
- Add stale-data and missing-evidence states.

Pass: the shell identifies live Kubernetes data separately from recorded evidence and retains the last good state
when a read fails.

## Phase 3 - Operator-present demonstration mode

- Add locked action cards for the scale and self-heal runbooks.
- Add an operator-facing evidence capture flow that records the resulting Event and endpoint changes.
- Restore the dashboard to two replicas after every demonstration.

Pass: the page makes the demonstration intelligible without gaining Kubernetes write access.

## Phase 4 - Pipeline evidence ingestion

- Push the curated source-only GitHub Actions workflow.
- Define the sanitized workflow-result artifact contract.
- Add a pipeline evidence ConfigMap and display commit SHA, job result, and timestamp.

Pass: a source-validation run appears in the command stream and unlocks the CI stage.

## Phase 5 - Approval-gated delivery

- Decide remote state, GitHub OIDC, registry, and protected environments.
- Add narrow pipeline identities and record exact RBAC in the permissions register.
- Let approved workflows publish evidence artifacts and update only the dashboard deployment or evidence ConfigMap.

Pass: the page reports approved pipeline progress, but privileged actions remain outside the browser process.

