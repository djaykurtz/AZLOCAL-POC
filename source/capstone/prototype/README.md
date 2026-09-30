# Capstone vision prototype

A self-contained webpage that plays the capstone narrative end to end. It exists to align on the product vision
before any backend work starts.

> **There is a newer mockup.** [v2](v2/index.html) rebuilds the interface around the decisions taken on
> 2026-08-28: one console as the frame, a collapsible transcript, colour that encodes connection kind, and the
> fabric morph. It also carries a commentary layer holding the open questions. This page remains the reference
> for the narrative and pacing.

## Run it

Open [index.html](index.html) directly in a browser. No server, no build step, no dependencies, no network calls.

Controls:

| Control | Action |
| --- | --- |
| `Director's cut` | Off by default. Plays the roughly two minute build story before the storyboard |
| `Begin` | Leave the cold-start screen and start playback |
| `Play` and `Pause` | Toggle automatic advance |
| `Next` and `Back` | Move one stage. Use `Next` freely to skip ahead |
| Stage rail | Jump to any stage |
| `1.0x` | Cycle playback speed: 1x, 1.5x, 2x, 3x, 0.5x |
| `Reset` | Return to the cold-start screen |
| Space, arrows, `R` | Keyboard equivalents |

During the director's cut, `Skip intro`, Escape, Space, or Enter jumps straight to the storyboard.

Run it in a real browser rather than the editor preview. The wire geometry is measured from live layout, and
the glow and blur filters need a normal browser compositor to look right.

## Distributing it

[Build-CapstoneSingleFile.ps1](../../scripts/Build-CapstoneSingleFile.ps1) inlines every stylesheet, script and
image the [v2](v2/index.html) deck loads into one portable HTML file at `out/capstone-presentation.html`. No
server, no assets folder, no network. That is the copy to hand to anyone outside this repository.

```powershell
.\scripts\Build-CapstoneSingleFile.ps1
```

**Rebuild after any change under `capstone/prototype/`.** The bundle is a build artifact, it is gitignored, and
it does not update itself. A change made only in the source will not reach the file people are actually given.

Two things worth knowing before editing the build:

- The script reads the asset order from `v2/index.html`, so a new stylesheet or script is picked up
  automatically as long as it is declared there. Never glob the directory, because load order matters.
- `intro.js` locates the media folder through `document.currentScript.src`, which is null for an inline script.
  The build rewrites that lookup and swaps the image file names for data URIs. If the photographs ever stop
  appearing in the bundle while working from source, that rewrite is the first place to look.

## Pacing

The storyboard runs deliberately slowly, because none of this work is instant in reality. Every scripted time is
multiplied by `PACE` in [scenario.js](scenario.js), and each stage shows the real-world elapsed time the work
actually took:

| Stage | Real elapsed time shown |
| --- | --- |
| Platform | 2h 13m to deploy |
| Appliance | ~25m to build and place |
| Image | ~3m to build and push |
| Kubernetes | ~90s to schedule and start |
| Scale | ~10s to reach ready |
| Terraform | ~6m plan, apply, and destroy |

To change the overall tempo, edit the single `PACE` constant. Raise it to slow everything down, lower it to speed
everything up.

## Visual language

Two influences, held to accents rather than a full theme:

- **Circuitry.** A drifting grid bed behind the shell, a faint circuit grid inside the canvas, and cyan light
  pulses that travel along each connection after it forms.
- **Growth.** Connections are not drawn instantly. They grow from source to target on an organic easing curve,
  in vine green, with a soft bloom that settles behind them. Nodes unfurl rather than pop. Spores drift upward
  behind the interface.

The growth bar under the stage title is the transition device. Each stage has one segment per evidence step, and
the bar fills as connections establish, so the audience can see the system knitting together rather than a
generic progress spinner.

## Terminology

This prototype does not present anything as something it is not. Two labels are used throughout, shown on every
stage and in the header:

- **Proven.** The numbers on screen were recorded from real runs on the POC cluster. Examples: the `90` request
  distribution of `26 / 30 / 34`, the `2 -> 3 -> 2` replica scale, the Terraform plan of `3 add, 0 change,
  0 destroy`, AKS `v1.33.5`, and the four-node cluster itself.
- **Storyboard.** Interface and narrative concept presented for review. The appliance image, the container build,
  and the closing system view are storyboard stages today.

The whole project is a proof of concept, so the honest framing is not real versus otherwise. It is
*demonstrated already* versus *designed and not yet demonstrated*.

## Files

