---
title: "Acceptance criteria verification worksheet"
domain: [platform]
layer: []
type: reference
status: current
proof: proven
audience: [leadership, engineer]
tags: [acceptance-criteria, traceability, verification, evidence, presentation]
updated: 2026-09-09
---

# Acceptance criteria verification worksheet

## Why this exists

The presentation grades the project against the acceptance criteria. At least five of those
gradings were written from memory or from our own planning documents rather than from the source,
and in four cases that made the result look worse than it was. One of them, the database item,
states a requirement that was never made.

This worksheet exists so that every claim can be checked against three things: what was actually
asked, what evidence exists that it happened, and where the deck shows it. Nothing here should be
taken on trust, including the parts written by the person who built the deck.

## How to read the verification column

| Mark | Meaning |
| --- | --- |
| `READ` | The evidence file was opened and it supports the claim in the row. |
| `POINTER` | The file exists and is named for this topic, but nobody has read it back against this claim. |
| `NONE` | No evidence file has been found. |

`POINTER` is not a soft yes. It is the same state the database item was in before anyone checked,
and that one turned out to be wrong. No row is left at `POINTER`. If one appears again, treat it as
unverified until someone opens the file.

## The source

The only authoritative statement of what was asked is
[original-poc-acceptance-criteria.md](original-poc-acceptance-criteria.md), section
"Original criteria". Quotations below are verbatim from it. Where the deck's wording differs from
the source, the source wins.

One more document turned up during verification and it deserves naming here rather than being
buried in a row. [poc-requirements-gap-audit.md](poc-requirements-gap-audit.md), dated 2026-08-19,
already graded every criterion against executed evidence, using four outcomes rather than a mark:
proven, partial, architecture substitution, and deferred or blocked. It agrees with the deck almost
everywhere. Where it does not, it is named in the row. It should have been the first thing read
when the deck's ledger was written.

---

## Sprint 1

### S1. Fact finding

> "Sync with the network and datacenter teams to familiarize with resources."

- **Evidence:** [storage-switch-config.md](../network/storage-switch-config.md),
  [external-dependencies-and-poc-lessons.md](external-dependencies-and-poc-lessons.md) (storage
  fabric row). Verification: `READ`.
- The switch config file is not a plan. It is a transcription of live `show run int` and
  `show int trunk` output from both Arista 7050s, with a per node port map, the MAC on each port,
  and the confirmed per port stanza including `mtu 9214`, `priority-flow-control priority 3
  no-drop`, and trunk mode carrying 711 on SW1 and 712 on SW2. It also records two things that were
  learned the hard way rather than read: no LACP on storage ports, verified by host packet capture
  where "LACPDUs went from ~70 to 0 after removal", and no native storage VLAN, because "setting
  native 711/712 breaks tagged delivery".
- The teams half of the requirement is evidenced by the storage fabric row of the dependencies
  document, which names "Network/switch team plus rack or smart-hands team" as owners and records
  the outcome: "Storage validation exposed reversed adapter naming on three nodes and missing trunk
  mode on SW2. Tagged VLAN 711 and 712 tests passed only after adapter renaming and switch
  correction."
- **Deck:** movement 00. Three commands on screen: `Get-NetAdapter`, an LLDP capture with
  `pktmon filter add LLDP`, and `Test-NetConnection` for the east-west check.
- **Deck mark:** `v`. Supported. The requirement said familiarize, and the evidence goes further
  than familiarity: a switch was found misconfigured and corrected.
- **Note.** `docs/network/set-vs-lacp-explainer.md` was cited in an earlier draft of this row.
  The LACP finding it explains is carried by the switch config file directly, quoted above, so the
  row no longer depends on it.

## Minimum viable product

### MVP1. Three or more nodes

> "Three or more compute nodes imaged with Azure Stack HCI and connected to an Azure subscription
> as an Azure Local instance."

- **Evidence:** [POC-deployment-summary.md](../POC-deployment-summary.md). Verification: `READ`.
- Confirms the cluster, the four nodes, and the headline: "Deployment completed: 2026-07-27 20:05
  (build wall time ~2h13m, 17:52-20:05)", "Final state: provisioningState=Succeeded", and "Within
  these 54 steps there were no failures and no retries."
- **Deck:** movement 02, ECE steps 16, 17 and 40 of 54, plus the headline 54 of 54 in 2h 13m.
- **Deck mark:** `v`. Four nodes exceeds the stated bar of three.
- **Precision issue.** The deck says "54 of 54 steps **Succeeded**". Counting the step lines gives
  **53 Success and 1 Skipped**, the skip being step 0.2 "Validate environment", which was skipped
  because a full environment re-validation pass had already run separately. Zero failed. The exact
  claim is "54 of 54 completed, none failed". This is small, but it is the single most repeated
  number in the deck.
