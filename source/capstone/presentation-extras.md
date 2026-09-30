# Presentation extras

A parking lot. Ideas that belong in or around the capstone presentation but are not the
presentation itself. Nothing here is finished. The point is that good ideas stop getting lost
between sessions.

Status key used below:

- GROUNDED means the claim is recorded somewhere in this repo and the source is cited.
- MINE means the owner has to supply it, because the repo does not contain it.
- GENERAL means it is true of Azure Local broadly but is not a finding of this POC. Do not
  present it as something we proved.

---

## 1. Questions the room will ask

Ordered roughly by how likely they are.

### "Your Azure view shows six machines. You said four. Which is it?"

Both. GROUNDED.

Arc sees every machine that has the agent installed. The cluster is the subset that passed
validation. Live Resource Graph on 2026-08-31 returns six Arc-connected hosts, and
`Get-ClusterNode` returns four.

Nodes 03 and 05 are Arc-connected and not cluster members. Node 03 is a viable spare with two
working data disks. This was a deliberate scope decision, not an accident.

Source: [decisions/0004-four-node-functional-poc-scope.md](decisions/0004-four-node-functional-poc-scope.md)

The useful follow-on: this is a good illustration of the split between the control plane and the
cluster. Arc is inventory and management reach. Cluster membership is a storage and failover
contract. They are not the same thing and the portal shows you both.

### "Is this production ready?"

No, and the project has always said so. GROUNDED, and worth quoting directly rather than
paraphrasing.

> This is a functional POC, not a production supportability, HA, DR, performance, or capacity
> certification.

Source: [STATUS.md](STATUS.md), and the same framing in [README.md](README.md)

Do not soften this. The credibility of everything else depends on it.

### "Why did it take so long?"

GROUNDED, and the intro answers it better than a sentence can. Three things stacked.

1. A requirement read more strictly than it was written. We were told the strict Secure Boot
   posture was needed. The published requirement is one sentence and says only that Secure Boot
   must be present and turned on.
2. Parts that did not fit, and a fleet that lost two of six machines.
3. Storage ports transposed on three of four machines, which took an LLDP capture to see because
   node 02 was wired the way the documentation described and the other three were not.

Then the deployment itself ran 54 of 54 steps in 2h 13m, with none of them failing.

The line worth landing: all of that, to earn a run that boring.

Do not attach a duration. The build ran alongside other work and was never tracked as dedicated
time, so any number invites a comparison the project cannot defend.

### "What happened with the drive?"

GROUNDED and it is the strongest material we have. A drive died in a lab 200 miles away and the
only consequence was a number in a health report. Then the platform refused to let me reboot my
own machine, four times, and it was right every time.

Source: [docs/runbooks/drive-failure-expectation-vs-reality.md](docs/runbooks/drive-failure-expectation-vs-reality.md)

Expect the follow-up: "so it got in your way." Answer honestly. Yes, and there is no lab
override, because the system cannot tell disposable hardware from irreplaceable hardware and so
it assumes the worst. That refusal is the product.

### "Can I reach the dashboard? What is the URL?"

There is no URL, and that is a stated boundary rather than a failure. GROUNDED.

The dashboard runs behind a ClusterIP Service and is reached with `kubectl port-forward`. A
LoadBalancer VIP on the management subnet would need external permission that we deliberately did
not request.

Source: [docs/planning/external-dependencies-and-poc-lessons.md](docs/planning/external-dependencies-and-poc-lessons.md)

Quote if pressed: "MetalLB, a management-subnet VIP pool, and a Kubernetes LoadBalancer Service
remain documented but out of the current executable scope. This is a valid POC boundary, not a
cluster failure."

### "Where is the CI pipeline?"

Never ran. GROUNDED and already in the recap caveats. EMU blocks GitHub hosted runners, and there
is no private registry, so images come from Microsoft Container Registry.

Do not dress this up. It is in the "what this was not" list on purpose.

### "How does it scale? How many VMs can it take?"

Do not answer this with a number. GROUNDED constraint:

> The four-node cluster has limited memory headroom. Avoid assuming every host can accept another
> general-purpose VM.

