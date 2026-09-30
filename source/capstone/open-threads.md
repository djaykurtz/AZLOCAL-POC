# Open threads

Loose ends, unanswered questions, and agreed work that is not built yet. A running worklist, not a
formal decision document. [vision-design-questions.md](vision-design-questions.md) is the formal
one and should stay tidy.

The convention: anything raised and not resolved lands here the same day, so ideas can keep coming
without the previous ones falling on the floor. Nothing here is blocked on anything else unless it
says so.

Updated 2026-09-02.

---

## Waiting on a decision from the owner

Only he can answer these. Everything else in the file is work.

| # | Thread | Why it matters |
| --- | --- | --- |
| D1 | **Audience scope for publication.** Narrowed 2026-09-03: the owner confirmed this is **not public facing**, which rules out external. Still open between immediate team and wider org. | Drives the sensitive content pass in `.ai/pre-publication-review.md`. Not public facing also settles that vendor product photos are fine as illustrative use |
| D2 | **Eight residual security risks are accepted but unsigned.** | Listed in `docs/access/security-posture-and-boundaries.md`, each marked DECISION REQUIRED. Accepting a risk in a document nobody signed is not acceptance |
| D3 | **Intro copy review.** In progress, second pass applied. The owner has flagged that a lot of the surviving narration is still the assistant's words rather than his, and will rewrite on the next pass. Nothing to change until then. | `intro-script-review.md`. He has to be willing to say every line out loud |
| D4 | **a1-15**, the memory grace line. Keep as the one soft moment, or does it break the rhythm? | Small, but it is the only line of its kind in that act |
| D5 | **a4-22** says driver install definitions were rewritten. That is from the owner's account, not from anything written down. | If it should be more precise, it needs his words |
| D6 | **Movement 10 and 10.5 need reworking**, including a real transition into questions rather than the word Questions on a screen. | Said, not specified. The five criteria landing at once on movement 10 is untuned pending this |
| D7 | **Does the dashboard page go into movement 04?** Screenshot in the cutaway, described panel, or left alone. | Movement 04 is called Something is being served and never shows what. See T4 |
| D8 | **Should the sprint plan nginx page be built**, or does Dockge's own UI carry the Docker web story? | `working/sprints/docker-on-cluster.md` step 2 was never run |

## Agreed, designed, not built

Work with a plan already written. No decisions outstanding.

| # | Thread | Where the design lives |
| --- | --- | --- |
| T1 | **The register.** Criteria pane scrolls so the active item comes to rest in a fixed frame, heavy wheel easing with an 11px overshoot, then the stamp fires in place. | `presentation-extras.md`, spec complete enough to build cold |
| T2 | **Restore the how underneath the criteria.** The steps pane comes back below the checklist. T1 depends on it, because the list currently fills the pane with zero slack and has nothing to scroll. | Parent commit `6d57c90` has the markup and `renderLog` with the 54 step meter |
| T3 | **Right pane redesign.** The owner's own plan to fold acceptance criteria into the main slides. Partially done: the checklist landed, the how has not come back. | His |
| T4 | **Measure the container recovery.** Sample the Dockge endpoint every 250ms, stop the VM, start it, record the real outage and recovery window. Same method as the rolling update and live migration runs. | Movement 07 currently has `real: 'not timed'` and no measured evidence |

## Known gaps

Things we know are missing. Not bugs.

