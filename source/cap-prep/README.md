# cap-prep

**Not part of the presentation.** This is study material for the presenter and nothing here is
shown to a room, published, or referenced by the capstone deck. It lives outside `capstone/` for
that reason. Nothing in the deck depends on it, and deleting the whole directory would change
nothing about the deliverable.

Open [index.html](index.html) directly in a browser. No server, no build, no dependencies.

## What it is for

Learning these technologies properly, so they are yours rather than something you did once. The
presentation is the deadline, not the purpose. Nobody is coming to catch you out, and knowing this
material well is worth having regardless of how the hour goes.

Every card is three parts:

- **say** what a good answer covers, in the order you would say it
- **why** the idea underneath, which is what turns a fact into something you can reason from
- **ours** what this project did, which connects the general idea to something you actually saw

Learn the first two. The third is the bridge back to your own evidence.

Thirteen cards carry a **diagram** for machinery that is hard to hold in words. Plain monospace,
no library, and legible over a remote session.

Forty one cards carry commands, and those get two extra blocks. **At the prompt** is a console,
never a sentence, because a thing you type should never be mixed into prose. **How to look it up
yourself** is the built in help for that tool, because remembering flags is a losing game and
knowing how to ask the tool is not. Every card with commands has one.

Commands live in [deck-commands.js](deck-commands.js), attached to cards by id, so the whole
command set can be reviewed together rather than hunted through five files.

Seventeen cards show a real **artifact** underneath what we did: the actual Dockerfile, the actual
Deployment spec, the actual RBAC Role, the actual Terraform module block, copied from this repo
with the path above it so it can be opened and checked. Describing our work in the abstract
teaches nothing. Installs two packages is not a fact you can use anywhere else, and a nine line
Dockerfile you have read is.

They are in [deck-artifacts.js](deck-artifacts.js), attached by id the same way.

## How to use it

Say the answer out loud, all the way through, before revealing anything. The attempt is the part
that works. Reading a good answer and nodding along feels like learning and mostly is not, and
recognising a right answer in a list trains the wrong thing entirely.

Then reveal and mark honestly. Knew it, roughly, or not yet.

Keyboard: space reveals, then 1, 2 or 3.

Cards you mark **not yet** come back about six times as often as cards you know, so the deck drifts
toward whatever has not landed. Progress is per browser and clears with reset.

## Tracks

| Track | Cards | Covers |
| --- | --- | --- |
| kubernetes | 27 | From what a node is up to disruption budgets and network policy |
| terraform | 20 | The model itself: plan against apply, state, drift, the dependency graph |
| docker | 19 | Images, layers, registries, persistence, and where Compose stops |
| azure-local | 21 | The stack, the fabrics, clustered VMs, live migration, and what this project learned |
| project | 12 | Talking through what was built |

Four levels. **basic** is vocabulary and first principles, and there are deliberately a lot of
them, because they are the pegs the harder material hangs on. **core** is the ideas everything else
depends on. **working** is normal follow up. **deeper** is the detail you would want if the
conversation goes somewhere specific.

## The rule for adding cards

Every card carries a source. Technology cards cite the vendor documentation, project cards cite a
path in this repo. A card with no source does not go in, because study material that teaches a
confident wrong answer is worse than no study material.

Add to the relevant `deck-*.js`. One object per card, picked up on reload.

## Known gaps

- Networking below Kubernetes. VLANs, RDMA and the storage fabric are covered from the Azure Local
  side but not as networking in their own right.
- Azure identity and RBAC, PIM, and how subscription level permissions actually resolve.
- Windows Server specifics. Failover clustering as a technology, Hyper-V, and Active Directory.
- Git and CI as topics, rather than as things this project happened to use.
