# Presenter brief

Rehearsal material. Facts at your fingertips, what to say over each movement, and the specific
places where a confident sentence would get you into trouble.

The console no longer labels itself as a replay on every panel, because that reads as nervous and
the room already knows you did not rebuild a cluster for a demo. The trade is that you carry it
verbally instead. That is what section 1 is for.

Deeper answers live in [presentation extras](presentation-extras.md). This file is the version you
practice out loud.

---

## 1. Say this once, near the start

You need one sentence early that frames the whole thing, and then you never mention it again.

Something in this shape:

> "Everything you are about to see is a replay of commands that really ran on the cluster. The real
> deployment took two hours and thirteen minutes, so I am not going to make you sit through it."

That is it. One mention. It is honest, it explains the pacing, and it moves on.

The panel still shows the real duration for each run, so the number is on screen when it matters
without the word "simulated" appearing ten times.

**The one genuinely live moment.** The `alive` run in movement 09 hands you a command to type in a
real terminal. It is read only, it takes about three seconds, and it is the moment that proves the
rest was not a video. If the network is uncooperative there is a fallback button that plays the
recording instead. Decide beforehand whether you are doing this, and have the terminal open.

---

## 2. Numbers to know cold

If you know these without looking, you will sound like you built it. Because you did.

| Fact | Value |
| --- | --- |
| Deployment | 54 of 54 steps completed, none failed, 2h 13m |
| Hardware validator | 25 checks, no critical failures |
| Heaviest single step | Arc infrastructure components, about 64 minutes |
| Physical build | Much longer than anticipated |
| Cluster members | Four: AZL-NODE-01, 02, 04, 06 |
| Arc connected machines | Six, which is why Azure shows more than four |
| OS build | Azure Stack HCI 10.0.26100.32690 |
| Kubernetes | v1.33.5 |
| Storage | Storage Spaces Direct, three way mirror, three data disks per node |
| Storage fabric | VLAN 711 and 712, PFC on priority 3, SMB_Direct at 50 percent ETS |
| Region | southcentralus, roughly 1,800 miles, about 30 ms |
| Subscription | contoso-lab-sub |
| Resource group | rg-azlocal-poc-001 |
| Dashboard | Two replicas, scaled two to three to two during the test |

One number is measured and everything else about timing is not. The 2h 13m is real. Do not put a
duration on the build. It ran alongside other work, nobody was tracking it as dedicated time, and
"much longer than anticipated" is both true and unarguable. "Two months" invites a comparison the
project never measured.

---

## 3. What to say over each movement

One or two beats each. The visual carries the rest.

**00. Six machines, one concern.** Start here because it is the honest starting point. Six machines
were bought. Not all six made it. The concern is whether any of this would work at all.

**01. Four machines carry the cluster.** Four passed validation and formed the cluster. Two did not.
One had a card that physically did not fit, the other was deferred. This is a scope decision that is
written down, not an accident you are glossing over.

**02. The machines become a fabric.** This is the long storage story compressed into one movement.
Two switches, two VLANs, RDMA over converged ethernet. Storage traffic gets its own path and half
the bandwidth guarantee. Worth pausing here, because this is where all the pain was.

**03. Scheduling arrives.** AKS Arc lands on top. The same `az` CLI you would use against a cloud
cluster, pointed at hardware in the local lab.

**04. Something is being served.** A workload, actually running, two replicas, reachable inside the
cluster. The first moment the rack does something useful rather than merely existing.

**05. Capacity follows demand.** Say "operator initiated" out loud here. You scaled it. Automatic
demand driven scaling needs the Metrics Server, which is a documented addition that was not made.
Claiming autoscale here is the easiest mistake in the whole deck to make.

**06. A machine, written down.** Terraform planned, created, verified, reconciled state for, and
destroyed a real VM. Infrastructure that can be read, reviewed, and reversed.

**07. Containers, without Kubernetes.** Docker and Dockge in a guest Linux VM. Two ways to run a
workload on the same hardware. Note that Docker is deliberately not on the hosts, because the hosts
are the platform.

**08. A machine leaves, and the fabric heals.** A node goes down, storage degrades but stays online,
and repair jobs start that nobody started. Degraded is not the same as down, and that distinction is
the whole point. It was node 01, and it rejoined after about 26 minutes with all six virtual disks
back to Healthy. See the trap in section 4 before you say anything about the workload here.