| # | Thread | Detail |
| --- | --- | --- |
| G1 | **No cost analysis anywhere in the repo.** | It is a question the room may well ask and there is currently nothing to say |
| G2 | **Portal views 00.5 and 01.5 are sketches**, drawn from real resource names, never captured. | The blue frame says so on screen, which is honest, and a real capture would be better |
| G3 | **The gate headline is still placeholder text** written by the assistant. | `v2/index.html` |
| G4 | **Most runs end on an aphorism.** Read back to back it becomes a tic. | `shared/runs.js`. Two recent ones already end on facts instead |
| G5 | **No private registry**, so there is nowhere to push an image the cluster can pull. | Blocks the disposable dev environments proposal, which is the lead card on 10.5 |
| G6 | **cap-prep has no cards on** networking in its own right, Azure identity and RBAC, Windows Server and failover clustering as technologies, or Git and CI. | Listed in its README |
| G7 | **`marketState` returns UNKNOWN** in the dashboard stock quote. | Cosmetic, and it would look sloppy on a projector next to a real price |
| G8 | **The cutaway right pane scrolls** on movements 05, 07 and 09. Movement 07 runs 484px past the fold. | Tied to T2 and T3, so left alone deliberately |
| G9 | **Resolution is handled, legibility is the limit.** `fit.js` scales a fixed 1536x864 canvas by `min(vw/1536, vh/864)` and letterboxes the remainder, so nothing reflows and no layout can break. Re-measured 2026-09-14 by driving `apply()` across ten viewports from 800x600 to 3840x2160: the scale matched the expected value exactly every time and the stage fitted inside the viewport every time. 16:9 fills edge to edge, 4:3 takes 96px bars top and bottom at 1024x768, and 21:9 takes 440px bars either side at 3440x1440. The real floor is type size, not layout. The smallest text in the deck is 9px `.fabric-cap`, which renders at 7.5px on a 1280x720 share and 6px at 1024x768. | This replaces an earlier note claiming the design was not responsive. That was measured 2026-09-03, before `fit.js` existed, and it is no longer true. Treat 1280x720 as the practical floor for a shared window, and anything below it as readable-by-the-presenter only |
| G10 | **Nothing announces itself.** No `aria-live` on the narration, no roles on the movement rail, no focus management when the callout opens, and the intro is motion heavy with no `prefers-reduced-motion` path. | Raised when the caption was changing colour. That specific bug is fixed, but the underlying gap is real and this is a Microsoft audience |

## Unverified or stale

| # | Thread | Detail |
| --- | --- | --- |
| U1 | **Switch side configuration has not been verified since 2026-07-17.** | The LLDP script exists. No reason to run it until something changes |
| U2 | **Jumbo frames are not enabled on the storage adapters.** Measured 1514 and MTU 1500 fleet wide on 2026-08-31. | Performance question, not a correctness one. Recorded in the wiring reference |
| U3 | **Node 03 wiring values are from 2026-07-17 and unverified**, because it is workgroup joined and was not queried. | The wiring reference says so in its own note |
| U4 | **The Dell DPWC400 price is not a fact.** `capstone/media/README.md` says "around 250 dollars per card". A listing seen 2026-09-12 showed $109. | Removed from the intro rather than picked. The narration now says only that the ASUS was cheaper and in stock, which is what drove the decision and does not move |
| U5 | **Dell may list the DPWC400 as compatible with the Precision 7960 Rack.** Seen in a generated summary with no primary Dell page behind it. If true, the deck's line that Dell's own carrier failed in Dell's own chassis gets stronger, not weaker, but it needs a real source before anyone says it out loud. | Resolved in the deck 2026-09-14: the card claiming nobody had checked the vendor's part against the vendor's chassis was removed, so nothing on screen asserts it. Our own photograph of the cooler overhanging its bracket is first-hand and unaffected either way. The fitment failure was reported by two people on site rather than witnessed here, and that qualifier now stays with the presenter |
| U6 | **Where the Deployed Mode requirement came from is not recorded.** The Secure Boot document corrects the belief emphatically, so a belief was held, but nothing says whether it was read, relayed or assumed. | The intro says assumed, which is the claim that survives not knowing. Do not let it become "we were told" without a source, because that points at a person |

## Resolved recently

Kept briefly so the same question does not get asked twice.

- **Where do updates come from after setup.** Solution channel, not Windows Update. Answered from the cluster and written into ADR 0009 as an amendment.
- **Why SConfig offers updates at all.** It is generic Server Core tooling, unaware of the platform. Confirmed on the node.
- **Whether the two update documents disagreed.** They did not. The ADR's decision on KB pinning stands; only its timing advice was superseded.
- **Whether the chassis is 1U.** It is 2U, per Dell's own specifications. The claim came from one relayed remark in ADR 0008 that every later document then repeated, and nothing measured it. Recorded as a correction on that ADR. The intro no longer names a rack unit count at all, because the mechanical finding never depended on one: a cooler that stands past its own bracket has no chassis height it is guaranteed to fit.
- **Whether the intro run time is a problem.** No. Flow rate is set live and an extended cut can exist separately.
- **Whether `ws2025-core-01` comes back up.** No. Windows VMs cost more and nothing needs it.
- **Which movement earns Availability Sets.** Both 07 and 09, update domain then fault domain.
