---
title: "0008 - ASUS Hyper M.2 card mechanically incompatible with 1U chassis"
domain: [storage]
layer: [hardware]
type: decision
status: current
proof: proven
audience: [engineer]
tags: [adr, asus-hyper-m2, mechanical-fit, 1u-chassis, carrier-card]
updated: 2026-09-12
---

# 0008 - ASUS Hyper M.2 card mechanically incompatible with 1U chassis

- **Status**: Active
- **Date**: 2026-06-24
- **Owner**: labadmin
- **Revisit when**:
  - The selected RIITOP replacement PCIe M.2 carrier is validated in the chassis, OR
  - Dell-supported NVMe storage hardware replaces the PCIe carrier approach.

## Observe

- The original storage ADR selected ASUS Hyper M.2 X16 Gen 4 cards for Slot 6.
- Local admin reported the 1U server chassis could not close with the ASUS card installed.
- The physical obstruction was mechanical: the ASUS card was about 1/4 inch fatter than the bracket/chassis clearance allowed.
- The cards had to be returned.

### Refinement (2026-06-25): precise mechanical cause + brand direction
- Owner clarified the exact failure: the ASUS card's **heatsink overhangs the card's own mounting
  bracket by ~1/2 inch** -- i.e. ASUS built the cooler *beyond the standard add-in-card spec*. Because
  the heatsink protrudes past the bracket envelope, **the 1U server chassis lid cannot close properly**
  with the card installed. The blocker is the oversized heatsink breaking the card's height/footprint
  envelope, not the bare PCB width. (Supersedes the earlier "about 1/4 inch fatter" framing above, which
  under-described it.)
- Root rule learned: in a 1U chassis there is no vertical clearance to spare, so **any add-in card whose
  cooler/components exceed the standard card bracket envelope will prevent the lid from closing**, full
  stop -- regardless of electrical/bifurcation suitability.
- Brand direction confirmed: go with a **generic / no-name ("random") brand** carrier card rather than
  a name-brand reference design, specifically *because* the generic carriers keep their cooling within
  the standard bracket footprint and do not over-build the heatsink past spec. This matches the RIITOP
  Quad PCIe carrier already selected below (a generic-brand card), and the selection criterion is now
  explicit: **the replacement must keep all components within the card bracket envelope so the 1U lid
  closes without force.**
- Replacement selected: 6x RIITOP Quad PCIe NVMe Adapter, PCIe 4.0 x16 to 4Ports M.2 NVMe Converter Card, Amazon ASIN/listing `B0DPG4GLLX`.
- Replacement source: [Amazon RIITOP B0DPG4GLLX](https://www.amazon.com/RIITOP-Adapter-Converter-Bifurcation-Required/dp/B0DPG4GLLX)
- The listing title says "for 2U" and "PCI-e Bifurcation Required". Local understanding is that this chassis supports full-size card width through a riser card, and the RIITOP package also includes a half-height bracket.
- Prior-art evidence (2026-06-25): RIITOP is a generic/no-name brand, but listing **reviews/comments report
  using this exact card for our use case in a Dell server**. That is the reason to trust it over other
  no-name carriers despite the lack of a vendor HCL entry.
- Expected behavior: as a *passive* bifurcation carrier (no controller silicon of its own), the card
  should present each M.2 drive **directly to the platform as if wired to the motherboard** -- i.e. an
  "extension of the motherboard" -- so each drive enumerates in Windows as `BusType=NVMe` rather than
  behind a RAID/VMD remap. This is the hoped-for outcome that distinguishes it from the earlier Slot-6
  path that surfaced a Samsung PM9A1 as `BusType=RAID` behind Intel VMD/VROC. STILL TO BE VERIFIED on hardware.
- Physical acceptance still depends on the installed bracket/riser/lid clearance, not only the listing title.
- Earlier testing on AZL-NODE-01 had shown the Slot 6/add-in path could enumerate an alternate Samsung PM9A1 device, but it appeared behind Intel VMD/VROC as `BusType=RAID`, which Azure Local rejects for data disks.

### Correction (2026-09-12): the chassis is 2U, and it never mattered
- Every "1U" in this record, including its title, traces back to one relayed remark from local admin
  and was then repeated by every document that cited this ADR. Nothing measured it.
- Owner checked Dell's own specifications and the Precision 7960 Rack is **2U**. Title and filename
  are left alone because they are the historical record and are linked from several places; treat
  the rack unit count in them as wrong.
- **The decision does not depend on it.** The finding was always that the cooler stands proud of the
  card's own bracket envelope, so the lid does not close. That is true of a chassis of any height,
  because an add-in card that breaks its own envelope has no height it is guaranteed to fit. The
  rack unit count was decoration on a mechanical fact.
- The intro no longer says a number out loud. It says there is no vertical room to spare, which is
  what was actually observed.

## Orient

- The ASUS card failed on chassis fit, not just storage enumeration.
- This invalidates the ASUS-specific install path in ADR 0003 for the Precision 7960 Rack 1U chassis.
- The decisive constraint is **lid clearance in a 1U chassis**: the ASUS heatsink extends ~1/2 inch past
  the card's own bracket envelope (built beyond add-in-card spec), so the lid cannot close. A 1U has no
  spare vertical room, so component-over-bracket is fatal regardless of electrical fit.
- The core requirement remains unchanged: each node needs poolable data NVMe devices exposed to Windows as `BusType=NVMe`, not `BusType=RAID`.
- Any replacement card must satisfy bracket/riser/lid fit **(all components within the bracket envelope)** and PCIe bifurcation behavior.
- Prefer generic/no-name carriers that stay within spec over name-brand cards that over-build the heatsink past the bracket.
- The RIITOP card is still a passive bifurcation-dependent carrier, so BIOS slot bifurcation remains required.

## Decide

Return the ASUS Hyper M.2 X16 Gen 4 cards (oversized heatsink overhangs the bracket by ~1/2 inch and
prevents the 1U lid from closing) and go with a generic-brand quad PCIe NVMe carrier that keeps all
components within the card bracket envelope -- currently the 6x RIITOP Quad PCIe NVMe Adapter cards.

## Act

- Treat ADR 0003 as superseded for the adapter-card model choice, but still useful for the drive-count and S2D symmetry rationale.
- Update active handoff/checklist language to refer to the replacement PCIe M.2 carrier card instead of the ASUS card.
- Validate the replacement card in this order:
  - chassis closes without force,
  - card seats cleanly in the intended PCIe slot,
  - the correct bracket is installed for the riser/chassis,
  - no riser/lid/bracket interference exists after the chassis is closed normally,
  - BIOS sees the carrier/drives,
  - Windows sees the data drives as `BusType=NVMe`,
  - Azure Local hardware validation sees 2+ poolable data NVMe disks per node.

