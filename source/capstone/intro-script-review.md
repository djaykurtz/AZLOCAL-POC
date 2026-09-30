# Intro script, for review

Every line of narration and every card in the director's cut, in order, with a slot against each
one. Easier than catching problems as they fly past at full speed.

Source: [capstone/prototype/intro.js](prototype/intro.js). Ids are stable, so quote the id rather
than the line number when you want something changed.

## How to mark it up

Put one of these in the **Note** column, plus whatever you want to say:

| Mark | Means |
| --- | --- |
| `KEEP` | Fine as is, no comment needed |
| `CUT` | Remove this line entirely |
| `REWORD` | Right idea, wrong words. Say what is off |
| `WRONG` | Factually incorrect. Say what actually happened |
| `SLOW` | Needs more time on screen before the next line |
| `ADD` | Something missing here. Put the new line in the Note |

Types: **say** is the big line at the bottom. **card** is a small pinned note that piles up.
**banner** is a quoted requirement on the left. **stamp** is a red or green mark. **slam** is the
angry zoom and shake.

## The lens to read it through

The story and the outcome matter more than the detail. Most of what follows is true, and being
true is not the same as earning a place. A line survives if it moves the story, lands a feeling, or
is the fact the whole beat exists for. Detail that only proves we did the work can go, because the
work shows anyway.

Run time is not a constraint on any single line. The whole thing does have a length though, and it
currently runs about seven minutes. An intro nobody watches is worth nothing, so a line that is
merely true is costing something real.

## Current direction

Review one trial at a time. The presentation source in `prototype/intro.js` is authoritative, and
this file is generated from it by `scripts/New-IntroScriptReview.ps1`. Rerun that after any change
to the script, or this drifts out of step again, which is exactly what happened before.

Ids are positional. Quote the text rather than the id when a line might move.

### Where the weight is

| Trial | Rows | |
| --- | --- | --- |
| 6, The wire | 40 | Nearly a third of the whole script. The obvious place to cut. |
| 5, Drivers | 27 | |
| 4, Drives | 25 | |
| 3, The trap | 17 | |
| 1, Requirements | 14 | |
| 2, The rebuild | 12 | Already cut from 22. |
| 7, Starting line | 7 | |

### The storage network trial

This is the one that needs a pass. The material is mostly inconsistencies and their fixes rather
than gotchas, and the difference matters: a gotcha is something the next team would walk into, and
an inconsistency is something we happened to have. Somebody who knows enterprise networking better
might well have found a faster way to work out which adapter was which. Adapters enumerating in an
arbitrary order did not help, and that is worth one line rather than several.

What is worth keeping is the shape. Every test passed, and every test was measuring the wrong wire.
The cabling was right the whole time and the naming was wrong. That is the story. The switch
configuration detail, the VLAN specifics and the sequence of attempts are supporting evidence for a
point the audience will already have taken.

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

---

## Trial 1 - Requirements

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t1-01 | say | This project started as an exploration of what Azure Local has to offer. | REWORD: Start with the available Dell workstations and their non-certified status. Do not open with generic project intent. |
| t1-02 | say | The resources available were the medium to build out a cluster. | PENDING CUT: The same point belongs in the hardware opening. |
| t1-03 | say | Dell Precision 7960 Rack. Workstations really, enterprise oriented but not servers. |  |
| t1-04 | say | And certainly not on the Azure Local catalog. |  |
| t1-05 | say | The list of requirements is short, and completely reasonable. |  |
| t1-06 | banner | Secure Boot must be present and turned on.  [system requirements] |  |
| t1-07 | banner | TPM version 2.0 must be present and turned on.  [system requirements] |  |
| t1-08 | banner | At least two SSD class drives per machine, 500 GB or larger.  [system requirements] |  |
| t1-09 | banner | 32 GB of memory, minimum.  [system requirements] |  |
| t1-10 | banner | Network adapters must run signed manufacturer drivers.  [host network requirements] |  |
| t1-11 | say | But after the hardware was configured and made accessible, |  |
| t1-12 | say | cracks started to appear... |  |
| t1-13 | say | Zero storage drives to be found? |  |
| t1-14 | stamp | 0 poolable drives |  |
| t1-15 | say | Not one requirement truly qualified on the first day. |  |

---

## Trial 2 - The rebuild

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t2-01 | slate | Getting the hardware to agree with itself |  |
| t2-02 | banner | Secure Boot must be present and turned on.  [the requirement, in full] |  |
| t2-03 | say | Six machines, same model and form factor. We treated them as identical. |  |
| t2-04 | say | Two of them installed. The other four stopped at a black screen. |  |
| t2-05 | stamp | 0xc0430001 error. |  |
| t2-06 | say | Their firmware had been altered but there was nothing indicating that. |  |
| t2-07 | say | One of those changes dropped the certificate that signs the boot loader. |  |
| t2-08 | card | UEFI0073. Unable to boot because of the Secure Boot policy. |  |
| t2-09 | say | Restore factory keys, standard policy, trust firmware and OS. |  |
| t2-10 | say | Now the four carried what the working two carried. |  |
| t2-11 | card | Certificate scope back to Device Firmware and OS, not firmware alone. |  |
| t2-12 | say | But the OS on the disk was sealed for Secure Boot being off. |  |
| t2-13 | say | Turning it on gave back the same error it gave before. |  |
| t2-14 | say | Nothing here was certified, so we assumed the stricter mode was required. |  |
| t2-15 | say | It is not. We used the looser one and the check passed. |  |
| t2-16 | card | The check asks one question. Is Secure Boot enabled. |  |
| t2-17 | say | So all six were rebuilt from bare metal, with Secure Boot already on. |  |