| File | Role |
| --- | --- |
| [index.html](index.html) | Layout skeleton only |
| [styles.css](styles.css) | Command Center visual system |
| [scenario.js](scenario.js) | **The story.** Stages, evidence stream, modules, architecture nodes |
| [app.js](app.js) | Playback engine. Sequences and renders whatever is in `scenario.js` |
| [intro.js](intro.js) | The optional director's cut. Self-contained, opt-in, never runs by default |

## The director's cut

The storyboard opens with a working cluster, which quietly skips the part that took the longest. The
director's cut is the missing prologue: what the requirements asked for, what the hardware actually
reported back, and how many caveats sat between the two.

It is deliberately lighter in tone. The structure borrows from an old instructional cartoon. A calm
narrator reads the official requirement, the hardware tries to comply, and the caveat cards pile up faster
than they get cleared away. The cards stay on screen until an act resolves, because the accumulation is
the point.

Five acts, about two minutes:

| Act | Subject |
| --- | --- |
| Requirements | Six servers against a short list, the Secure Boot seal trap, and the two nodes that fell out of contention |
| The list | The 54 deployment steps, at speed |
| Parts | The carrier card that stopped the lid closing, and the adapter harvested from node 05 |
| The wire | Two isolated storage VLANs, and ports that Windows had named in the wrong order |
| Starting line | 2h 13m, and what it cost to get there |

Every number and quoted requirement is from the real build. Two things are framed rather than quoted, and
both are called out on screen as such. The step list names only the steps worth stopping on, because most of
the 54 names were never recorded and naming the obvious ones flattens the joke. The four-node target is
labelled `proof of concept scope`, not a platform requirement, because it comes from
[ADR 0004](../../docs/decisions/0004-four-node-functional-poc-scope.md) rather than from Microsoft.

## Change the story

Everything narrative lives in [scenario.js](scenario.js). The engine never needs editing to change the
presentation.

A stage looks like this:

```js
{
  id: 'scale',
  title: 'Capacity follows demand',
  fid: 'proven',              // 'proven' or 'story'
  exec: 'Executive line, <strong>bold for the point</strong>.',
  prompt: 'scale to handle more traffic',
  arch: ['p3'],               // architecture nodes to switch on
  hot: ['svc', 'p3'],         // nodes to highlight this stage
  pods: 3,                    // header counter
  mods: [ /* capability cards */ ],
  detail: [ /* what this proves, boundary */ ],
  stream: [ { t: 200, src: 'kubectl', msg: '...', tone: 'hot' } ],
  dwell: 1700                 // pause after the last line
}
```

Stream tones are `info`, `ok`, `warn`, and `hot`. Module value tones are `good`, `warn`, and `info`.

Architecture nodes are defined once in `ARCH_LAYERS` at the top of the same file, grouped into the five layers
shown on the canvas.

Connections are defined separately at the bottom of the same file:

```js
const STAGE_LINKS = {
  kubernetes: [['arc', 'aks'], ['aks', 'wrk'], ['img', 'dep'], ['dep', 'p1']]
};

const STAGE_PULSES = {
  heal: [['dep', 'p2']]      // re-energize an existing path without redrawing it
};
```

`STAGE_LINKS` grows new connections during a stage. `STAGE_PULSES` sends a light pulse down connections that
already exist, which is how the self-healing stage shows the controller acting through paths built earlier.

## Current narrative

| Stage | Title | Label |
| --- | --- | --- |
| 00 | Cold start | Storyboard |
| 01 | Your hardware, the Azure control plane | Proven |
| 02 | A machine built for one purpose | Storyboard |
| 03 | Software becomes a shippable unit | Storyboard |
| 04 | Declare the outcome, not the steps | Proven |
| 05 | Capacity follows demand | Proven |
| 06 | It repairs itself | Proven |
| 07 | Infrastructure as reviewable code | Proven |
| 08 | One system, end to end | Storyboard |

Each stage carries an executive line in the workspace and a `What this proves` plus `Boundary` pair in the
evidence panel. That structure is deliberate: it is what keeps the presentation credible with a technical
audience while staying legible to an executive one.

## What this prototype is not

- It does not connect to the cluster, Azure, or GitHub.
- It does not read live state. The existing dashboard already does that separately.
- It is not the final application. It is the storyboard the final application is built against.

## Related

- [Vision design questions](../vision-design-questions.md)
- [Product architecture](../product-architecture.md)
- [Command Center design direction](../../out/_preorg-snapshot-20260826-131032/docs/planning/capstone-command-center-design.md)