- **Caveat the source raises itself, and the deck should not lose.** "That is not the same as
  saying the deployment never needed retrying. Getting to a clean pass took repeated validation
  cycles and earlier attempts, and quoting 'zero retries' without that qualifier overstates what
  happened." The intro does carry this, with "The deployment was never the hard part. Getting four
  machines to the starting line took two months."

### Six node deployment target: checked, and the deck is right

The deck carries a separate row "Six node deployment target" marked `~`, note "four by scope
decision, 03 and 05 out".

- **Evidence:** [0004-four-node-functional-poc-scope.md](../decisions/0004-four-node-functional-poc-scope.md).
  Verification: `READ`.
- Dated 2026-06-18, status Active, owner labadmin. It decides: "Run the Azure Local POC as a
  4-node functional proof on AZL-NODE-01..04, with AZL-NODE-05/06 deferred as an optional
  scale-out path." It records the goal as "I just need to test if it works", and states that nodes
  05 and 06 are "useful as future scale-out evidence, not as a first-cluster prerequisite".
- **Withdrawn.** An earlier draft of this worksheet suggested this might be a `v` being given away,
  on the grounds that "six-node deployment target" is a Sprint 2 heading rather than a stated
  requirement. That origin is correct but the conclusion was not. Six nodes were not deployed, so
  `v` would be false. A dated descope with a named owner is exactly what `~` means, and the row is
  carried from the project's own traceability table rather than invented by the deck.
- One detail worth noting: ADR 0004 planned nodes 01 to 04. The cluster that exists is 01, 02, 04
  and 06, because node 03 later failed to enumerate its drives. The deck's note matches the final
  state rather than the original plan, which is the right choice.

## Sprint 2

### S2. Subscription, resource groups, security

> "Subscription for the POC: `contoso-lab-sub`."
> "Create resource groups."
> "Deploy resources while keeping security and security compliance KPIs in mind."

- **Evidence:** [azure-permissions-and-capability-register.md](../access/azure-permissions-and-capability-register.md),
  [security-posture-and-boundaries.md](../access/security-posture-and-boundaries.md),
  [POC-deployment-summary.md](../POC-deployment-summary.md). Verification: `READ`.
- The named subscription is confirmed. The deployment summary records "Subscription:
  contoso-lab-sub (00000000-0000-0000-0000-000000000001)" and the resource group
  `rg-azlocal-poc-001` appears throughout.
- The register is stronger than the requirement asked for. It is a table of every capability with a
  least privilege route, a practical maximum, a scope, and a current position, plus a second table
  of confirmed denials with dates. It includes the denials that were never escalated, which is the
  part most registers leave out.
- The security half is evidenced too, and the posture document opens by explaining what it is not:
  "A threat model is a structured exercise... Producing a shallow one that nobody can defend would
  be worse than producing nothing." It then records the three layers, and the residual risk section
  is headed "DECISION REQUIRED" because accepting a risk "is a judgment, not a fact".
- The phrase "security compliance" does not appear in either file. What does appear is the concrete thing a compliance review would
  have flagged: the `SkipSecurityMonitoringAgent=true` opt out at resource and resource group scope,
  tracked, applied because an incumbent corporate security monitoring agent held the single
  monitoring agent slot and blocked Azure Local's own observability.
- **Deck:** movement 09 shows the resource group at 55 resources. The BUILT portal blade on
  movement 00 shows the same group empty.
- **Deck mark:** `v`. Supported.
- **Gap, unchanged and now confirmed.** The security half of this requirement is real, documented,
  and completely invisible in the deck. The security monitoring extension opt out in particular is the single item most
  likely to draw a question from a reviewer, and the deck never mentions it. The gap audit
  independently reaches the same place, grading this "Proven for POC baseline" with "Residual risk
  sign-off outstanding".

## Sprint 3

### S3a. IaaS VM deployment, manual and automated

> "Infrastructure as a Service virtual machine roles can be deployed manually and through
> automation or scripting from Azure Portal, Azure CLI, and PowerShell."

- **Evidence:** [terraform-against-cluster.md](../../working/sprints/terraform-against-cluster.md),
  [custom-vm-image-and-test-runbook.md](../runbooks/custom-vm-image-and-test-runbook.md),
  [kubernetes-terraform-integration-test-results.md](kubernetes-terraform-integration-test-results.md).
  Verification: `READ`.
- Sprint S6 states its own outcome in the header: "Status: complete - human-operated lifecycle
  proven; pipeline identity and remote state deferred." The integration results record the full
  lifecycle, `3 to add, 0 to change, 0 to destroy`, the VM landing `Online` on `AZL-NODE-04`,
  and a final `terraform plan -destroy` with no objects left.
