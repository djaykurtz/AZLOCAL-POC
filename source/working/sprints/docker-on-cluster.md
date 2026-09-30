---
title: "Sprint S4 - Test Docker container support on cluster nodes"
domain: [containers]
layer: [application]
type: plan
status: current
proof: proven
audience: [engineer]
tags: [sprint, docker, guest-vm, sprint-s4]
updated: 2026-08-28
---

# Sprint S4 - Test Docker container support on cluster nodes

Sprint S4 (PoC Validation Part 2). Status: complete - Docker CE 29.x and Compose v5.3.1 ran on Rocky Linux 10.2 in a guest VM on the cluster on 2026-07-30, with Dockge answering HTTP 200 from off the box. See docs/runbooks/docker-dockge-on-rocky-runbook.md.
Cluster: AZL-CLUSTER-01. Custom location: azl-cluster-01-cl.

## Objective

Prove normal Docker container operations work in the POC. Per ADR 0006, Docker is NOT installed on the
Azure Local host nodes (that is unsupported and would put a container runtime on the cluster OS). Docker
runs inside a disposable Linux VM created on the cluster (the S1 VM), and this sprint exercises the
full container lifecycle there.

## Why not on the host nodes

- Azure Local host OS is a locked appliance surface; adding Docker/moby to it is out of support and risks
  the S2D/cluster/Arc stack. The cluster runs containers the supported way via AKS on Azure Local (S5).
- "Container support on cluster nodes" for this POC = containers running on VMs/AKS hosted BY the cluster,
  not dockerd on the bare hosts.

## Prerequisites

- A running Linux VM on the cluster (sprint S1, image path B). This is the blocker.
- Guest outbound to mcr.microsoft.com and registry-1.docker.io (already proven at the host level; confirm
  from inside the guest).

## Procedure

1. Install Docker Engine in the test VM (get.docker.com convenience script or distro package).
   Result: docker --version and docker info clean, dockerd running.
2. Pull + run: docker run --rm hello-world; docker run -d -p 8080:80 nginx.
   Result: image pull from MCR/Docker Hub, container Up, port mapped.
3. Build + tag: build tests/docker/smoke/Dockerfile inside the VM, tag it.
   Result: local image built from our smoke Dockerfile.
4. Inspect + logs + exec: docker ps/inspect/logs/exec into the running container.
   Result: introspection works.
5. Lifecycle: stop, start, restart, rm the container; rmi the image.
   Result: all state transitions succeed.
6. Optional publish: push the built image to an ACR (needs an ACR + login); or skip if no registry.
   Result: push/pull round-trip if a registry is available.

## Success criteria

- Docker Engine installs and runs in the guest.
- Pull, run, build, tag, inspect, logs, exec, stop, start, restart, rm all succeed.
- No Docker is installed on any Azure Local host node.

## Evidence

- out/_docker-smoke-*.txt (command transcript from the guest).
- Reuse scripts/Invoke-DockerSmokeBuild.ps1 for the local static/build preflight before the guest run.

## Risks / notes

- Docker Hub rate limits: prefer MCR mirrors (mcr.microsoft.com) for base images where possible.
- This is POC proof only: no HA, DR, or performance claim (ADR 0004/0005).

