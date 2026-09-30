# Media

Images for the capstone presentation. Kept here rather than in the prototype folder so the
prototype stays code, and so a file can be swapped without touching a stylesheet.

## Why these photos are load-bearing

Without them the room fills in the obvious explanation, which is that somebody failed to measure
a card. Length is trivially measurable and everyone knows it, so a bare statement that the lid
would not close reads as carelessness.

The actual cause is not measurable from a spec sheet. The cooler is built past the bracket
envelope, so the card is a standard length and still will not fit under the lid. Nothing in the
add-in card specification covers a shroud that stands proud of its own bracket, which is exactly
why buying the part and trying to close the lid was the only way to find out.

The fact that carries the most weight is that Dell's own carrier failed the same way in Dell's
own chassis. That is the difference between a team that did not check and a vendor that did not
validate its own part against its own hardware.

## On using vendor photographs

Settled 2026-09-03. This deck is not public facing, and using a seller's own product photo to
explain a fitment constraint is reasonable illustrative use. Vendor photos are fine here.

What is left is a craft question rather than a permission one. A card photographed flat on a
white field only half makes the point, because the constraint is a relationship between the
cooler, the bracket and the lid, and a photo of the card alone cannot show a lid.

Two things that make either kind of photo land:

- Crop to the bracket junction, so the overlap is the subject rather than something to spot.
- Annotate it. An arrow and a measurement across the overhang states the point instead of
  implying it. That also matches the drawing language the explain callouts already use.

A bench photo with the lid resting on the heatsink and refusing to close needs no annotation at
all, which is why it is still the best shot if one exists.

## Naming

`NN-subject.jpg`, numbered by the movement or act it belongs to.

    04-dell-dpwc400-installed.jpg
    04-asus-hyper-m2-lid-gap.jpg
    04-riitop-carrier-seated.jpg

## Treatment on a dark background

Do not try to knock the background out. A product photo with a white or grey field looks wrong
floating on black, and a bad cutout looks worse. Frame it instead, the way the rest of the deck
frames evidence: a hairline border, a small dark inset, and a monospace caption underneath
carrying the part number and the fact. The photo then reads as a specimen plate in a lab
notebook, which is the language this deck already speaks.

Two details that make it sit properly against the black:

- Drop the image opacity slightly, around 0.92, so it stops being the brightest thing on screen.
- Give the frame the same `--line` hairline as every other divider, not a heavier border.

## The story these illustrate

Facts as told by the owner on 2026-09-03, not yet confirmed against a receipt or an order record:

- Dell's own carrier, around 250 dollars per card, would not fit the workstation chassis and
  stopped the lid closing.
- The ASUS Hyper M.2 was too tall by a small margin, for the same reason. See
  [ADR 0008](../../docs/decisions/0008-asus-card-mechanical-incompatibility.md), which records the
  cooler overhanging its own bracket by about half an inch.
- A third party carrier from Amazon at under twenty percent of the Dell price fitted and worked.
  The RIITOP quad PCIe NVMe adapter, listing B0DPG4GLLX, is the one in the reimage checklist.

The point worth making from this is not that the cheap part won. It is that the expensive part
from the chassis vendor was never validated against the chassis, and there was no way to find
that out except by buying it and trying to close the lid.

## No photographs of physical hardware

Settled 2026-09-08. The machines live in a secure area and smart hands will not be asked to
photograph them. Physical shots are off the table, including the rack, the cabling and the
carrier cards on a bench.

That makes vendor product images the route for the card fitment story, which the section above
already accepts. It also means every other bit of grounding has to come from software surfaces,
so the portal captures below carry more weight than they otherwise would.

## Where to capture from

The ranked list, with what each shot proves, lives in
[capture-links.txt](capture-links.txt). It is ranked rather than alphabetical because the first
three are the ones the deck is actually missing. All of them need an active PIM elevation, so run
`scripts/Invoke-PocPimElevation.ps1` first. Subscription is `00000000-0000-0000-0000-000000000001`,
resource group is `rg-azlocal-poc-001`.

## Query captures, which are better than screenshots

A portal screenshot is a picture of a user interface at a moment. A query and its output is the
thing itself, and anyone who doubts a number can run the same line and get the same answer. That is
also how the rest of this project was built, so it is the honest register for evidence.

`scripts/Show-ClusterEvidence.ps1` runs the read-only queries and echoes each command before it
runs, so a capture shows both. It names the subscription before making any claim, and refuses to
run against the wrong one.

| Capture | Holds |
| --- | --- |
| [evidence-2026-09-09-arc-and-cluster.txt](evidence-2026-09-09-arc-and-cluster.txt) | Every Arc registered machine in one table, with the four cluster members flagged and their model, class and memory beside them. Movement 01's BUILT frame is drawn from this. |
| [evidence-2026-09-09-inventory.txt](evidence-2026-09-09-inventory.txt) | Subscription context, then the resource group counted by type. 53 resources, the count movement 09 quotes. |

Worth knowing what the cluster reports about itself, because it settles an argument the deck would
otherwise have to make in prose. Azure classes this hardware `ThirdParty`, every node reads
`Precision 7960 Rack` with 32 GiB, and `oemActivation` is `Disabled`. Microsoft's own API calls the
hardware uncertified, so no slide has to.

Dockge is on the tenant network and needs no Azure permission, only a route to
`10.10.0.0/22`. It is the cheapest capture on this list and the most convincing, because it is
a real interface running on the cluster rather than a view of Azure describing it.

The cluster is on a trial. It had 22 days remaining on 2026-09-04, so these blades have a
shelf life. Capture before renewing or losing them.