- **The surface gap is now measured, and it is narrower than I claimed.** The requirement names
  three surfaces, Portal, CLI and PowerShell.
  - **CLI: proven.** The runbook is built on `az stack-hci-vm image create`, `az stack-hci-vm
    create`, and `az stack-hci-vm network nic show`, with expected output for each.
  - **PowerShell: proven.** `New-AzLocalGalleryImage.ps1`, `New-AzLocalTestVm.ps1`,
    `Invoke-VmLifecycle.ps1` and `Invoke-LiveMigrationTest.ps1` drive create, lifecycle and
    migration end to end.
  - **Portal: not proven.** Searching the whole `docs/` tree for "Azure Portal" returns four hits.
    One is this worksheet, one is the source criteria, and two are in the reimage checklist, where
    the portal is used to download the Azure Stack HCI OS ISO. No VM was ever created through the
    portal, or at least no record of one exists.
- **So the corrected gap is:** two of the three named surfaces are proven and the third is not,
  and the deck shows a fourth surface, Terraform, which was never asked for. That is a better
  result than the earlier draft implied, and it is still not what the requirement said.

### S3b. Corporate network connectivity

> "IaaS VMs running on the Azure Local instance can connect to, and be connected to from,
> corporate network resources."

- **Evidence:** [docker-dockge-on-rocky-runbook.md](../runbooks/docker-dockge-on-rocky-runbook.md).
  Verification: `READ`.
- The dated snapshot section records "Dockge healthy, http 200 locally and from the DevBox", which
  is the inbound half: a corporate workstation reaching a guest running on the cluster. It also
  records "Arc: HybridCompute machine Connected, Azure Connected Machine Agent 1.66".
- **Deck:** movement 06, `curl` to the guest on port 5001 from outside the machine.
- **Deck mark:** `v`. Supported in both directions.
- **Withdrawn.** An earlier draft of this row said outbound to a corporate resource was never
  tested, and proposed a test to close it. That gap does not exist. The tenant logical network
  `AZL-CLUSTER-01-TenantLNET` hands every guest `dnsServers: 10.20.50.50, 10.20.10.50`, checked live
  on 2026-09-09. Those are the corporate resolvers, named as such in the deployment wizard answers:
  "10.20.50.50, 10.20.10.50 (corp resolvers, confirmed 2026-05-27)". Every name the guest resolved
  was a query to a corporate resource, and the guest resolved plenty, because it installed Docker
  from `download.docker.com` and onboarded an Arc agent. `Test-Reachability.ps1` even carries a
  purpose-built check for it, tagged `corp`.
- The bar I applied was stricter than the sentence sets, and the evidence was sitting in the
  network definition the whole time. The traceability doc already graded this "Complete for POC"
  and it was right.

## Goals and targets of opportunity

### G1. Docker and Kubernetes

> "Docker and Kubernetes container clusters or swarms."
> "On-premises hosting of containerized workloads with high availability and Azure management
> control-plane tools."

- **Evidence:** [docker-on-cluster.md](../../working/sprints/docker-on-cluster.md),
  [kubernetes-terraform-integration-test-results.md](kubernetes-terraform-integration-test-results.md),
  [docker-dockge-on-rocky-runbook.md](../runbooks/docker-dockge-on-rocky-runbook.md).
  Verification: `READ`.
- Docker. Sprint S4 records its own result in the header: "Status: complete - Docker CE 29.x and
  Compose v5.3.1 ran on Rocky Linux 10.2 in a guest VM on the cluster on 2026-07-30, with Dockge
  answering HTTP 200 from off the box."
- Kubernetes. The integration results record six named tests, all Pass, on the real AKS Arc
  cluster: baseline `2/2`, scale to `3/3`, thirty in-cluster requests distributed `17/13` across two
  ready backends, a deleted pod replaced and the Deployment back to `3/3`, and a restore to `2/2`.
- **Deck:** movement 03 `az aksarc create` and `kubectl get nodes`. Movement 06
  `docker run hello-world` and `docker compose up -d`.
- **Deck mark:** `v` on both rows. Supported.
- **Two qualifications the deck does not carry, and one of them is interesting.**
  1. The criterion says "container clusters or swarms". Docker Swarm was never tested. The "or"
     makes that fine, but nobody should hear the word swarm and assume it was proven.
  2. Docker is deliberately **not** on the Azure Local hosts. Sprint S4 is explicit about why:
     "Azure Local host OS is a locked appliance surface; adding Docker/moby to it is out of support
     and risks the S2D/cluster/Arc stack." So "Docker on the cluster" means Docker in a guest VM
     that the cluster runs. That is the correct reading of the requirement and it is a decision
     worth showing, not hiding. It is recorded in ADR 0006.
- **Evidence quality note the source raises itself.** The gap audit grades Docker "Proven in guest,
  evidence consolidation needed", and asks for "a concise standard Docker lifecycle transcript if
  the old evidence is not already curated". Build, tag and push were part of the sprint plan and
  are not in the runbook snapshot. The audit says so directly: "custom image build/publish not
  proven." The deck shows `docker run` and `docker compose up`, which is exactly what the evidence
  supports, so the deck is not overclaiming. The sprint plan is.