---

## Trial 3 - The trap

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t3-01 | slate | The most dangerous button on the screen |  |
| t3-02 | say | The machines were imaged. Same media, every node. |  |
| t3-03 | say | The systems start up to the Server Core wizard. |  |
| t3-04 | say | Name the machine. Set the address. Turn on remote management. |  |
| t3-05 | say | And the next selection installs security updates. |  |
| t3-06 | say | It seems like the responsible thing to do. |  |
| t3-07 | say | But that pick stops you from building the cluster. |  |
| t3-08 | stamp | Recipe mismatch |  |
| t3-09 | card | The image is signed against a recipe that pins exact updates. |  |
| t3-10 | card | Any updates and the check no longer matches. |  |
| t3-11 | card | AzStackHci_OSImageRecipeValidation_LCU. Arc bootstrap refuses the node. |  |
| t3-12 | say | Some nodes had already done it to themselves, overnight, unattended. |  |
| t3-13 | say | While a warning exists. It is buried in a place you search for. |  |
| t3-14 | say | Nothing at this point tells you not to update. |  |
| t3-15 | say | The solution, complete re-image. Do not run security updates. |  |
| t3-16 | say | Let the platform handle it with onboarding, to keep validation. |  |

---

## Trial 4 - Drives

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t4-01 | slate | Dell Precision versus accuracy |  |
| t4-02 | say | The storage problem had a prudent answer. Buy a carrier card. |  |
| t4-03 | say | Dell makes the official one for this chassis. The DPWC400. |  |
| t4-04 | say | We passed on it. The cost, and how long it would take to arrive. |  |
| t4-05 | say | Six ASUS PCIe 4x M.2 cards instead. |  |
| t4-06 | say | The cooler stands half an inch past its own bracket. |  |
| t4-07 | stamp | Lid will not close |  |
| t4-08 | plate | Dell DPWC400. The part we passed on. |  |
| t4-09 | say | Dell's own card does exactly the same thing. |  |
| t4-10 | plate | The cooler stands past its own bracket. |  |
| t4-11 | say | A generic card keeps everything inside the bracket. |  |
| t4-12 | say | Then the slot is bifurcated. x4 x4 x4 x4, one per drive. |  |
| t4-13 | say | Three data drives per node, matched on every node. |  |
| t4-14 | say | A mixed count blocks the node from ever joining. |  |
| t4-15 | say | Node 05 came up with one drive, and an older part. |  |
| t4-16 | say | Node 03 would not hold a session long enough to validate. |  |
| t4-17 | stamp | 1 data drive |  |
| t4-18 | stamp | unstable |  |
| t4-19 | say | Two out of contention. Four still standing. |  |
| t4-20 | say | Which is the number we had committed to anyway. |  |
| t4-21 | stamp | 4 of 6 usable |  |
| t4-22 | banner | Four nodes. Three-way mirror, plus one node you can afford to lose.  [proof of concept scope] |  |

---

## Trial 5 - Drivers

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t5-01 | slate | Drivers and hardware never meant for this |  |
| t5-02 | say | Validation found the network cards did not match each other. |  |
| t5-03 | say | One adapter on node 02 was a different subsystem ID. |  |
| t5-04 | stamp | Not matched |  |
| t5-05 | card | Driver version, component ID, description. None of them line up. |  |
| t5-06 | say | Node 05 was already out of contention. So node 05 became the parts bin. |  |
| t5-07 | say | We pulled its adapter, put it in node 02, and benched node 05 permanently. |  |
| t5-08 | say | And then there is the drivers. |  |
| t5-09 | say | Every adapter was on a stock Microsoft driver, which Azure Local refuses. |  |
| t5-10 | card | The management NIC was running a generic driver from 2007. |  |
| t5-11 | say | Hardware validation had already passed every machine. |  |
| t5-12 | say | That check never looks at who wrote the driver. |  |
| t5-13 | card | Green on the validator. The documentation said otherwise. |  |
| t5-14 | say | Storage had a pre-flight gate, but networking did not. |  |
| t5-15 | say | The storage cards were easily matched to a Server driver package. |  |
| t5-16 | say | The management NIC is a workstation part. Nobody ships one for Server. |  |
| t5-17 | say | So you find the same silicon in an enterprise SKU, a PowerEdge, and pull that archive apart. |  |
| t5-18 | say | Then you convince the installer it is landing on Windows Server 2022. |  |
| t5-19 | say | Generic hardware, fine. Generic driver? DENIED! |  |
| t5-20 | card | Dell does not certify this chassis for Windows Server, let alone for Azure Local. |  |
| t5-21 | say | After days of tinkering, 25 hardware checks behind us. |  |
| t5-22 | stamp | 0 critical |  |