Source: [README.md](README.md)

And separately, node 01 is running on two data disks after the NVMe failure, which STATUS.md
flags as a maintenance risk with an explicit instruction to avoid stress or scale claims.

### "Why southcentralus for an on-premises cluster?"

GROUNDED and there is a real rationale on file. The POC selected southcentralus from the supported
control-plane regions after comparing management-plane latency. eastus is a commonly documented
alternative; the choice must be evaluated against the deploying environment's requirements.

Source: [decisions/0001-arc-control-plane-region.md](decisions/0001-arc-control-plane-region.md) and
the original plan rationale

### "Why is Docker in a VM instead of on the hosts?"

Deliberate. GROUNDED.

Source: [decisions/0006-docker-operations-disposable-vm.md](decisions/0006-docker-operations-disposable-vm.md)

The general principle is worth stating: the Azure Local hosts are the platform, and you do not
install workload tooling on the platform. The container host is a guest that can be destroyed and
rebuilt without touching the cluster.

### "What did this cost, and is it cheaper than the cloud?"

MINE. The repo contains no cost analysis, no licensing model, and no comparison against public
cloud. There is a single line noting the extra 512GB M.2 per node was already planned.

Either prepare a real answer or decline cleanly. A confident guess here is the fastest way to
lose the room, because somebody in it will know the actual numbers.

### "Was any of this on the Azure Local catalog?"

No. Workstation class hardware, not certified. Already in the recap caveats, GROUNDED. It is
also the reason the third data disk per node existed, and the reason the failure was survivable.

---

## 2. Where this technology fits

The section the owner asked for. Mostly MINE, because the repo proves the platform works and never
says who it is for.

### What the repo actually supports saying

GROUNDED, and it is a narrow but real claim:

> The Azure control plane extends to on-premises hardware. The same portal, CLI, RBAC, and
> templates apply to servers in our own rack.

Source: [capstone/prototype/scenario.js](capstone/prototype/scenario.js)

And the goal, stated plainly:

> The goal was not to claim production readiness. The goal was to prove that the lab hardware and
> Azure control plane could form a working Azure Local cluster, host real Windows and Linux
> workloads, run AKS, and demonstrate the important recovery and application-platform behaviors.

Source: [README.md](README.md)

### What only the owner can supply

The repo does not contain any of this. It has to come from him or the section will be generic.

- What platform team actually runs and supports today. Build agents, lab services, test benches,
  domain infrastructure, file services, legacy VMs, whatever the real portfolio is.
- Which of those things are stuck on premises, and why. Latency to instruments, licensing tied to
  hardware, data that cannot leave, equipment that must be physically adjacent.
- Who the beneficiaries are. Which teams get to do something they cannot do now.
- Whether anyone has a cost or capacity problem this would relieve.

### Draft shape for the section, once the above is filled in

Three headings, roughly balanced. The balance is the point. A section that only lists strengths
reads as a sales pitch and gets discounted.

**Where it fits.** GENERAL, needs the owner's examples to become real.

- Work that has to sit near something physical. Instruments, test equipment, sample handling.
- Data with a residency or egress constraint that makes cloud storage awkward or expensive.
- Existing hardware that is already bought, already racked, and otherwise underused.
- Teams that want Azure tooling and Azure RBAC without the workload leaving the building.
- Steady state capacity, where you know roughly what you need and it does not swing wildly.

**Where it does not fit.** GENERAL. This is the more valuable half and it is the half people
remember.

- Anything that needs to scale elastically. You bought four machines. That is what you have.
  Public cloud absorbs a spike, a rack does not.
- Anything with real HA or DR requirements today. Single site, single rack, one power domain.
  This POC explicitly does not certify HA or DR.
- Anything you want to stop paying for when it is idle. The hardware costs the same whether it is
  busy or not.
- Anything where nobody wants to own physical maintenance. This POC lost two of six machines
  before it started and one NVMe during it. Somebody has to care about that.
- Managed PaaS shaped work. If the thing you want is a database you never patch, this is the
  wrong tool.
- Greenfield work with no on-premises constraint at all. If nothing forces it local, do not force
  it local.

