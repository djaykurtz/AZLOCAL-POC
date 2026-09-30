---
title: "Capstone vision: design questions"
domain: [docs]
layer: [application]
type: plan
status: draft
proof: not-attempted
audience: [engineer]
tags: [capstone, design-questions, decisions-pending]
updated: 2026-08-25
---

# Capstone vision: design questions

## How to use this page

This is the decision document for the capstone presentation system. It has three parts:

1. **Settled by research.** Facts that are already proven, with sources. Do not re-litigate these.
2. **Open questions.** Numbered decisions, each with options and a recommendation. Answer these.
3. **Answer sheet.** A compact table to record your answers in one pass.

Every question has a recommended default. If you agree with a recommendation, answer `default`. The goal is to get
from a vision to a buildable specification in one review, not to write an essay.

Context for this round: the audience is internal, the environment is a locked-down lab, and security review is not
the gating concern. That removes several constraints that would normally block a browser-driven demo. The remaining
constraints are technical feasibility, cluster capacity, and demo-day reliability.

---

## Part 1: Settled by research

### 1.1 What the platform actually allows

| Question | Answer | Source |
| --- | --- | --- |
| Can the product be "baked into" the Azure Local host OS? | No. Azure Local runs workloads as VMs and AKS containers. The host is the platform, not the app host. | [What is Azure Local?](https://learn.microsoft.com/azure/azure-sovereign-clouds/private/azure-local/azure-local-overview#run-specialized-workloads-on-azure-local) |
| Can we build a purpose-built OS image for it? | Yes. Custom VM images are supported from a local share, Azure Compute Gallery, storage account page blob, or an existing Arc VM. VHDX must be Gen 2 and Secure Boot enabled. | [Create VM image from local share](https://learn.microsoft.com/azure/azure-local/manage/virtual-machine-image-local-share?view=azloc-2608#prerequisites) |
| Do Linux images need preparation? | Yes. Install and enable `cloud-init`, run `cloud-init clean`, then shut down before capture. | [Prepare an Ubuntu image](https://learn.microsoft.com/azure/azure-local/manage/virtual-machine-image-linux-sysprep?view=azloc-2608#create-a-vm-image-from-an-ubuntu-image) |
| Is node autoscaling possible on AKS Arc? | Yes. The cluster autoscaler is documented for AKS on Azure Local. | [Use cluster autoscaler on an AKS cluster](https://learn.microsoft.com/azure/aks/aksarc/auto-scale-aks-arc) |
| Is HPA possible? | Yes, but Metrics Server is not preinstalled. "For the Horizontal Pod Autoscaler to work, you must manually deploy the Metrics Server component in your AKS cluster." | [Make effective use of autoscaler](https://learn.microsoft.com/azure/aks/aksarc/auto-scale-aks-arc#make-effective-use-of-autoscaler) |
| Can we build container images inside the cluster? | Yes. BuildKit ships Kubernetes manifests for Pod, Deployment, StatefulSet, and Job, including rootless variants. | [BuildKit Kubernetes examples](https://github.com/moby/buildkit/tree/master/examples/kubernetes) |
| Can a webpage trigger a real pipeline? | Yes. `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches` starts a workflow and returns a run ID and URL. | [Create a workflow dispatch event](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event) |
| Can we add human approval mid-demo? | Yes. Environments support required reviewers, wait timers, and branch policies. | [Managing environments for deployment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) |
| Can we get a real external IP for the app? | Not currently. MetalLB is the documented path and it needs `Microsoft.KubernetesRuntime` registration, which was denied. | Repo record: permissions register and external dependency notes. |

### 1.2 What this POC already proved

These are demo assets, not claims to rebuild:

- Four-node Azure Local cluster with Arc, Arc Resource Bridge, custom location, and Storage Spaces Direct.
- Windows Server 2025 and Linux VM lifecycle, live migration, and host-reboot recovery.
- Docker and Dockge running in a guest VM.
- AKS Arc `1.33.5` running a two-replica dashboard with live Kubernetes API reads.
- Replica scale `2 -> 3 -> 2`, pod self-healing, EndpointSlice reconciliation.
- In-cluster Service routing: 90 requests distributed `26 / 30 / 34` across three pods.
- Terraform full lifecycle on a real Azure Local VM: plan, create, verify, destroy, reconcile state.

### 1.3 Known technical friction to design around

| Item | Impact on the demo |
| --- | --- |
| Rootless BuildKit needs kernel and sysctl conditions | `overlayfs` snapshotter wants kernel 5.11 or newer, and nodes may need `user.max_user_namespaces` set. AKS Arc node OS must be checked before promising a live in-cluster build. |
| ARM status lag on Azure Local VM create | Terraform reported success later than the actual running VM. A live Terraform stage needs a timeout and a narration plan. |
| PIM expiry | Elevation lasts 8 hours and Azure Local RP propagation lags 2-3 minutes after activation. A long demo day needs a pre-flight elevation step. |
| Node 01 retired NVMe | Storage is in a maintenance state. Avoid stress tests, large image pulls, and node-pool growth without a fresh capacity check. |
| Memory headroom | Hosts have about 31.5 GiB usable and node 06 carries infrastructure. Every new VM or node competes with the demo itself. |

---

## Part 2: Open questions

### Section A: Purpose and audience

**A1. Who is the primary audience, and what decision do they make after watching?**

- Options: (a) leadership deciding on further investment, (b) engineers who will inherit or extend the platform,
  (c) mixed internal showcase with no decision attached.
- Why it matters: it sets the depth of technical detail, the length, and whether the ending is a request or a summary.
- Recommendation: **(a) leadership, with an engineer-facing appendix mode.** One story, two depths.
|| I agree, (A), that is the correct shape.


**A2. What is the single sentence you want repeated back afterward?**

- Why it matters: every stage should serve this sentence. Without it the demo becomes a feature tour.
- Recommendation draft: *"We proved that Azure Local can run a real cloud-native delivery stack on our own hardware,
  and here is the working system that proves it."*
|| Azure Local represents new angles of freedom within some key constraints, let's explore what it has to offer.
* I'll have to think more about this maybe.

**A3. How long is the presentation slot, including questions?**
- Options: 10, 20, 30, or 45 minutes.
- Why it matters: this decides the number of stages. A stage needs roughly 2-3 minutes to be understood.
- Recommendation: **20 minutes of content, 10 for questions.** That supports six to eight stages.
|| Let's say 15 minutes is the target for content and 15 for questions. It's not a big formal thing at this point. But I might need to do it more than once.


**A4. Is this presented live by you, self-running, or both?**

- Options: (a) operator-narrated, (b) kiosk autoplay, (c) both modes in one build.
- Why it matters: autoplay demands scripted timing and no dead air. Narrated allows live pauses and real waits.
- Recommendation: **(c) both.** Build the narrated path first, add an autoplay timer that reuses the same script.

|| The most likely scenario is to present it through a Teams meeting, so it needs to be visually engaging and readable within those constraints.

### Section B: The narrative

**B1. What is the opening frame before anything is built?**

- Options: (a) literal blank white page, (b) dark powered-down console with a single control, (c) empty
  workspace with a prompt cursor already blinking.
- Why it matters: this is the emotional hook and it sets up the payoff.
- Recommendation: **(b) powered-down console with one control.** It creates a clear before and after.
|| I like console imagery, but I also like the console to be continually used throughout the whole presentation. It should be the window to the rest of the operation. Really need to home in on the right fit for the console because shortly into the website there is what looks like 3 competing consoles and a couple are static and not really what we're going for. But they do look nice and have useful information. So need to figure this out more.


**B2. What is the ending frame?**
- Options: (a) the full architecture lit up, (b) the running product with a live counter, (c) a scoreboard of
  what was proven versus what remains.
- Why it matters: determines whether the audience leaves with awe or with a decision.
- Recommendation: **(a) plus (c) as a final overlay.** Show the system, then show the honest ledger.
|| That is a good design idea. We'll go with that design recommendation for now.

**B3. Does the story follow build order or value order?**

- Build order: source -> image -> cluster -> service -> scale.
- Value order: a working app appears first, then we peel back each layer to show what supports it.
- Recommendation: **build order.** It matches the teaching goal and the self-building concept.
|| Yeah build order. But some bits may be redundant and other bits may need to be pre-built to get things running. But the idea being that it is a more bare website to start and then the backend builds and links in the new parts of the website, as most pods and infra get deployed holding different chunks, showcasing database and load balancer and other elements that can be depicted in a web site.

**B4. Who is the narrator voice in the interface?**

- Options: (a) neutral system log, (b) an assistant persona responding to prompts, (c) a guided tutorial voice.
- Why it matters: you described a prompt window, which implies a conversational agent.
- Recommendation: **(b) assistant persona, with all real output kept verbatim.** The persona introduces a step; the
  system output is never paraphrased.
|| I am going to be talking about the project. Again this isn't a large stage production, this is a teams meeting with important people.


## Part 2B: Reforged questions (answer these ten)

### What your answers changed

Four corrections that invalidate most of the original question set:

1. **This is a Teams meeting, not a stage.** Small audience, important people, possibly repeated. That makes
   screen-share legibility the dominant visual constraint, not cinematic impact.
2. **You narrate.** No assistant persona, no scripted voice. The interface should stay quiet and let you talk.
3. **One console, used throughout.** You flagged that the page currently has about three competing consoles and
   some are static. That is a real defect and it needs a single decision.
4. **The mechanic is infrastructure contributing website parts.** A bare page that gains real chunks as pods and
   infrastructure land, with a database, a load-balanced service, and other pieces each owning a visible element.
   That is far more specific than the generic modules I built.

Working theme, from your A2: **freedom within constraints.** Every stage should show a new degree of freedom, and
name the constraint it lives inside.

### Section C: The console

**C1. Which console model do you want?**

- (a) **Console as the frame.** One dark console occupies the page. The product being built appears inside it as
  the main viewport. Everything else is a rail or a strip on that console.
- (b) **Console as the instrument panel.** The product page is the hero and the console is one persistent panel,
  always visible, always the place output appears.
- (c) **Console as the stage floor.** A wide strip across the bottom, always live, with the product above it and
  the architecture beside it.
- Recommendation: **(a).** You said it should be the window to the rest of the operation. If it is the frame, then
  the product growing inside it reads as the system producing something, which is exactly the story.
|| Yeah that should be the truth of the situation because it is easy to assume much of this is smoke and mirrors when building out an attractive presentation that encapsulates it. 
**C2. What lives in the console, and what gets cut?**

Current competing surfaces: evidence stream (right), growth bar (middle), typed prompt (bottom), product frame
title bar. Pick what survives.

- (a) Keep evidence stream only. Cut the growth bar and the prompt.
- (b) Keep evidence stream and progress. Cut the prompt.
- (c) Merge all three into one scrolling console with an inline progress line.
- Recommendation: **(c).** One surface, one place to look. Progress becomes a line in the console rather than a
  separate bar, which also survives Teams compression better than a thin gradient bar.
|| Don't need the prompt. I like the visual clarity of the evidence stream, but don't want to call it that.
I want the actual console commands to be real commands that run the project. But unless we make a new console that just links with a background one that isn't visible we're not going to do a very good job of synthesizing a realistic build experience.

**C2 design direction, agreed 2026-08-28.** One surface, two registers, which is the collapsible job log pattern
from GitHub Actions and Azure Pipelines. The audience already knows how to read it.

- Each stage emits a **group**. The group header is the coloured milestone row that survives from the evidence
  stream: name, status, duration.
- The group body is the real command and its real output.
- Groups are **collapsed by default, including while running.** The default state of the console is calm. The
  commands are there to be revealed, not to be endured. Expanding one is a deliberate presentation beat, a
  pull-back-the-curtain move, rather than a permanent wall of text.
- A group **expands itself on failure.** Success collapses, failure opens. This is the honest asymmetry, and it
  means a genuine problem during the call is handled by the design rather than hidden by it.
- Long steps show an **interstitial** in the collapsed header instead of streaming output. See the honesty
  constraint below.
- The whole console is collapsible, so it can be pushed aside when the product frame is the point.

Collapsed-by-default removes the burstiness problem at the root rather than mitigating it. It also makes the proof
land harder: scarcity is why expanding on request answers the smoke-and-mirrors instinct, where showing everything
all the time just reads as noise and stops being looked at.

**Interstitial honesty constraint.** A progress bar asserts that progress is known. Most CLI operations do not
report percentage, so a smoothly filling bar for something like `terraform apply` is invented information, which
is the one line we agreed not to cross. Rules:

- Determinate bar **only** where the underlying tool genuinely reports progress. The Azure Local deployment is a
  real example: 54 discrete steps, real step numbers, an honest bar.
- Everywhere else, an **elapsed timer counting up**, or indeterminate activity. Both are true and neither invents
  precision.

**The timing track.** Timings become data rather than incident, so they can be rehearsed and tuned. Captured from
a real run's timestamps, held separately from content, and adjustable without touching the script.

This is the melody and lyrics model. The melody is the runtime rhythm of the real build, which we do not get to
change. The narration is written to fit it. Waits stop being dead air and become the designed places to talk,
which is what makes a dense console survive a live presentation.

**Scheduling consequence.** This design is identical whether C4 is transcript or live shell, because the console
shows milestone rows either way and only the content behind an expanded group differs. The console can therefore
be built before C4 is answered.

**The console is the event source.** Everything outside it subscribes. Visual aids, graphs, the architecture view,
and the product frame all appear because a step started, finished, or reported a fact, never because a separate
timeline said so.

- One clock. There is no second timeline to keep in sync, which is the usual failure mode of presentation
  software.
- Structurally honest. A visual is *caused* by the evidence rather than scheduled alongside it, so the picture
  cannot drift from the log.
- **It makes C4 an implementation detail rather than an architecture.** A transcript replays events; a live shell
  emits them. Everything downstream is byte-identical. Building the transcript version first is not throwaway
  work, and switching to live later is a change of producer, not a rewrite.

Event vocabulary should be a small fixed contract rather than per-stage wiring, or it will rot: `step.start`,
`step.progress`, `step.done`, `step.fail`, plus named domain facts such as `resource.ready` and `metric.sample`.
Visual aids subscribe by name.

**Reality sets the tempo, decoration must fit.** The timing track comes from real runs and is authoritative. If an
animation takes longer than the step it hangs off, the animation gets cut short, not the track extended. Without
that rule the visuals pile up behind a fast sequence and the whole thing desynchronises.

**The honesty rule extends to the graphs.** A chart triggered by a real event still has to be plotted from data
captured in that same run. Otherwise we have built an honest event bus that delivers invented charts, which is the
progress bar problem again in a larger frame.

**Colour belongs to the connection, and encodes what kind of relationship it is.** The console group header
carries a hue, and the links that event creates or exercises carry the same one. Colour stops being mood and
becomes a key.

This is the fix for a real defect. In the old evidence ledger the colours encoded tone, which was not obvious and
did not repay attention. Giving colour a single job gives every element purpose.

- **Edges own the hue, not nodes.** Nodes already have position and a label, so colour spent on them is largely
  redundant. Edges have neither, and the connections are the part people respond to most. Colour spent there is
  pure information gain.
- **Nodes glow in the hue of whichever connection is currently active through them.** The colour travels through
  the architecture rather than being owned by any part of it.
- **Five connection kinds**, which is also the practical ceiling for distinguishable hues on a dark background
  over compressed video:

| Connection kind | What it represents |
| --- | --- |
| Networking | L2 and L3 reachability, VLANs, the storage fabric |
| Storage | S2D, volumes, persistence |
| Control plane | Arc and ARM calls, the API layer |
| Orchestration | scheduling and placement decisions |
| Workload | traffic between running things |

- **Colour encodes kind. Form encodes status.** These cannot both be hue or neither reads. Dashed while
  establishing, solid once established, weight for volume, and a pulse travelling the line when it carries
  traffic. Motion is already in the visual language, so status has somewhere to live.
- **Failure is the one privileged override.** A failed link goes red regardless of kind, because failure has to
  dominate and it is rare enough not to muddy the scheme. This pairs with the rule that failed groups expand
  themselves.
- **Colour is an accelerator, not the only channel.** Kind is also implied by which layers an edge spans, so a
  viewer with colour vision deficiency loses speed but not meaning.

**The density arc is earned, not staged.** Early stages genuinely only have networking and storage relationships,
because nothing else exists yet. Orchestration edges cannot appear until Kubernetes does. Workload edges cannot
appear until something is serving. So the palette fills as the system actually grows, and the visual build is a
consequence of the architecture rather than a choreographed effect.

**The opening is dense and monochrome, not sparse.** At the start there are a great many edges and nearly all of
them are one kind. This is the stratification-of-concern idea behind the lower OSI layers, borrowed as styling
logic rather than implemented literally: at first the only relationship that exists between anything is whether
it can reach anything else.

So complexity is added by **new kinds of line, not more lines**. That has a useful property. Edge count grows
without bound and is a poor measure of anything, but the number of distinct kinds present caps at five and tracks
the actual maturity of the system. `3 of 5 connection kinds online` is an honest header statistic in a way that
`47 links` is not.

Musically this is instrumentation, and the arc is **unison to harmony** rather than soloist to tutti. It opens
with many voices on one line, then splits into parts as the system earns them. Each connection kind is an
instrument with a consistent voice, and the stages are movements. The recurrence is real: the storage line in an
early stage and the storage line in a late one are the same instrument.

**Density grows, focus stays single.** This is what keeps both ends of the arc readable, and it needs three tiers
rather than two, precisely because the opening is monochrome. Two tiers would leave every edge bright in stage
one, which is no focus at all.

| Tier | State |
| --- | --- |
| Edges touched by the current console event | full saturation, pulsing |
| Same kind, already established | mid |
| Other kinds, already established | dim |

The picture gets richer across the arc while never having more than one thing bright at a time.

**The reveal order is determined, not chosen.** The five kinds are an ordered climb up the abstraction ladder, and
each one is a hard prerequisite for the next. Orchestration edges cannot exist before a control plane does.
Workload edges cannot exist before something is scheduled. So the sequence is fixed by the architecture, which
removes a whole category of design debate:

| Order | Kind | What the system has become |
| --- | --- | --- |
| 1 | Networking | infrastructure |
| 2 | Storage | infrastructure |
| 3 | Control plane | fabric |
| 4 | Orchestration | systems |
| 5 | Workload | systems in use |

The colour arc and the argument are the same arc. Each new hue is a step up in what the environment can do, so
the visual is not illustrating the story, it is the story.

**Novelty does the attention work for free.** A new hue against a field of established colour is noticed without
being pointed at, so the newest capability is always the most salient thing on screen. That reinforces the focus
tiers rather than competing with them.

**First of a kind gets ceremony, the rest get texture.** The first edge of a new colour is the highest value
moment in the whole arc, because it is the only time that colour is genuinely new. It should be drawn
deliberately and dwelt on. The fortieth storage link is background. Animating everything equally is how nothing
ends up feeling significant.

**Guard against the infrastructure appearing to stop mattering.** As hues accumulate, the early layers recede,
and the audience can quietly conclude that the physical and storage work is finished business. It is not. The
resting dim state has to stay legible as present rather than absent, and the closing view should bring the full
stack back up briefly. That recapitulation is what keeps the thesis intact, since the entire claim is that this
is running on hardware in our own building.

**Nodes abstract into a fabric once the cluster forms, and that morph is the thesis.** Early on the machines are
four discrete, named, individually addressed things, because that is what they are. After the cluster exists they
become one continuous work surface, because that is also what they are. Going from four servers to a pooled
substrate you stop thinking about is precisely what the platform does, so the strongest visual argument in the
piece is the one that gets the substrate out of the way.

- **Triggered, not scheduled.** The morph fires on the cluster forming, like every other visual, so it is earned
  rather than staged.
- **Recede, do not disappear.** This is the distinction that keeps the guard above intact. The surface stays
  legible as a real thing carrying real load. It is out of focus, not out of the picture.
- **Reversible on demand.** At any point the fabric can resolve back into four machines. This is the same
  pull-back-the-curtain move as expanding a console group, and it is the honest answer to anyone wondering where
  the hardware went.
- **It resolves itself on failure.** When a node drops, the surface breaks back into individual machines so the
  audience can see exactly which one left, then re-abstracts as it rejoins. That is real proven content from the
  node failure work, and it gives that demonstration a visual language nothing else in the piece has.

**Three states for a machine.**

| State | When | What is shown |
| --- | --- | --- |
| Detailed block | before the cluster exists | name, memory, address, disks, driver state |
| Strip cell | after the cluster forms | name and an activity light, parked at the edge of the canvas |
| Resolved | on demand, and automatically on failure | back to the detailed block |

**The demotion is spatial, not just visual.** The machines do not shrink in place, they move to a margin. That is
the mechanism by which focus actually shifts, and it is what frees the middle of the canvas. Fabric at the edge,
workspace in the middle.

It also solves a real layout problem at exactly the right moment. The architecture view needs more room precisely
when orchestration and workload edges start appearing, and that is the same moment the substrate stops needing
the space. The canvas gets bigger without the page changing.

**The activity light should indicate work, not just health.** If a strip cell pulses while that machine is
hosting active workload, then placement is legible at a glance without drawing anything extra, and a live
migration shows up as the pulse moving from one cell to another. That is proven content getting a visual for
free.

**Failover is shown at two levels at once, and the contrast is the point.** Kubernetes rescheduling a pod is
table stakes and every demo has it. What is hard to show, and what this environment can actually prove, is the
substrate healing underneath while the workload above never notices.

So both halves run simultaneously and the layout already supports it. The fabric strip at the edge breaks apart
and goes red while the workspace in the middle keeps serving. Neither half is the story on its own. The story is
that they are happening at the same time.

| Level | What the audience sees |
| --- | --- |
| Physical | node leaves the strip, pool degrades, repair jobs start, resync runs, node rejoins, pool healthy |
| Workload | brief blip at most, requests redistribute across surviving replicas, service stays up |

**The return path is the strongest beat, and it should be gated on resync rather than on rejoin.** A machine
coming back resolves out of the fabric into a detailed block, because that is exactly when you care about it
individually again. It then stays detailed while resync runs, since the node is present but its data is not yet
whole. Only when repair completes does it fade back into the fabric.

That makes the fade meaningful rather than cosmetic. Rejoining gets you the block back. Fading into the fabric
means fully trusted again, and it maps exactly to the real Storage Spaces Direct behaviour of degraded but
online, repair jobs, then healthy.

**Two honesty constraints on this sequence.**

- **Use the failure we actually ran.** The proven event is a forced reboot, with the pool going to warning, six
  virtual disks degraded but online, three repair jobs starting automatically, and a return to healthy on
  rejoin. Do not stage a more dramatic failure than the one that happened.
- **Disclose the time compression.** Real rejoin and resync took minutes, which is far too long to play at
  natural pace. Compressing it is fine, inventing a recovery time is not. Show the real elapsed figure as a
  label while the animation runs short, the same way the stage timings already do.

**Failover is recorded, not live. Decided 2026-08-28.** This also corrects the F2 recommendation below, which
suggested running self-healing live on the grounds that it is fast and recovers cleanly. That was wrong on the
facts. Replica scaling really is fast, at roughly ten seconds. Node recovery is not: rejoin alone took about five
minutes before resync even started. There is nothing to gain from waiting for it live and a great deal to lose.

**The healing sequence is the archetype of the timing track.** It is a genuinely long real duration, compressed
in playback, with the wait used deliberately for narration about resiliency and expected recovery windows. Every
other stage is a milder version of this problem, so if the pacing works here it works everywhere.

**Open item: the recovery figure has to be a real measurement.** If expected healing time becomes a spoken
talking point it needs to be a number we recorded, not one estimated on the call. What is captured today is the
rejoin at roughly five minutes. Full resync to healthy is less precisely recorded and should be recovered from
the run logs, or measured again deliberately, before it is quoted.

**Three recovery behaviours were proven, and they are different conversations.**

| Behaviour | What happened | What it demonstrates |
| --- | --- | --- |
| Graceful drain | node paused, roles live-migrated off, disks warning but online, resumed healthy | planned maintenance with no workload impact |
| Forced reboot | node down, six disks degraded but online, three repair jobs, resync, healthy | unplanned loss and self-healing |
| Workload failover | guest VM moved when its host was rebooted, came back running | the workload surviving the substrate |

The middle one is the interesting one and should carry the stage. The other two are worth a sentence each,
because together they show the difference between a maintenance window and an actual failure.

**Progressive disclosure is now the spine across every surface.** Console groups collapse and expand. The fabric
abstracts and resolves. Connection kinds rest and brighten. In all three the detail is never destroyed, only set
aside, and always one gesture away. That is what lets the piece be calm without being thin.

**How the surfaces fit together.** Each answers a different question about the same event, which is what keeps
four simultaneous surfaces from competing:

| Surface | Question it answers |
| --- | --- |
| Console | what happened |
| Architecture view | where it happened |
| Product frame | what it produced |
| Visual aid or graph | what it means |


**C3. Does the typed command line stay?**

Since you narrate, the typed prompt may be a gimmick that competes with your voice.

- (a) Remove it. Stages advance on your click.
- (b) Keep it, but as a visible record of the command that was actually run, not as theater.
- (c) Keep it interactive so you can type a real command on request.
- Recommendation: **(b).** It shows the real verb behind each step, which supports your narration instead of
  competing with it.
|| Read C2 for this vision design. Synthesized by pulled from reality.

**C4. How real are the commands in the console?**

Raised by your C2 answer. You are right that a console showing real commands is only convincing if something real
is behind it, and that is a build decision rather than a design one.

- (a) **Transcript.** Real commands and real output, captured from actual runs, replayed in order at presentation
  pace. The page stays a plain file you can open anywhere.
- (b) **Live shell.** The page holds a socket to a small local process that runs the commands for real while they
  watch.
- (c) **Transcript by default, live for the two or three steps that are fast and recover cleanly.**
- What (b) actually costs: a local agent process, a websocket or server-sent-event channel, output streaming and
  buffering, a command allowlist so the page cannot run arbitrary things, and a visible failure path for when a
  command hangs mid-call. It also means the prototype stops being a file you can double-click, which is currently
  its main advantage for review.
- Recommendation: **(c),** and it is the same decision as F2. Answer one and the other follows.
- Note: (a) is not smoke and mirrors as long as the console says where the output came from. A replayed real run
  is still a real run. The dishonest version is invented output, which we are not doing either way.
- **Pacing does not require live execution.** If each captured line carries its original timestamp, replay
  reproduces the real cadence exactly: the same waits, the same bursts, the same total duration. The natural
  pacing you are counting on to make a dense console readable is available in (a) at no risk. What (b) buys is
  the ability to change something on request, not a more honest rhythm.

**C5. What should the evidence stream be called?**

You said you like it but not the name.

- (a) **Transcript.** Precise if C4 is (a). Tells the audience these are real commands from real runs, which
  answers the smoke-and-mirrors instinct directly.
- (b) **Terminal.** Correct only if C4 is (b).
- (c) **Build log** or **Run log.** True in every case, and familiar to everyone.
- (d) Something else. Write it in.
- Recommendation: **(a),** because it is the most honest word available and it is coupled to C4.

### Section D: The build mechanic

**D1. Confirm the mapping of website parts to infrastructure.**

This is the heart of the product. Strike, edit, or add rows.

| Website element that appears | Backed by | Degree of freedom it shows |
| --- | --- | --- |
| Page shell and header | first pod and Deployment | we can host our own application |
| Live runtime tiles | read-only Kubernetes API | the page can observe itself |
| Data table with real rows | database pod plus persistent volume | stateful workloads on our own storage |
| "Served by" badge that changes per refresh | Service across multiple replicas | traffic spreads without configuration |
| Asset or file panel | persistent volume on Storage Spaces Direct | local storage that survives restarts |
| Background job history | Kubernetes Job | scheduled and batch work |
| Version and build banner | container image tag and digest | traceable releases |
| Capacity indicator | replica count and node placement | capacity on demand |

- Recommendation: **keep the first five, cut the rest if time is short.** The data table is the most valuable
  addition because a database is the thing executives recognize as real work.

**D2. What causes a website part to appear?**

- (a) Presenter advances the stage and the part appears.
- (b) The part appears when its backing resource actually reports ready, so the page reacts to the cluster.
- (c) (b) with a presenter override if it takes too long.
- Recommendation: **(c).** Reacting to real readiness is the whole point, but you need an escape hatch on a call.

**D3. Do we deploy a real database and a real load-balanced service for this?**

- (a) Yes, deploy both. Real workloads, real evidence, more build effort.
- (b) Deploy the load-balanced service only, depict the database.
- (c) Depict both.
- Why it matters: a database means a StatefulSet or Deployment plus a PersistentVolumeClaim on the cluster, and
  the node 01 storage condition is open. It is achievable but it is real work.
- Recommendation: **(a) if the schedule allows, (b) if not.** A small PostgreSQL with a handful of rows is enough.

### Section E: Delivery over Teams

**E1. Should I optimize the visual design for Teams screen share?**

Screen share is compressed and often reduced in resolution. Current design has thin one-pixel wires, small
monospace text, fine diagonal hatching, and drifting particles. All four degrade badly over video.

- Recommendation: **yes.** Concretely: raise base font sizes, thicken connection lines, reduce fine texture,
  slow or cut ambient particles, and increase contrast on status colors. Keep one accent motion moment.
- Confirm you want this, because it will make the page look slightly less delicate in person.

**E2. How will you run it during the call?**

- (a) Share the whole screen, browser full screen.
- (b) Share a single browser window, notes on your other monitor.
- (c) Share a window and keep a terminal visible for credibility.
- Recommendation: **(b).** It keeps your notes private and avoids notification leaks.

### Section F: Scope and schedule

**F1. What is the deadline, and roughly how many working days do you have before it?**

- Why it matters: it decides whether D3 is (a) or (b), and whether anything runs live.

**F2. How live do you want it on the call?**

Simplified from the original fidelity ladder, since Teams changes the calculation.

- (a) **All recorded.** Everything replays from real captured runs. Zero risk, still honest if labeled.
- (b) **Live reads, recorded writes.** The page reads the real cluster during the call, but any change was
  captured earlier.
- (c) **Live reads and live writes.** Scaling and pod deletion actually happen while they watch.
- Recommendation: **(c) for scaling and self-healing only,** because those are fast and recover cleanly. Keep
  everything slow, such as image build and Terraform, as recorded.

---

## Archived question set

Everything below predates your answers. Kept for reference only. Do not answer it.

### Section C: Fidelity (original framing)

Define fidelity levels first, then assign one to each stage.

| Level | Name | Meaning |
| --- | --- | --- |
| F0 | Simulated | Scripted animation and canned text. Nothing runs. |
| F1 | Replay | Real recorded output from a real prior run, replayed on cue. |
| F2 | Live read | Real API reads at presentation time. Nothing is changed. |
| F3 | Live write | The demo actually changes cluster state during the presentation. |
| F4 | Live build | The demo builds an image or applies infrastructure during the presentation. |


**C1. What is the highest fidelity level you want to attempt on stage?**

- Why it matters: this is the single biggest driver of build effort and demo risk.
- Recommendation: **F3 as the ceiling for the live path, with F1 replay available for every F3 and F4 stage.**
  Attempt one F4 moment only if rehearsal shows it completes in under 90 seconds.

**C2. Is simulated content acceptable if it is labeled?**

- Options: (a) no simulation at all, (b) simulation allowed with a visible badge, (c) simulation allowed and
  unlabeled during the flow but disclosed at the end.
- Why it matters: this project's credibility has come from being explicit about boundaries.
- Recommendation: **(b) visible badge per stage.** A small `SIMULATED`, `REPLAY`, or `LIVE` chip. It costs nothing
  and it makes the live parts land harder.

**C3. What happens if a live stage fails during the presentation?**

- Options: (a) show the failure and narrate it, (b) auto-fall back to replay, (c) manual hotkey to switch to replay.
- Recommendation: **(c) manual hotkey, with (a) as the preferred choice when the failure is interesting.** A real
  failure that you explain well is often the most credible moment in a technical demo.

**C4. Should the timeline be real or compressed?**

- A real Terraform VM create runs for minutes. A real image build runs for minutes.
- Options: (a) real time with narration, (b) compressed replay, (c) start the real job early and cut to it when done.
- Recommendation: **(c) start-early-and-return.** Kick off the real work at the beginning, do other stages, then
  return to the finished result. It is honest and it removes dead air.

### Section D: The "OS foundation" concept

You described the product as baked into an OS. Research says the host OS is off limits, so this needs a decision
about what the phrase means here.

**D1. Which interpretation do you want?**

- (a) **Appliance VM.** A purpose-built Linux image, auto-login, browser in kiosk mode, the product is the whole
  screen at boot. Runs as an Azure Local VM. Feels like an OS to the viewer.
- (b) **Cluster as the OS.** The product is a Kubernetes-native app and the "operating system" framing is
  conceptual: AKS is the OS, the app is the shell, workloads are processes.
- (c) **Desktop shell metaphor only.** The web page looks like an OS, with a workspace, windows, and a task bar,
  but nothing is actually an OS.
- (d) Combination: (c) visually, delivered by (a), running on (b).
- Recommendation: **(d).** It is achievable, it is honest, and it gives the strongest visual payoff. The demo boots
  a machine whose only purpose is to be this product.

**D2. If we build the appliance VM, is it part of the demo story or just the delivery mechanism?**

- Options: (a) invisible plumbing, (b) stage zero of the story, showing the image being created and booted.
- Recommendation: **(b).** "We built the operating system image this presentation is running on" is a strong
  opening and it uses a capability we have already proven.

**D3. Do you want the workspace metaphor to include multiple windows?**

- Options: (a) single focused pane, (b) tiled panes that fill in as capabilities appear, (c) draggable windows.
- Why it matters: draggable windows are a large build with real usability risk on a projector.
- Recommendation: **(b) tiled panes.** It reads as an OS, avoids window-management bugs, and looks intentional.

### Section E: Technology coverage

**E1. Which technologies must appear on screen? Rank as must, should, or cut.**

| Technology | Available evidence | Recommendation |
| --- | --- | --- |
| Azure Local platform and Arc | Strong, already proven | Must |
| Azure Local VM lifecycle | Strong | Must |
| Docker or container image build | Guest VM proven; in-cluster build unproven | Must, method to be decided in E2 |
| Terraform | Full lifecycle proven | Must |
| Kubernetes deploy and Service routing | Strong | Must |
| Scaling: replicas | Proven | Must |
| Scaling: HPA with Metrics Server | Documented, not yet installed | Should |
| Scaling: node autoscaler | Documented, capacity-gated | Cut for this round |
| GitHub Actions CI | Workflow authored, not yet run | Should |
| Live migration and node failure recovery | Proven earlier | Should, as a replay clip |
| External load balancer VIP | Blocked | Cut, mention as a boundary |

**E2. Where does the container image get built during the demo?**

- (a) **Prebuilt.** Built beforehand, demo shows the digest and the running version.
- (b) **GitHub Actions.** Real workflow triggered from the page, image pushed to a registry.
- (c) **In-cluster BuildKit.** A Kubernetes Job builds the image on the cluster itself.
- Why it matters: (c) is the most impressive and the least proven. It needs a node kernel and sysctl check first.
- Recommendation: **(b) as the primary path, with (c) as a stretch goal** after a feasibility spike. If (c) works,
  it becomes the signature moment: the cluster builds the thing that is being presented on it.

**E3. Where do images live?**

- (a) In-cluster `registry:2` running as a pod.
- (b) Azure Container Registry, pulled over the internet.
- (c) ACR connected registry as an Arc extension, which requires a Premium ACR SKU.
- Recommendation: **(a) for the demo, (b) as the source of truth.** In-cluster keeps the demo independent of
  external network conditions on the day.

**E4. Do you want a visible "scale the capability" moment tied to real load?**

- Options: (a) manual scale button, (b) generate load and let HPA scale it, (c) both, one after the other.
- Recommendation: **(c).** Manual scale first so the mechanism is understood, then load-driven scale so the
  automation is credible. This requires Metrics Server, which is a small, well-documented install.

### Section F: Interaction model

**F1. What does the prompt window actually do?**

- (a) Cosmetic: typing is animated and outputs are scripted.
- (b) Command palette: a fixed set of real commands the backend executes.
- (c) Natural language: free text mapped to intents, then to fixed actions.
- Recommendation: **(b) with (a) styling.** A fixed verb list is reliable on stage, and each verb maps to a real
  backend action. Free-text parsing adds risk with no audience benefit.

**F2. Who can type into it during the presentation?**

- Options: (a) presenter only, (b) audience suggestions relayed by presenter, (c) open kiosk input.
- Recommendation: **(a) presenter only, with a suggested-prompt list visible.** Audience suggestions can be
  accepted verbally and typed by you.

**F3. Should there be a visible plan step before actions run?**

- Example: prompt -> shows the plan -> asks to proceed -> executes.
- Why it matters: this mirrors real infrastructure workflow and it gives you a natural narration pause.
- Recommendation: **yes.** The plan-then-apply rhythm is also the honest Terraform story.

**F4. Do you want an undo or reset control?**

- Recommendation: **yes, a single `Reset demo` control** that restores replica count, deletes demo Jobs, and clears
  the UI back to stage zero. Rehearsal and repeat presentations both need this.

### Section G: Backend visualization

**G1. What is the primary visual for the backend?**

- (a) Architecture graph with nodes and animated paths.
- (b) Live resource inventory, closer to a console.
- (c) Layered stack diagram that fills upward.
- Recommendation: **(a) as the hero, with (b) available in the appendix mode.**

**G2. What granularity of objects appears in the graph?**

- Options: (a) logical layers only, (b) real named objects such as pods, Services, and VMs, (c) both, with drill-down.
- Recommendation: **(c).** Start at layer level, drill into real object names on demand. Real names are what make
  it feel non-fictional.

**G3. Should the graph animate continuously or only on change?**

- Recommendation: **only on change,** plus a slow heartbeat on live-connected nodes. Continuous motion reads as
  decorative and undermines the "this is real" claim.

**G4. Do you want request-level tracing visible?**

- The existing app already emits `X-Request-ID` and structured logs.
- Recommendation: **yes, one small panel.** Click a request, see which pod served it. It is cheap and it proves the
  routing story better than a diagram.

### Section H: Visual design

**H1. Keep the existing Command Center direction?**

- Dark shell, warm workspace, orange active path, restrained status colors.
- Recommendation: **yes.** It is already documented and it suits an internal technical audience.

**H2. Light or dark for the main product pane?**

- Recommendation: **dark shell with a warm light workspace,** as already specified. It projects well and separates
  chrome from content.

**H3. How much motion?**

- Options: (a) minimal, (b) moderate with purposeful transitions, (c) cinematic.
- Recommendation: **(b).** Motion only when something changed, plus one deliberate cinematic moment at power-on.

**H4. Is there a branding requirement?**

- Question: does this need team, org, or Azure branding, and are there internal guidelines to follow?
- Recommendation: **minimal branding, one footer line.** Confirm whether that is acceptable.

### Section I: Content depth

**I1. For each stage, do you want the three-block format already designed?**

- `What changed`, `What proves it`, `Boundary`.
- Recommendation: **yes.** It is the most defensible part of the existing design and it prevents overclaiming.

**I2. How much Azure Local specificity versus general cloud-native teaching?**

- Options: (a) mostly Azure Local, (b) balanced, (c) mostly the technologies, with Azure Local as the venue.
- Recommendation: **(b) balanced,** with every stage naming what was Azure Local specific. That is the unique
  value of this project.

**I3. Do you want the failure stories included?**

- The storage fabric root cause, the AD pivot, the security monitoring extension conflict, the NIC naming discovery.
- Why it matters: these are the most interesting engineering content and they justify the elapsed time.
- Recommendation: **yes, one compact "what it took" panel** with three or four entries, available on demand rather
  than in the main flow.

### Section J: Demo-day logistics

**J1. Where does the presentation run from?**

- Options: (a) your DevBox browser with port-forward, (b) the appliance VM on the cluster, displayed over console
  or RDP, (c) a laptop with a cached local copy.
- Recommendation: **(b) primary, (c) as the guaranteed fallback.** Always have an offline copy that needs no cluster.

**J2. Is network access to Azure guaranteed in the room?**

- Why it matters: live Azure reads, workflow dispatch, and image pulls all depend on it.
- Recommendation: **assume no,** and cache everything that can be cached.

**J3. How many rehearsals before the real presentation?**

- Recommendation: **at least two full runs,** one of them with a deliberately induced failure to practice recovery.

**J4. What is the pre-flight checklist window?**

- PIM elevation, cluster health, replica reset, evidence freshness, and fallback copy verification.
- Recommendation: **a scripted preflight run 30 minutes before,** producing a single pass or fail summary.

### Section K: Success criteria

**K1. How will you judge whether the capstone succeeded?**

- Options: (a) audience understanding, (b) a specific funding or expansion decision, (c) reusable asset for future
  onboarding, (d) personal or team demonstration of capability.
- Recommendation: **name a primary and a secondary.** Suggested: primary (b), secondary (c).

**K2. Should the artifact survive the presentation?**

- Options: (a) one-time demo, (b) permanent internal tool, (c) template others can fork for their own POCs.
- Recommendation: **(c).** It costs a small amount of extra structure and greatly increases the value of the work.

### Section L: Constraints

**L1. What is the hard deadline?**

**L2. How many working days can you spend on this before then?**

**L3. Is anyone else contributing, or is this solo?**

**L4. Can the POC cluster be considered stable for the whole period, or is hardware maintenance expected?**

- Specifically: does the node 01 NVMe condition get repaired before the demo, and do nodes 03 or 05 come back?

**L5. Is any budget available?**

- Relevant only for an ACR Premium SKU if the connected registry path is chosen.

### Section M: Risks to confirm

**M1.** Do you accept that the external VIP stays unavailable and the demo uses port-forward or the appliance VM?

**M2.** Do you accept that a live in-cluster image build may prove infeasible after a spike, and the fallback is a
GitHub Actions build?

**M3.** Do you accept a cap on live infrastructure creation during the presentation, given host memory headroom?

**M4.** Is it acceptable for the demo application to have write access to its own namespace so it can scale itself?

- This is the key permission that makes a self-scaling demo real rather than simulated. In this locked-down internal
  lab it is a low-consequence grant, scoped to one namespace.
- Recommendation: **yes, namespace-scoped write to Deployments and Jobs only.**

---

### Section G: Raised during the build (2026-08-28)

**G1. Is ADR 0005 superseded?**

[ADR 0005](../docs/decisions/0005-plan-only-tooling-test-surface.md) records Terraform, Docker, and Kubernetes as a
plan-only test surface. All three have since been executed against the real cluster, so the decision looks
overtaken. It is tagged `status: current`.

- (a) Mark it `superseded`, since reality moved past it.
- (b) Leave it `current`, because it still describes the boundary that was agreed at the time.
- Recommendation: **(a).** The `proof` facet is the honest ledger, and leaving this one stale undercuts it.
- Not changed without your call, because it is a judgment about original intent rather than a fact.

**G2. How hard should the four-node number land in the intro?**

The director's cut currently labels it `proof of concept scope` and words it as the number this POC committed to.

- Why it matters: Azure Local does not publish a four-node minimum. The supported range starts at one node. The
  four came from [ADR 0004](../docs/decisions/0004-four-node-functional-poc-scope.md), driven by scope and by
  eight drives mapping cleanly across four machines.
- (a) Leave it as proof of concept scope.
- (b) State it harder, as a requirement.
- Recommendation: **(a).** Three-way mirror plus one node you can afford to lose is true and defensible.
  Calling four a platform minimum is not, and someone in the room may know that.

**G3. Is 2 minutes 27 seconds acceptable for the intro?**

You asked for about two minutes. Adding the six-node attrition beat pushed act one from 33 to 47 seconds.

- (a) Leave it. The accumulation needs the room.
- (b) Cut back toward two minutes by tightening the Secure Boot card sequence and the network act.
- Recommendation: **(a),** but this is a taste call and easy to reverse. Act durations are one array in
  [intro.js](prototype/intro.js).

**G4. Two half-built features are sitting in the prototype. Wire or remove?**

Both predate this session.

- `BOOT_TASKS` in [scenario.js](prototype/scenario.js) is fully written, with per-task weights and real endpoint
  contracts, but `runBoot()` ignores it and uses a hardcoded list with a fixed ramp.
- The `slot-info` element renders with CSS fade rules but has no handler behind it.
- Recommendation: **wire the first, remove the second.** Answer `default` and I will just do it.

---

## Part 3: Answer sheet

Sections A and B are answered inline above. Section C is answered. These remain open.

| ID | Question | Your answer |
| --- | --- | --- |
| C1 | Console model: frame, panel, or floor | **(a) console as the frame.** The frame is the honesty device, because a polished presentation invites the assumption that it is smoke and mirrors |
| C2 | What lives in the console, what gets cut | **Cut the prompt. Keep the stream, rename it.** Console content should be real commands that run the project |
| C3 | Typed command line: remove, record, or interactive | **(b), synthesized but pulled from reality** |
| C4 | How real are the console commands | |
| C5 | What to call the evidence stream | |
| D1 | Website part to infrastructure mapping: strike or add rows | |
| D2 | What causes a part to appear | |
| D3 | Real database and load-balanced service, or depict | |
| E1 | Optimize visuals for Teams share | |
| E2 | How you share during the call | |
| F1 | Deadline and available working days | |
| F2 | How live on the call | |
| G1 | ADR 0005: superseded or current | |
| G2 | Four-node framing: scope or requirement | |
| G3 | Intro length: leave at 2:27 or tighten | |
| G4 | BOOT_TASKS and slot-info: wire or remove | |

**Blocking order.** E1 now gates the prototype layout work on its own, since C1 and C2 are settled. C4 and F2 are
the same decision and set how much backend gets built. F1 and D3 set scope. The rest can follow.

---

## Part 4: What happens after you answer

1. Rebuild the prototype around a single console, per C1 and C2.
2. Rewrite the stage script so each stage delivers one website part from D1, with its constraint named.
3. Apply the Teams legibility pass from E1.
4. Stand up whatever D3 requires on the cluster, and capture recorded fallbacks for everything slow.
5. Wire live reads, and live writes only where F2 allows.

## Related records

- [Capstone product definition](README.md)
- [Product architecture](product-architecture.md)
- [Build roadmap](build-roadmap.md)
- [Command Center design direction](command-center-design.md)
- [Self-building learning demo](self-building-learning-demo.md)
- [Interaction research](interaction-research.md)
- [Platform boundary research](../docs/planning/azure-local-platform-boundary-research.md)