### G2. Azure integrated load balancer

> "Azure integrated load balancer in front of IIS, web-server, or similar role VMs."
> "Provide high-availability tools and services for future infrastructure deployments."

- **Evidence:** [loadbalancer-scaleset.md](../../working/sprints/loadbalancer-scaleset.md),
  `docs/planning/external-dependencies-and-poc-lessons.md`. Verification: `READ`.
- The sprint states the framing directly: "there is no Azure Standard Load Balancer resource and no
  Azure Virtual Machine Scale Set resource on Azure Local. The equivalent capabilities are delivered
  differently, and this sprint proves those equivalents."
- It also records why the VIP is absent. The `LoadBalancer` Service "correctly remained
  `EXTERNAL-IP <pending>` because no MetalLB IP pool was configured", MetalLB needs
  `Microsoft.KubernetesRuntime` at subscription scope, and "the current user's RG-scoped AKS Arc
  Contributor/UAA roles cannot register it". Confirmed live on 2026-09-08: still `NotRegistered`.
- **Deck:** movement 04, thirty requests distributed across ready replicas.
- **Deck mark:** `~`. **Accurate.** The note was "internal Service proven, external VIP blocked" and
  is now "internal Service proven. An external VIP needs a subscription action we chose not to
  request".
- **Why the note changed, 2026-09-09.** Blocked is passive and it is not what the record says. The
  registration was denied, and then a decision was made. The dependencies document has a heading
  called POC decision under which it says "Do not request additional external permission for this
  POC" and "This is a valid POC boundary, not a cluster failure". The permissions register logs it
  as "Denied. No external request will be made for this POC" and "intentionally not escalated".
  Every route to exposing this cluster more widely is well understood technology with a known cost,
  and none of it would have taught the project anything about Azure Local. Saying that out loud is
  both truer and stronger than letting the room hear that we hit a wall and stopped.
- **Remaining gap:** the source says in front of role VMs. We proved it in front of pods. The
  sprint shows this was a deliberate documented equivalence rather than an oversight, so it is a
  wording gap on screen rather than a substantive one. Still worth stating, because the audience
  cannot see the sprint.

### G3. VM Availability Sets

> "VM Availability Sets."
> "Increase service availability/resiliency with VM groups serving a role/service while isolated
> to different fault/update domains."

- **Evidence:** [ws2025-azure-local-demo-quickref.md](../runbooks/ws2025-azure-local-demo-quickref.md),
  [node-failure-recovery.md](../../working/sprints/node-failure-recovery.md),
  [poc-requirements-gap-audit.md](poc-requirements-gap-audit.md). Verification: `READ`.
- The quickref carries the measurements. Live migration of `ws2025-core-01` from AZL-NODE-01 to
  AZL-NODE-04 in **16.4 seconds**, role `Online` throughout, proven by VMMS event `20418` and
  the **absence** of a `18502` power-off or `18504` reset. It also warns against the obvious wrong
  check: "Do not use `(Get-VM).Uptime` as the continuity check. That counter resets on the
  destination host." Planned drain took 34.8 seconds, both guests evacuated, pool stayed `Healthy`.
- The separate 16.7 second figure the deck uses on movement 07 is a different move, the AKS worker
  on 2026-09-01, recorded in the gap audit. Both numbers are real and they are not the same event.
- **Deck:** movement 07 live migration, movement 08 node leaving and pool repair.
- **Deck mark:** `=` met by different means. The Azure resource does not exist on Azure Local.
  Supported, and the gap audit uses the same words: "Architecture substitution, intent proven".
- **Finding: movement 08 does not match the recorded test, and it should.** The deck's log panel
  shows `Get-ClusterNode` returning `AZL-NODE-04   Down`, a storage job at `resync 62%`, `3
  repair jobs Running`, and a duration of `5m 12s`. What was actually executed on 2026-08-13 was
  `Invoke-NodeFailureTest.ps1 -TargetNode AZL-NODE-01 -Mode Reboot`, and the record says: "Node
  01 went `Down` and later rejoined after approximately 26 minutes. Storage temporarily reported
  `Warning`; all six virtual disks returned to `Healthy`. `ws2025-core-01` recovered automatically
  as `Running` on `azl-node-02`." Wrong node, and a recovery time off by a factor of five. The
  62 percent and the three jobs are not in the record at all.