**09. What was proven.** The recap, plus the caveats, plus the live check if you are doing it.

---

## 4. Traps

These are the sentences that would cost you the room. Each one has a document behind it saying why.

**Do not give a capacity or scale number.** Both README.md and STATUS.md instruct against stress or
scale claims while node 01 runs on two data disks. If asked how many VMs it holds, say the honest
thing: there is limited memory headroom and you have deliberately not characterised it.

**Do not guess at cost.** There is no cost analysis anywhere in this project. Somebody in the room
may know the real numbers. Decline cleanly.

**Do not claim the workload kept serving during the node failure.** This one is specifically flagged
in movement 08 as unverified. The node failure test and the AKS workload were separate pieces of
work, and whether the dashboard was even deployed during the outage is not recorded. Storage
continuity is proven. Workload continuity is not.

**Do not say jumbo frames are enabled.** Measured 1514 and MTU 1500 across all four nodes on
2026-08-31. It is an open item, not a configured feature.

**Do not claim an external load balancer or a public URL.** Internal Kubernetes Service routing is
proven. An external VIP needs a subscription provider registration that was requested and denied,
and then deliberately not escalated. Say it as a decision, not a wall: exposing a test environment
wider is well understood technology with a known cost, and none of it would have taught us anything
about Azure Local. The dashboard is reached by port forward.

**Do not say the CI pipeline runs.** The workflow is authored and has never run. EMU blocks
GitHub hosted runners for user owned repositories.

**Do not claim the switch side is currently verified.** Last confirmed 2026-07-17. The host side
gives no DCBX confirmation, all Remote fields return Not Available.

**Do not say there were no retries.** The final run completed 54 of 54 steps with none failed, and
that is the claim to make. Counting the step lines gives 53 Success and 1 Skipped, the skip being
the environment validation that had already run separately. It is not the same as saying the
deployment never needed retrying. Validation and earlier attempts took plenty. "Every step of the
run that worked, worked" is true. "No retries" is not, and somebody who watched it happen will know.

**Do not oversell the reboot refusal.** The platform blocking a node restart during storage repair
is a meaningful data point about safety interlocks. It is not drama. Mention it as evidence that the
system protects data even when that is inconvenient, and move on.

---

## 5. When you do not know

You will get a question you cannot answer. That is normal and it is survivable, as long as you do not
improvise a fact.

Useful shapes:

- "That was not tested. Here is what was." Then name the adjacent thing that was.
- "I do not have a number for that and I am not going to guess at one."
- "That is written down. I can pull it up after this."
- "That is outside what this POC was scoped to prove."

The one thing that damages credibility is a confident answer that turns out to be wrong. Everything
in this project is documented precisely enough that "let me check" is a completely reasonable answer.

---

## 6. Where the deeper answers live

If a question goes past the movement on screen, these are the four places worth knowing.

| Question shape | Document |
| --- | --- |
| Did you do what you said you would | [POC requirements gap audit](../docs/planning/poc-requirements-gap-audit.md) |
| Why did you not build X | [Azure Local platform boundary research](../docs/planning/azure-local-platform-boundary-research.md) |
| What about security | [Security posture and boundaries](../docs/access/security-posture-and-boundaries.md) |
| Likely audience questions | [Presentation extras](presentation-extras.md) |

The boundary research is the one to know best. Several items on the original wish list named Azure
public cloud resources that do not exist on Azure Local, and that finding reframes most of the gaps
as translation rather than failure. It is fully cited.

**The Curtain button** puts the full terminal over the console, already on the run you were just
discussing, with speed controls. That is your route when somebody wants to see the actual output
rather than the summary. It also reaches the three runs that sit outside the arc, including the
drive failure.

---

## 7. The closing thought worth landing

Two candidates, depending on the room.

For a technical audience: the work it took to earn a deployment run that boring. Fifty four
steps, not one of them failed. Everything interesting happened before that run started.

For a broader audience: moving on premises does not reduce the security surface, it adds to it. You
keep every control the cloud gave you, and then you add a building, a rack, a set of management
controllers, and a domain. The platform helps more than expected. What it cannot do is close the
physical gap, and physical is exactly what you signed up for when you chose to own the hardware.