---

## Trial 6 - The Wire

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t6-01 | slate | The wire |  |
| t6-02 | banner | Two isolated storage VLANs. No gateway. No routing.  [network requirements] |  |
| t6-03 | banner | RoCEv2 requires priority flow control on priority 3, no-drop.  [network requirements] |  |
| t6-04 | banner | Every host and every switch port must agree, exactly.  [network requirements] |  |
| t6-05 | say | The last requirement was a fabric unlike any network most people run. |  |
| t6-06 | say | We built it exactly as documented. Zero of six connections. |  |
| t6-07 | stamp | 0 / 6 |  |
| t6-08 | say | Then came days of back and forth with the network team. |  |
| t6-09 | say | Packet captures, frame by frame, at both ends of every link. |  |
| t6-10 | card | Nobody builds a network shaped like this. That part was expected. |  |
| t6-11 | say | Their standard patterns came off, and untagged traffic passed. |  |
| t6-12 | say | Which looked very much like the answer. |  |
| t6-13 | stamp | untagged: PASSES |  |
| t6-14 | card | Lossless RDMA depends on priority flow control, carried in the 802.1p bits inside the tag. |  |
| t6-15 | slam | A native VLAN strips the tag. The priority goes with it. |  |
| t6-16 | say | It was the most dangerous result of the whole project. |  |
| t6-17 | say | Every test passes. The fabric quietly stops being lossless. |  |
| t6-18 | say | So we read every port and device ID off both ends of every cable. |  |
| t6-19 | say | Windows had enumerated the two ports in the opposite order. |  |
| t6-20 | card | Three of the four nodes had Port3 and Port4 on the wrong switch. |  |
| t6-21 | say | Every test we ran was correct, and measuring the wrong wire. |  |
| t6-22 | say | The cabling was right. The naming was wrong. |  |
| t6-23 | card | Node 02 was the exception. Its Port4 is the card we took from node 05. |  |
| t6-24 | stamp | switchport mode trunk |  |
| t6-25 | say | One rename, and one line of configuration the second switch never got. |  |
| t6-26 | say | Both fabrics passed, tagged. |  |

---

## Trial 7 - Starting line

| id | Type | Text | Note |
| --- | --- | --- | --- |
| t7-01 | say | Some of it never got explained. |  |
| t7-02 | say | Why two nodes booted when four would not. Why the firmware differed at all. |  |
| t7-03 | say | Nobody ever went back to find out. |  |
| t7-04 | say | Some things you fight for weeks. Some things quietly let you through. |  |
| t7-05 | say | The deployment was never the hard part. |  |
| t7-06 | say | Getting four machines to the starting line took much longer than anticipated. |  |
| t7-07 | say | Now the project can begin. |  |


## Open questions from my side

Things I would want your answer on rather than guessing.

1. **a1-15** is new, from your point about the memory being warned but never failed. Worth keeping
   as the one moment of grace in an otherwise rigid act, or does it break the rhythm?
   ### I think recapping this in act six pivoting from lingering questions to moments of unexepcted grace would be a great way to end the pre-build struggles with that touch of mystery and uncertainty. 
2. **a4-22** says install definitions were rewritten. That is from your account rather than from
   anything written down in the repo. Say it more precisely if it should be more precise.
   ### Sure. basically you couldn't get that driver for the workstation class hardware. But if you pick an enterprise sku poweredge type hardware and extract the driver archive you can make it think you are installing it on server 2022. I don't remember all the details exactly.

## Where I would cut first

My own list, so you have something to argue with. All of these are places where I wrote the
evidence instead of the story.

| Lines | What is there now | What it could be |
| --- | --- | --- |
| a1-36 to a1-39 | Four lines establishing that Deployed mode was never needed | Two. The identical checks line and the validator line carry it. 342 module files is a detail that proves I looked, not a detail that lands |
| a1-40 to a1-44 | Five lines on the key database | Three. The certificate that signs the boot shim is the fact. The rest is procedure |
| a1-23 to a1-30 | Eight lines on the installer working on some nodes and not others | Five. The feeling is nothing was consistent, and it arrives twice |
| a4-17 to a4-25 | Nine lines on drivers | Six. The 2007 driver and the Windows 10 packages are the two that land. The support line and known good configuration are the same point said twice |
| a5-08 to a5-11 | Four cards, each confirming something checked out | Two. Everything worked and nothing worked is the beat, and four proofs delay it |
| a5-32 to a5-41 | Ten lines from the reveal to the resolution | Six or seven. The node 02 explanation is lovely and slows the landing |

One I would not cut: **a5-17 to a5-26**, the native VLAN. It is long and it is the only place in
the intro where a thing that passed was worse than a thing that failed.