- **Finding: it was a reboot, not a power cut. Raised, and closed.** Sprint S3 splits the work
  into a graceful stage and an ungraceful one, and only the graceful stage ran. Its own status line
  says so: "A manual hard power-loss test remains unexecuted and must follow the recovery-boundary
  plan's no-go gates."
  - **Decision, 2026-09-09, project owner.** Not a gap and not worth stating on screen. A hard
    power-off through iDRAC is available and has never been worth the risk to simulate. The thing
    under test is whether the cluster copes with a resource becoming unavailable, and a reboot makes
    it unavailable. On hardware already running at the bare minimum, that is a sufficient proof of
    concept. The deck says "a node left the cluster" and that is accurate.
  - Recorded here so nobody re-raises it as an omission. The distinction is real and it is not
    material at this scope.
- **Finding: the stated prerequisite was not met.** Sprint S3 lists "A cluster witness
  configured, so quorum survives the loss." The cluster has no witness. Quorum is Majority across
  four nodes, verified live on 2026-09-04. One node down leaves three of four and holds. Two nodes
  down leaves two of four and does not. The test that ran only ever removed one node, so nothing
  observed is wrong, but the resiliency claim has a narrower edge than the sprint assumed.
- **The boundary the deck already states well.** Movement 07's fourth panel is marked BOUNDARY and
  reads "This survives maintenance. It does not survive losing that node." The gap audit says the
  same thing in the requirements matrix: "Availability Sets protect against host loss, not host
  maintenance." That is the honest framing and it is already on screen.

### G4. VM Scale Sets

> "VM Scale Sets."
> "Enable auto-scale up/down of VM counts for a role based on service demand."

- **Evidence:** [loadbalancer-scaleset.md](../../working/sprints/loadbalancer-scaleset.md).
  Verification: `READ`.
- The sprint records what passed: "one Linux worker scheduled the two-replica smoke deployment,
  manual replica scale passed, and deleting a pod triggered successful replacement". Auto-scale is
  not among the things it claims. The traceability doc separately records HPA as not validated,
  because the Metrics API was unavailable.
- **Deck:** movement 04, `kubectl scale deployment/azure-local-dashboard --replicas=3`.
- **Deck mark:** two rows, `VM Scale Sets` marked `=` and `Auto-scale on demand` marked `-`.
- **Withdrawn.** An earlier draft of this worksheet called the split "one source requirement
  producing two deck rows and one of only two hard deferrals", implying it manufactured a failure.
  The evidence does not support that. Manual scale was proven and auto-scale was not, and those are
  genuinely different claims. Collapsing them into one row would either overstate auto-scale or
  understate the scale set equivalent. The split is the honest presentation.

### G5. Azure database software as a service

> "Azure database software as a service."
> "Deploy highly available/scalable databases with less manual SQL/OS maintenance."

- **Evidence:** `NONE`. Never attempted.
- **Deck:** movement 10, marked `-` deferred.
- **Deck note is wrong.** It reads "asked for SQL Managed Instance with failover". Neither
  "SQL Managed Instance" nor "failover" appears in the source. That phrasing comes from our own
  planning file (the POC plan, not published), which recorded the implementation
  **we chose**, not the requirement.
- The accurate part of the note is "no workload chosen". That is the real reason.
- The actual bar is three properties: highly available, scalable, and less manual SQL and OS
  maintenance. SQL Managed Instance enabled by Arc is the heaviest way to meet it, not the only
  way. `Microsoft.AzureArcData` is confirmed `Registered`, so this was never a permissions block.

### G6. Azure Storage Services

> "Azure Storage Services."
> "Test locally hosted blob, queue, and table storage."
> "Enable tools/services using Azure Storage without prematurely accruing cloud operating costs."

- **Evidence:** [omitted-elements-and-technology-equivalents.md](omitted-elements-and-technology-equivalents.md).
  Verification: `READ`.
- Its row for these services reads: "Azure Blob/Queue/Table services | **No application workload
  selected; these are Azure services, not native S2D APIs** | Object, queue, and table service APIs
  for application development | ... | **S2D storage foundation is operational only** | Define
  whether cloud Azure Storage, local emulation, or a workload-specific service is required."
- **Deck:** movement 10, marked `=` met by different means, note "asked for a storage account.
  S2D presents block storage, so cluster volumes carry the data".
- **The deck overclaims this one.** Your own equivalents document says blob, queue and table are
  **not S2D APIs** and that S2D is the foundation **only**, with the next step still being to decide
  what is actually wanted. That is a deferral, not a substitution.
  [original-poc-acceptance-criteria.md](original-poc-acceptance-criteria.md) agrees, grading it
  "Opportunity deferred".
- Note the direction. Every other finding so far made the deck look harsh on itself. This one is
  the deck being too generous, and it is the only `=` that two source documents contradict.

### G7. Azure DevOps pipelines and hybrid workers

> "Azure DevOps pipelines and hybrid workers."
> "Enable tighter use of local compute for compile, pipelines, and tools such as Ansible or
> Terraform."