**What it changes if you already have hardware.** GENERAL, and this is probably the honest
positioning for our situation.

The pitch is not that Azure Local is cheaper or faster. It is that hardware you already own stops
being a separate world with separate tooling. Same portal, same RBAC, same templates, same
inventory. The build described in the intro is the real cost of entry, and it was mostly paid in
requirements ambiguity rather than in the product.

---

## 3. Other parked ideas

Things raised and not yet done. Not in priority order.

- The three resilience runs and the live check are bound to `stage: null`, so v2 cannot show them.
  Giving resilience its own movement would fix that and would also stop the strongest material
  being reachable only from the standalone player.
- Interstitials between acts. Movements 06 and 07 sit inline with nothing marking the shift.
- The gate headline is still placeholder text written by the assistant, not the owner.
- Every run in `shared/runs.js` used to end on an aphorism. Two recent ones do not. The rest still
  do, and read back to back it becomes a tic.
- Jumbo frames are not enabled on the storage adapters. Measured 1514 and MTU 1500 fleet wide on
  2026-08-31. Performance question, not a correctness one, recorded in the wiring reference.
- Switch side configuration has not been verified since 2026-07-17. LLDP capture would confirm it
  self service, and the script exists, but there is no reason to run it until something changes.

### The live demo, parked 2026-08-31

The original idea was a web page whose features get built out through Kubernetes, so a refresh
shows something new. It is not dead, and the reason it stalled was misdiagnosed at first.

It has nothing to do with browsers calling Azure APIs. That constraint belongs to a different
idea, a console reaching outward to run diagnostics against the lab, which cannot work because a
browser has no route to workgroup joined hosts on an isolated segment and because a bearer token
with Contributor and User Access Administrator has no business being handled on a shared screen.

The real blocker for the live demo is narrower. There is no private registry, so there is nowhere
to push a new image that the cluster can pull from. Shipping an actual new feature means solving
that first.

What needs no new image, no registry, and no code change at all:

- `kubectl scale deployment dashboard --replicas=4`, then refresh and the page lists more instances
- delete a pod and watch the ReplicaSet rebuild it, which is the self heal story happening live
  rather than being described
- change a ConfigMap the app reads, if the app is ever rewritten to read one

Access is `kubectl port-forward` to `localhost:8080`, which works today and is tethered to the
presenting laptop.

Not attempted for the capstone. Two days was not enough runway to add a live dependency to a
presentation that currently has none.

### The curtain button, parked 2026-08-31

A button near the movement controls that opens the large terminal and shows what is actually
running underneath. Blocked by the same split described above. Roughly half the interesting
commands are Azure control plane reads that a browser could genuinely make, and half are host
level PowerShell and kubectl that it cannot.

The workable version, if it is ever built: a script runs the real checks minutes beforehand and
writes JSON, and the overlay renders the output next to the exact command with a stamp saying how
old it is. Real data, really collected, no token in the browser. Plus a copy button so any command
can be run for real in a separate terminal if the room pushes.

### The register, parked 2026-09-01

The owner's design for the acceptance criteria pane, agreed but not built, because the runs and steps
pane has to come back underneath first and he wants to look at the current state before either.

The two changes are really one change. The eighteen criteria currently fill the pane with zero
slack, so there is nothing to scroll. The scroll only becomes possible because the how comes back
underneath and takes half the height, leaving about nine of the eighteen rows visible. That is
what makes travel legible: there is always something above and below.

A fixed register sits about 40 percent down the pane, marked with a hairline band and corner
ticks. On each movement the list travels so that movement's criterion comes to rest inside it, and
the stamp fires in place once it has settled.

The motion is a heavy wheel rather than a slide. It carries past the mark and then leans back into
it, which is the part that makes it read as something mechanical registering rather than a list
scrolling. Two terms, animated on scrollTop by hand so the easing is controllable:

    base = 1 - (1 - p)^3                     travel, fast out and slow in
    bump = sin(p^1.6 * PI)                   one lobe, peaks at p = 0.65, back to zero at p = 1
    scrollTop = from + travel * base + direction * 11px * bump