- **Evidence:** `.github/workflows/validate.yml`,
  [github-actions-and-repo-usage.md](../pipelines/github-actions-and-repo-usage.md),
  `scripts/Test-RepoPublishSafety.ps1`, `STATUS.md`. Verification: `READ`. The workflow runs
  `terraform fmt`, `terraform init -backend=false` and `terraform validate` on
  `runs-on: ubuntu-latest`.
- **Deck:** movement 10, marked `v`, note "GitHub Actions source validation, ADO estate left alone".
- **Gap, and it is worse than the first pass found.** The stated purpose is **local compute** for
  pipelines. The workflow names `ubuntu-latest`, which is not local compute. It is also source only:
  format, init without a backend, and validate. Nothing is deployed and nothing touches the cluster.
- **And it has never run, because it cannot.** Two files say the same thing independently.
  `Test-RepoPublishSafety.ps1`: "GitHub-hosted runners are not available to EMU user-owned
  repositories." `STATUS.md` repeats it. So the workflow declares a runner class this account cannot
  schedule. Self-hosted is not the blocked option here, hosted is. The deck's own caveat list says
  "No CI pipeline has ever run. EMU blocks GitHub hosted runners", which is correct and is the
  sharpest statement of this anywhere in the project.
- **Withdrawn correction.** An earlier draft of this row said the citation
  `pipelines/github-actions-and-repo-usage.md` pointed at a file that does not exist, and called it
  a stale directory listing. The file exists. It is at `docs/pipelines/`, not the empty `pipelines/`
  at the repo root. The original citation had a wrong path, not a missing file, and my correction
  was itself the error it accused. Third time a first-pass claim of mine has failed on contact with
  the file.
- **Whether `v` is defensible: decided 2026-09-09, and the answer changed.** It was not defensible
  on the workflow alone, because a pipeline definition with no run is an artifact rather than an
  outcome. It is defensible now, because the owner asked for the analysis that a green run would not
  have produced: where a pipeline is actually different on Azure Local versus any Azure
  subscription. That is written up at
  [pipeline-differences-azure-local-vs-azure.md](../pipelines/pipeline-differences-azure-local-vs-azure.md),
  it names five real differences, and every one of them was hit by this project rather than read
  from a doc: the VM is an extension resource and not a top level one, ARM reports Succeeded before
  Hyper-V agrees, a human PIM session cannot drive a schedule, provider registration is a
  subscription action no RG role grants, and verification has to ask the cluster rather than the
  control plane.
- **Why that is the stronger proof.** Running a self-hosted agent would have demonstrated that a
  process runs on a VM, which this project already proved several times. The boundary research says
  so outright: an ADO agent "neither requires nor gains its foundational value" from Azure Local.
  The knowledge worth having is the five differences, and a green pipeline would not have surfaced
  four of them.
- **Say the honest sentence anyway.** No pipeline has ever executed here. The document opens with
  that and the deck's caveat list carries it. The `v` covers the analysis and the authored workflow,
  not a run.

### G8. Threat model

> "Prepare a threat model."

- **Evidence:** [security-posture-and-boundaries.md](../access/security-posture-and-boundaries.md).
  Verification: `READ`.
- The document is not a threat model and says so in its first heading, "Why this document is not a
  threat model", with the reasoning: "it is worth doing properly or not at all. Producing a shallow
  one that nobody can defend would be worse than producing nothing, because it would create the
  appearance of analysis where there was none."
- What it does instead is separate three layers: what Azure carries, what the platform switched on
  by itself, and what neither reaches. The third layer is where the value is, and it is specific
  rather than generic. Physical console access is called a demonstrated capability rather than a
  theoretical one, because the nodes were imaged over KVM virtual media. The Raritan KVMs and
  iDRACs are named as a second door that does not authenticate against Entra, with the line "an
  unlicensed iDRAC is not a disabled iDRAC". Credential material on one workstation is admitted
  outright. Node 03 is flagged as outside the domain and outside the managed credential lifecycle.
- It also names both deliberate deviations, the security monitoring extension opt out and the interactive plus batch
  logon rights for the deployment account, the second with a Microsoft Learn citation.
- **Deck:** movement 10, marked `~`, note "boundaries documented, formal artifact pending".
- **Deck mark:** `~`. **Accurate, and if anything modest.** The traceability doc says "Partial" and
  the gap audit says "Addressed by substitution". The artifact that exists answers more than a
  first-pass threat model usually would, but it is not the named deliverable, so `~` is right.
- **Open item, unchanged.** The residual risk section is headed DECISION REQUIRED and still needs
  the project owner to accept or amend each line.

### G9. Demo of findings

> "Prepare a demo of findings."

- **Evidence:** the presentation itself, `capstone/prototype/v2/`.
- **Deck:** movement 10, marked `v`.

---

## The numbers on screen

The rows above check whether each criterion was met. They do not check the figures printed in the
deck's log panels, and those are what an audience actually reads. This section does that
separately, because a correct mark sitting above an invented number is still a problem.

| Where | Claim on screen | Source | Verdict |
| --- | --- | --- | --- |
| 00 | `Port3 100 Gbps`, `Port4 100 Gbps`, `Management 1 Gbps` | [cluster-network-wiring-reference.html](../network/cluster-network-wiring-reference.html) lists 100 Gbps on all eight storage ports. ADR 0010 records `LinkSpeed=100 Gbps` after the PnP enable. | Verified |
| 00 | node 01, 04, 06 reversed, node 02 correct | The wiring reference, verbatim: "On three of the four cluster machines the two Mellanox adapters were transposed... Node 02 was the only one wired the way the documentation described." | Verified, and the deck names the same three |
| 00 | `0 of 6 on all four nodes` | Same page: "The failure this page was originally written to diagnose was 0 of 6 east-west on both storage VLANs." | Verified |
| 00, 01 | `Test-NetConnection ... 10.40.1.185` | Appears in our own prototype files and nowhere else. | Unsourced. Plausible as a storage subnet address, but no capture records it |
| 01 | `all 27 validation tests` | The only recorded validator run says **25 checks, 23 SUCCESS, 2 FAILURE**. | **Wrong. Corrected to 25 checks.** |
| 01 | `Count: 12  (3 data disks x 4 machines)` | ADR 0011 sets three per node, and the risk register confirms node 01 reached three before deployment. | Verified at that point in the story |
| 01 | `6 of 6 on all four nodes` | Same lineage as the `0 of 6` figure. | Verified |
| 02 | steps 16, 17 and 40 at about 15m, 6m and 64m | [POC-deployment-summary.md](../POC-deployment-summary.md) lists each one with those exact durations and the same annotations. | Verified exactly |
| 02, 11 | `54 of 54 steps Succeeded` | 53 Success and 1 Skipped, zero failed. | **Wrong. Corrected to completed, none failed.** |
| 03 | `kubernetesVersion: v1.33.5` | The gap audit records "AKS `1.33.5`, control plane and worker Ready". | Verified |
| 03 | `moc-worker-01   Ready` | Checked live 2026-09-09. The cluster has two distinct node roles, represented here by `moc-control-plane-01` and `moc-worker-01`. | Verified node roles; labels are examples |
| 04 | `2/2`, `m94q2`, `zgnwp`, `3/3`, `72jvt`, `17/13` | [kubernetes-terraform-integration-test-results.md](kubernetes-terraform-integration-test-results.md) carries every one of those strings. | Verified exactly, pod names included |
| 07 | `16.7s`, 34 samples, minimum ready endpoints 2, 0 restarts | The gap audit records the 2026-09-01 run in those terms. | Verified |
| 08 | node 04 Down, `5m 12s`, `resync 62%`, 3 repair jobs | The test rebooted node **01** and it rejoined after about **26 minutes**. The percentage and the job count appear in no record. | **Wrong. Corrected.** |
| 09 | `55 items in Resource Group` | Counted live 2026-09-09. `az resource list` returns **53**. | **Wrong. Corrected to 53.** |
| 09 | `Seven VM images and three virtual machines` | Four gallery images plus two marketplace images is **six**. Two Azure Local NICs exist, `rocky-docker-01-nic` and `ws2025-core-01-nic`, so **two** guest VMs. | **Wrong. Corrected to six and two.** |
| 09 | Six Arc servers, four agents per node, four storage paths, two logical networks | Eight `HybridCompute/machines`, six of them hosts and all Connected. Extensions land 4 on each cluster node and 1 each on 03 and 05. Four `storageContainers`, two `logicalNetworks`. | Verified, all four lines |
| 09 | `Twelve NVMe, three per machine` | Twelve are installed and one is retired, so eleven carry data. [nvme-thermals.md](../storage-imaging/nvme-thermals.md) records it: "Node 01 shows two data drives rather than three." | Kept deliberately. Twelve is the build, and the retirement is the resilience point the deck makes next to it |
| 11 | `EMU blocks GitHub hosted runners` | `Test-RepoPublishSafety.ps1` and `STATUS.md` both say hosted runners are unavailable to EMU user-owned repositories. | Verified, and it is the sharpest sentence in the deck |

Seven numbers were wrong and one is unsourced. The unsourced one is not necessarily false. It is a
figure nobody can point at a file for, which is a different problem and a smaller one.

Two of the three original unsourced figures did not survive being looked up. `moc-worker-01` was
listed as probably fine, most likely the same machine under a second naming system. It was not. The
cluster has two nodes and neither has that name. The resource group count was listed as unconfirmed
until a screenshot could be taken, and it is 53 rather than 55. Every figure that could be checked
against the running system should be, because "probably fine" is the state the database note was in.

---

## Summary of what needs a decision