Eleven pixels of overshoot as a fixed distance rather than a percentage, because a detent is the
same size whatever the wheel just travelled. Duration scales with distance, roughly 850ms plus
3.2ms per pixel, capped near 1800ms.

It sits inside the viewing budget comfortably. Worst case travel is about three rows, so 130px.
Peak velocity of an ease-out cubic is three times its average, so 302px per second, which is 25px
per delivered frame against a 30px row. A ratio of 0.84. The settle is far safer than that: in the
last 300ms it moves about five pixels in total, which is motes territory, and the stamp itself has
zero displacement.

One accident worth keeping. Availability Sets sits at index 10, above Docker at 11 and 12, so
after movement 08 the list travels back up to finish a criterion it started at 07. The two domain
story becomes physical without anybody designing it that way.

### The cannon shot, parked 2026-09-01

The handoff from movement 02 into the BUILT cutaway currently draws a line from the rail underline
to the button. A shot was tried instead, on the reasoning that a line says these two things are
related while a shot says that went there, which is the thing the room has to learn in the one
second it gets to learn it.

It was built and it worked and it was reverted, because it is invisible over remote desktop. That
is how the deck is actually viewed, and Teams will be no kinder.

The rule this produced is worth more than the effect, and it applies to everything else in the
prototype. The first version of it was wrong, and the correction came from watching the motes.

Motion is not the problem. The motes drift constantly, they look smooth over the same remote
session that killed the shot, and the effect is one of the better things in the deck. What
separates them is displacement per delivered frame, measured against the object's own size, on the
assumption that the stream delivers something closer to 12 frames per second than 60.

    (distance in pixels / (seconds x 12)) / object size in pixels

Under about 1.0 and the object overlaps itself every frame, so a dropped frame costs nothing that
can be perceived. The motes travel about 90 pixels over 15 seconds, which is half a pixel per
delivered frame against an 8 pixel glow, a ratio of 0.06. The tracer travelled 1150 pixels in
780ms, which is 123 pixels per delivered frame against a 46 pixel object, a ratio of 2.7. It was
never a streak. It was nine unrelated dashes, and the eye correctly reported nothing.

That also explains the artifacting where the glow meets the black. Banding on a smooth gradient is
the encoder quantising, which is a fidelity cost rather than a continuity cost, and it does not
stop the effect landing.

So there are three ways to stay inside the budget. Transform in place, where displacement is zero
and nothing can be lost. Accumulate, like a stroke revealed by dashoffset, where every frame adds
to what is already painted. Or move slowly enough, or make the object long enough, that the ratio
stays under one.

The implementation is in commit `cc76d94`, reverted whole in `7184625`. If the viewing medium ever
changes, that commit restores it. The shape of it:

- the flair layer becomes a `div` rather than an `svg`, because the tracer is a real element
  travelling an `offset-path` instead of a stroke being revealed
- a muzzle ring at the rail underline, a streak with `offset-rotate: auto` so it points along its
  own path, an impact ring on the button, and the button recoiling rather than lighting up

Two bugs came out of building it that will bite again anywhere else motion paths get used.

Keyframes with no explicit offsets are spaced evenly. Three position keyframes put the middle one
at the halfway mark, so the shot spent the entire first half of its flight covering 18 percent of
the distance and then had to whip through the rest. It was being deleted at 28 percent of the path
while the impact ring fired at a button it had never reached. Position and opacity have to be
separate animations.

The arc apex has to be clamped on screen. Computing it as a fixed distance above the higher of the
two endpoints put it at `y` of -122, because the BUILT button already sits near the top edge. The
shot flew out of view and came back.

If it is ever revived, the fix for the visibility problem is a trail rather than a faster head. Draw
the arc as a revealed stroke synchronised to the same duration and easing as the travelling head,
so the head is welded to the tip of something that accumulates. That works for a reason the ratio
makes obvious: a trail is as long as its own path, so the object size term becomes the whole
distance and the ratio can never exceed one. Slowing the flight to about four seconds would also
bring it inside budget on its own. It was written and never seen, so it is unproven.