Every row has now been checked against its evidence file, and every figure in the deck's log panels
has been checked against a source. Nothing is left on trust. Three items from earlier drafts have
been withdrawn, because checking them showed the deck was right and I was not.

**Fixed in the deck, 2026-09-09:**

1. **G5 database.** The note said "asked for SQL Managed Instance with failover". Neither phrase is
   in the source. Replaced with what was actually asked, less SQL and OS maintenance, and the real
   reason it did not happen, which is that no workload was chosen.
2. **G6 storage.** Moved from `=` met by different means to `-` deferred. Three source documents
   agree: the equivalents matrix, the traceability doc, and the gap audit.
3. **MVP1 wording.** "54 of 54 steps Succeeded" is now "54 of 54 steps completed, none failed", in
   both places it appeared.
4. **The validator count.** "All 27 validation tests" is now "25 checks with no critical failures",
   which is the only count any file records. The intro narration and stamp changed with it.
5. **Movement 08.** Node 01 goes down, not node 04. The `5m 12s` and the `resync 62%` are gone,
   replaced by the recorded 26 minute rejoin and the six virtual disks returning to Healthy. One
   line joined the caveat list: there is no cluster witness, so four nodes survive losing one and
   not two.
6. **The reboot wording, put back.** A first pass at this added "a controlled reboot, not a power
   cut" to the panel and "nodes were rebooted, never pulled" to the caveats. Both are gone again by
   owner decision. See the G3 row. Removing a resource is the test. How it was removed is trivia at
   this scope, and hedging it on screen invites a question that does not need asking.
7. **The Kubernetes node roles.** The deck distinguishes the control plane from the worker,
   represented by `moc-control-plane-01` and `moc-worker-01`.
8. **Movement 09 counts.** 55 items became 53. Seven images and three VMs became six and two.
9. **The external VIP note.** "Blocked" became "an external VIP needs a subscription action we
   chose not to request". The denial is a fact and the decision not to escalate is a choice, and
   the deck was only showing the first half. See the G2 row.

10. **G7 pipelines, closed by writing the thing a green run would not have shown.** The note was
    "GitHub Actions source validation, ADO estate left alone" and is now "GitHub Actions validation
    authored, and the five places Azure Local changes a pipeline documented". The analysis is at
    [pipeline-differences-azure-local-vs-azure.md](../pipelines/pipeline-differences-azure-local-vs-azure.md).
    The `v` now covers an outcome rather than an artifact. No pipeline has still ever run, and the
    document says that in its second paragraph.

**Still open, needs a person to decide:**

11. **S2 security and security compliance.** Verified as genuinely done and genuinely invisible in the deck. The
    the security monitoring extension opt out is the item most likely to be asked about, and the deck
    never mentions it.
12. **S3a surfaces.** CLI and PowerShell are both proven. Portal is not, anywhere in the repo. The
    deck shows Terraform, a fourth surface nobody asked for.
13. **G2 wording.** Proven in front of pods rather than role VMs. Documented as a deliberate
    equivalence, but the audience cannot see that.
14. **One unsourced figure.** `10.40.1.185`, the storage fabric target address. Not likely to be
    false. Not traceable to a capture.

**Closed by decision, not by evidence:**

- **Reboot versus power cut.** 2026-09-09. A hard power-off is available through iDRAC and has
  never been worth simulating. The test is whether the cluster copes with a resource going away,
  and a reboot makes it go away. Sufficient at this scope. See the G3 row for the reasoning.

**Withdrawn after reading the evidence:**

- **Six node target.** ADR 0004 is a dated, owned descope. `~` is correct and `v` would be false.
- **G4 scale set split.** Manual scale was proven, auto-scale was not. Two rows is the honest
  presentation, not a manufactured deferral.
- **The missing pipelines file.** I said `github-actions-and-repo-usage.md` did not exist and called
  the citation a stale directory listing. It exists, at `docs/pipelines/`. The path was wrong, not
  the file.
- **S3b outbound.** I said the guest was never proven to reach a corporate resource and proposed a
  test. The tenant logical network hands every guest the two corporate DNS resolvers, so every name
  the guest ever resolved was that proof. The bar I applied was stricter than the sentence sets.

The withdrawal rate matters more than the findings. Four first-pass claims of mine have now failed
on contact with the evidence, and one of them failed while correcting two others. That is the
failure this worksheet was built to catch, committed inside the worksheet, four times.

## What the sweep changed

The seven rows that were still `POINTER` are now `READ`, and every one of them held up. The
requirement was met in each case. Reading them produced no reversals, only a set of edges that the
deck rounds off: Portal was never used, outbound connectivity was never tested against a corporate
resource, Docker Swarm was never touched, and the cluster has no witness.

The figure sweep was different. Four numbers on screen were wrong, one of them by a factor of five,
and three more cannot be traced to any file. None of them changes a mark. All of them are the kind
of detail that, asked about from the floor, is much better to have already known.
