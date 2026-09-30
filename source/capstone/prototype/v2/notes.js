/*
 * Commentary layer.
 *
 * Floats above the mockup and owns no layout, so notes can be added, answered, or retired without
 * touching any layer underneath. Anchors to [data-note="id"] elements.
 *
 * Answers and statuses persist in localStorage, so this survives a reload but stays local to the
 * machine it was written on. Use Export to get the answers back out as text.
 *
 * kind: "q"        open question, needs an answer
 *       "decision" settled, recorded here so the reasoning stays attached to the pixels
 *       "risk"     known shortcut or hazard in this mockup
 */

const NOTES = [
  {
    id: 'copy-subs', anchor: 'n-copy', kind: 'copy', title: 'The movement subtitles are mine',
    body: 'Eleven subtitles, none of them specified by you. Five use an X not Y construction and several assert a thesis where a fact would do. "The fourth pathway is earned, not scheduled." "The contrast is the point, not either half alone." Say what the room should take from each movement and these get rewritten to that.',
    ref: 'mockup.js, sub'
  },
  {
    id: 'copy-captions', anchor: 'n-copy', kind: 'copy', title: 'The BUILT captions are mine',
    body: 'Eleven short lines under the button, written to a cadence rather than to a point. "degraded is not the same as down", "the floor moved, the workload did not". They read as slogans. If they should just name what the run proves, say so.',
    ref: 'mockup.js, builtSub'
  },
  {
    id: 'copy-explain', anchor: 'n-copy', kind: 'copy', title: 'Seventeen explain entries, never reviewed',
    body: 'Click any node and it answers with what it is, what it does, and what it is here. Written in one pass and never read back by you. The here field carries real names and numbers. The what and role fields are definitions I chose.',
    ref: 'explain.js'
  },
  {
    id: 'copy-runs', anchor: 'n-built', kind: 'copy', title: '141 narration lines under the commands',
    body: 'One sentence sits under each command in every cutaway, interpreting the output. The commands and the output are real. The interpretation is mine, and it decides what a result means before the room gets to.',
    ref: 'shared/runs.js'
  },
  {
    id: 'copy-next', anchor: 'n-built', kind: 'copy', title: 'The proposals on 10.5 are my judgement',
    body: 'Four cards on where this goes next and four security boundaries. Nobody agreed these. The lead card is disposable dev environments, which is a call about what the platform is for.',
    ref: 'built.js, NEXT_CARDS and NEXT_SIDE'
  },
  {
    id: 'copy-crit', anchor: 'n-crit', kind: 'copy', title: 'Nine criteria notes explain away the gaps',
    body: 'The notes on the bounded, deferred and finding items are my wording. They are the lines most likely to sound defensive, because each one explains why something is not a plain yes.',
    ref: 'criteria.js, n'
  },
  {
    id: 'mockup', anchor: 'n-mockup', kind: 'risk', title: 'What this mockup is not',
    body: 'Six movements that demonstrate the design rules, not the full narrative. Movements advance by hand so the layout can be inspected. The timing track and the interstitials are not implemented here.',
    ref: 'build after C4'
  },
  {
    id: 'kinds-stat', anchor: 'n-kinds', kind: 'decision', title: 'Kinds online, not link count',
    body: 'Edge count grows without bound and measures nothing. Distinct kinds present caps at five and tracks real system maturity, so this number cannot be inflated.',
    ref: 'agreed 2026-08-28'
  },
  {
    id: 'kinds-header', anchor: 'n-kinds', kind: 'q', title: 'Does this belong in the header at all?',
    body: 'It is honest, but it may be too abstract to read at a glance for a leadership audience, and the legend already implies the same thing with colour.',
    ref: 'open'
  },
  {
    id: 'movements', anchor: 'n-movements', kind: 'decision', title: 'Movements, not stages',
    body: 'Each connection kind is an instrument with a consistent voice. The arc runs unison to harmony: many voices on one line at the start, splitting into parts as the system earns them.',
    ref: 'agreed 2026-08-28'
  },
  {
    id: 'tiers', anchor: 'n-canvas', kind: 'decision', title: 'Three focus tiers, not two',
    body: 'Active edges full, same kind mid, other kinds dim. Two tiers would leave every edge bright in the opening, since almost everything there is networking, which is no focus at all.',
    ref: 'agreed 2026-08-28'
  },
  {
    id: 'ceremony', anchor: 'n-canvas', kind: 'risk', title: 'First of a kind needs ceremony',
    body: 'Concretely: when a pathway colour appears for the first time, that one path draws over about a second while everything else holds still, the legend entry lights on arrival, and the movement holds a beat before continuing. Every later path of that colour appears in a fraction of that time and is just texture. Five slow moments in the whole run, one per colour. Right now all paths grow identically, which is how nothing ends up feeling significant.',
    ref: 'to build'
  },
  {
    id: 'teams', anchor: 'n-canvas', kind: 'q', title: 'Does the layer stack survive Teams compression?',
    body: 'Rows of small boxes with thin curves between them is the part most likely to turn to mush over screen share. Confirming this changes line weights and type sizes everywhere, so it is worth doing once.',
    ref: 'E1'
  },
  {
    id: 'morph', anchor: 'n-fabric', kind: 'decision', title: 'The morph is the thesis',
    body: 'Four named machines becoming one pooled surface is exactly what the platform does. The demotion is spatial: they move to a margin rather than shrinking in place, which is what frees the middle.',
    ref: 'agreed 2026-08-28'
  },
  {
    id: 'flip', anchor: 'n-fabric', kind: 'risk', title: 'The transition is a cut, not a morph',
    body: 'This mockup swaps one element for another. The real thing needs the machines to visibly travel to the margin, otherwise the argument is lost in a blink.',
    ref: 'to build'
  },
  {
    id: 'resolve', anchor: 'n-fabric', kind: 'risk', title: 'Resolve on demand is not wired',
    body: 'On request means you click the strip and it expands back into the four named machines, then click again and it collapses. It is there for the question you will actually get in the room, which is where did the hardware go. It also happens by itself on failure, because that is the moment the individual machine matters again. Neither is wired here.',
    ref: 'to build'
  },
  {
    id: 'name', anchor: 'n-built', kind: 'q', title: 'What should this panel be called?',
    body: 'Transcript is precise if the commands are replayed, Terminal is only right if they run live, and Build log is true either way. Currently guessing Transcript.',
    ref: 'C5, depends on C4'
  },
  {
    id: 'liveness', anchor: 'n-built', kind: 'decision', title: 'Transcript, not a live shell',
    body: 'Settled. Raw console output is thousands of lines of nothing at a speed no one can read, which is bad presentation material. Captured lines replayed with their original timestamps reproduce the real cadence exactly, so nothing is lost by not being live. This is the same call as note 14.',
    ref: 'C4, agreed 2026-08-28'
  },
  {
    id: 'collapse', anchor: 'n-built', kind: 'decision', title: 'Collapsed by default, failure expands itself',
    body: 'The resting state is calm and expanding is a deliberate beat. Scarcity is what gives the reveal weight, because constant proof stops being looked at. Movement 00 shows the asymmetry.',
    ref: 'agreed 2026-08-28'
  },
  {
    id: 'live', anchor: 'n-liveness', kind: 'decision', title: 'Nothing runs live',
    body: 'Settled. No part of this touches the cluster during the talk. Everything shown is word for word what happened, replayed. That removes the failure risk entirely and costs nothing, because a recorded event and a live one look identical on screen. It also means the talk survives a dead network in the room.',
    ref: 'F2, agreed 2026-08-28'
  },
  {
    id: 'resync', anchor: 'n-liveness', kind: 'risk', title: 'The resync figure is not measured',
    body: 'Movement 05 says rejoin took about five minutes, which is recorded. Full resync to healthy is not captured precisely. If expected healing time becomes a spoken talking point it needs a real number.',
    ref: 'open item'
  },
  {
    id: 'deadline', anchor: 'n-liveness', kind: 'decision', title: 'Five days, so scope is the only real question',
    body: 'Answered: feature complete in about five days. Ignore the database, that was a stale idea from an earlier draft where answers were stored server side. Nothing here needs a backend, it is files on disk. Five days is enough to finish one complete thing and not enough to finish two, which is what notes 17 and 18 are about.',
    ref: 'F1, answered 2026-08-28'
  },
  {
    id: 'spine', anchor: 'n-mockup', kind: 'q', title: 'Which one is the spine, v1 or this?',
    body: 'You are right that this is a re-imagined slice rather than a replacement. v1 has the cold open, the director\'s cut, the growth track, the module frame and eight stages. This has the pathway language, the fabric demotion and better looking connections, but only three of those eight stages plus the heal. One of them has to become the spine and absorb the other. Merging both directions at once is the thing five days does not allow.',
    ref: 'blocks everything else'
  },
  {
    id: 'beats', anchor: 'n-movements', kind: 'q', title: 'Five beats from v1 have no home here',
    body: 'v1 ran boot, platform, appliance, image, kubernetes, scale, heal, terraform, recap. This covers boot, platform, kubernetes and heal. Missing entirely: the VM image appliance, the container image, scaling to three replicas as its own beat, terraform as reviewable code, and the closing recap. Each is real and proven. Which ones earn their place, and which get folded into a line of transcript.',
    ref: 'open'
  },
  {
    id: 'evidence', anchor: 'n-built', kind: 'risk', title: 'The evidence console is still not built',
    body: 'Your words: the synthetic console that shows the evidence with the real commands expandable underneath. What exists here is a static list that expands to a fixed block of text. What is missing is the replay, meaning lines arriving at their captured pace, a visible link between the claim on screen and the command that proves it, and output long enough to be credible without being unreadable. This is the single largest remaining build.',
    ref: 'to build, largest item'
  },
  {
    id: 'intro', anchor: 'n-movements', kind: 'q', title: 'Does the director\'s cut ship in front of this?',
    body: 'Two minutes twenty seven, already built, covering why nothing worked for so long. It is the best answer to the question of why this took the time it did, and it is also two and a half minutes before the first useful frame. In, out, or cut down to about forty seconds.',
    ref: 'open'
  },
  {
    id: 'climax', anchor: 'n-canvas', kind: 'q', title: 'The best real drama is buried',
    body: 'Zero of six storage connections on all four machines, both directions, both fabrics, caused by three of four machines having their ports crossed. That is the most dramatic true thing in this project and right now it is a collapsed line in movement 00 that nobody will open. Compare it against the heal, which is calmer but ends well. Only one of them can be the peak.',
    ref: 'open'
  },
  {
    id: 'ending', anchor: 'n-movements', kind: 'q', title: 'What is the last frame?',
    body: 'It currently ends on a degraded pool repairing itself, which is honest but leaves the room looking at a warning. The alternatives are the full stack lit and serving, a plain statement of what was and was not proven, or the application itself with nothing else on screen. Whatever is up when you stop talking is what people carry out.',
    ref: 'open'
  },
  {
    id: 'runlength', anchor: 'n-controls', kind: 'q', title: 'How long is the slot?',
    body: 'Not recorded anywhere. It sets everything: number of movements, whether the intro fits, how long a pathway may take to draw, how much transcript can be opened on screen. A twelve minute slot and a forty minute slot are different pieces of work.',
    ref: 'open'
  },
  {
    id: 'control', anchor: 'n-controls', kind: 'q', title: 'Who drives it?',
    body: 'Three different builds. Presenter clicks each movement and talks over it, which is the safest. It plays itself on a timer while you narrate, which looks best and forgives nothing. Or it runs unattended and has to explain itself with no voice at all. The last one needs captions the other two must not have.',
    ref: 'open'
  },
  {
    id: 'delivery', anchor: 'n-mockup', kind: 'risk', title: 'How does it actually reach the room?',
    body: 'This is files opened from disk with no build and no server, which is deliberate and makes it trivially portable. If it is shared over Teams then the compression question in note 7 decides the line weights. If it needs a link that other people can open later, that is hosting, and it is not currently anyone\'s job.',
    ref: 'open'
  }
];

(function () {
  'use strict';

  const KEY = 'capstone-v2-notes';
  const STATES = [
    { id: 'open', label: 'Open' },
    { id: 'considering', label: 'Considering' },
    { id: 'change', label: 'Change this' },
    { id: 'resolved', label: 'Resolved' }
  ];

  const layer = document.getElementById('notesLayer');
  const index = document.getElementById('notesIndex');
  const toggle = document.getElementById('notesToggle');
  const countEl = document.getElementById('notesCount');

  // Authoring tool, not a presenting one. Set false to get the commentary layer back.
  const PRESENTING = true;
  if (PRESENTING) { toggle.style.display = 'none'; return; }

  let store = load();
  let notes = NOTES.concat(store.custom || []);
  let on = false;
  let openId = null;
  let showResolved = false;
  let adding = false;
  let tucked = false;
  // Same overlay, two audiences. Design commentary now, presenter talking points closer to the day.
  let mode = store.mode || 'design';
  const views = [];

  function load() {
    let s;
    try { s = JSON.parse(localStorage.getItem(KEY)) || { state: {}, custom: [] }; }
    catch (e) { s = { state: {}, custom: [] }; }
    if (!s.state) s.state = {};

    // Anything untouched in this browser adopts the answer of record. Live edits are never lost,
    // because a note that has been given a status or an answer is left exactly as it is.
    const seed = window.NOTE_ANSWERS || {};
    Object.keys(seed).forEach((id) => {
      const cur = s.state[id];
      const untouched = !cur || (cur.status === 'open' && !(cur.answer || '').trim());
      if (untouched) s.state[id] = { status: seed[id].status, answer: seed[id].answer };
    });
    return s;
  }

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(store)); } catch (e) { /* private mode */ }
  }

  function st(id) {
    if (!store.state[id]) store.state[id] = { status: 'open', answer: '' };
    return store.state[id];
  }

  const kindClass = (k) => (k === 'q' ? 'q' : k === 'risk' ? 'risk' : k === 'copy' ? 'copy' : '');
  const kindLabel = (k) => (k === 'q' ? 'Open question' : k === 'risk' ? 'Risk or shortcut' : k === 'copy' ? 'Wording, mine not yours' : 'Decision');

  /* ---------- build ---------- */

  function build() {
    layer.innerHTML = '';
    views.length = 0;

    notes.forEach((note, i) => {
      const s = st(note.id);

      const pin = document.createElement('button');
      pin.className = 'pin ' + kindClass(note.kind);
      pin.type = 'button';
      pin.textContent = String(i + 1);

      const card = document.createElement('div');
      card.className = 'sticky ' + kindClass(note.kind);

      const answer = document.createElement('textarea');
      answer.className = 'sticky-answer';
      answer.placeholder = note.kind === 'q' ? 'Your answer'
        : note.kind === 'copy' ? 'What should this say, or what should it emphasise'
        : 'Your comment';
      answer.value = s.answer || '';
      answer.addEventListener('click', (e) => e.stopPropagation());
      answer.addEventListener('input', () => { s.answer = answer.value; save(); });

      const actions = document.createElement('div');
      actions.className = 'sticky-actions';
      STATES.forEach((opt) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'sticky-act' + (s.status === opt.id ? (opt.id === 'resolved' ? ' done' : ' on') : '');
        b.textContent = opt.label;
        b.addEventListener('click', (e) => {
          e.stopPropagation();
          s.status = opt.id;
          save();
          if (opt.id === 'resolved' && !showResolved) openId = null;
          build();
          paint();
          buildIndex();
        });
        actions.appendChild(b);
      });

      card.innerHTML =
        '<p class="sticky-kind"></p><p class="sticky-title"></p><p class="sticky-body"></p><p class="sticky-ref"></p>';
      card.querySelector('.sticky-kind').textContent = kindLabel(note.kind);
      card.querySelector('.sticky-title').textContent = note.title;
      card.querySelector('.sticky-body').textContent = note.body;
      card.querySelector('.sticky-ref').textContent = note.ref || '';
      card.appendChild(answer);
      card.appendChild(actions);
      card.addEventListener('click', (e) => e.stopPropagation());

      pin.addEventListener('click', (e) => {
        e.stopPropagation();
        openId = openId === note.id ? null : note.id;
        paint();
      });

      layer.appendChild(pin);
      layer.appendChild(card);
      views.push({ note, pin, card, i, s });
    });

    const outstanding = notes.filter((n) => st(n.id).status !== 'resolved').length;
    countEl.textContent = String(outstanding);
  }

  /* ---------- position ---------- */

  function inMode(note) {
    return (note.mode || 'design') === mode;
  }

  // A note is useless if its anchor is not on screen, so opening one walks the mockup to a
  // movement where the thing it annotates actually exists.
  function reveal(id) {
    const note = notes.find((n) => n.id === id);
    openId = id;
    if (!note) { paint(); return; }

    const visible = () => {
      const t = document.querySelector('[data-note="' + note.anchor + '"]');
      return t && t.offsetParent !== null;
    };

    if (!visible() && window.M) {
      const start = Number(document.getElementById('statStage').textContent) || 0;
      for (let i = 0; i < 12; i += 1) {
        M.go(i);
        if (visible()) break;
        if (i === 11) M.go(start);
      }
    }
    paint();
  }

  function place() {
    const seen = {};
    views.forEach((v) => {
      const hidden = (v.s.status === 'resolved' && !showResolved) || !inMode(v.note);
      const target = document.querySelector('[data-note="' + v.note.anchor + '"]');
      if (hidden || !target || target.offsetParent === null) {
        v.pin.style.display = 'none';
        v.card.style.display = 'none';
        return;
      }
      v.pin.style.display = '';
      const n = seen[v.note.anchor] || 0;
      seen[v.note.anchor] = n + 1;

      const r = window.FIT.rect(target);
      // Pins straddle the anchor's top-right corner and stack sideways, so they never bury
      // the thing they are annotating and never collide with a neighbouring anchor.
      const x = r.right - 3 - n * 21;
      const y = r.top + 1;
      v.pin.style.left = Math.max(12, x) + 'px';
      v.pin.style.top = Math.max(10, y) + 'px';

      const cardW = 272;
      const wantLeft = x - cardW - 10;
      v.card.style.left = Math.max(10, wantLeft < 10 ? x + 16 : wantLeft) + 'px';
      v.card.style.top = Math.max(56, Math.min(window.FIT.H - 330, y + 16)) + 'px';
    });
  }

  function paint() {
    place();
    views.forEach((v) => {
      const isOpen = on && openId === v.note.id;
      v.pin.classList.toggle('open', isOpen);
      v.pin.classList.toggle('answered', v.s.status === 'resolved');
      v.card.classList.toggle('on', isOpen);
      if (!on) { v.card.style.display = 'none'; }
      else if (v.pin.style.display !== 'none') { v.card.style.display = isOpen ? '' : 'none'; }
    });
  }

  /* ---------- index ---------- */

  function buildIndex() {
    const groups = [
      { s: 'change', label: 'Change this' },
      { s: 'considering', label: 'Considering' },
      { s: 'open', label: 'Not yet addressed' },
      { s: 'resolved', label: 'Resolved' }
    ];

    const anchors = Array.from(document.querySelectorAll('[data-note]'))
      .map((e) => e.dataset.note)
      .filter((v, i, a) => a.indexOf(v) === i);

    let html =
      '<button class="ni-tuck" id="niTuck">' + (tucked ? 'Show list' : 'Hide list') + '</button>' +
      '<div class="ni-inner">' +
      '<div class="ni-head"><h3 class="ni-title">Commentary</h3></div>' +
      '<p class="ni-sub">An overlay. It never changes the console underneath, so what you review is what the room will see.</p>' +
      '<div class="ni-tools">' +
      '<button class="ni-tool' + (mode === 'design' ? ' on' : '') + '" id="niDesign">Design</button>' +
      '<button class="ni-tool' + (mode === 'presenter' ? ' on' : '') + '" id="niPresenter">Presenter</button>' +
      '</div>' +
      '<div class="ni-tools">' +
      '<button class="ni-tool" id="niAdd">Add note</button>' +
      '<button class="ni-tool' + (showResolved ? ' on' : '') + '" id="niShow">' +
      (showResolved ? 'Hiding none' : 'Show resolved') + '</button>' +
      '<button class="ni-tool" id="niExport">Export</button>' +
      '</div>' +
      '<div class="ni-add' + (adding ? ' on' : '') + '" id="niForm">' +
      '<label>Attach to</label><select id="niAnchor">' +
      anchors.map((a) => '<option value="' + a + '">' + a + '</option>').join('') +
      '</select>' +
      '<label>Title</label><input id="niTitle" type="text" placeholder="Short label" />' +
      '<label>Note</label><textarea id="niBody" placeholder="' +
      (mode === 'presenter' ? 'What to say here' : 'What to consider changing') + '"></textarea>' +
      '<button class="ni-tool" id="niSave">Save note</button>' +
      '</div>';

    groups.forEach((g) => {
      if (g.s === 'resolved' && !showResolved) return;
      const items = views.filter((v) => v.s.status === g.s && inMode(v.note));
      if (!items.length) return;
      html += '<div class="ni-group"><h4>' + g.label + ' (' + items.length + ')</h4>';
      items.forEach((v) => {
        html += '<div class="ni-item ' + kindClass(v.note.kind) +
          (g.s === 'resolved' ? ' answered' : '') + '" data-id="' + v.note.id + '">' +
          '<span class="ni-n">' + (v.i + 1) + '</span><span>' + v.note.title + '</span></div>';
      });
      html += '</div>';
    });

    if (mode === 'presenter' && !views.some((v) => inMode(v.note))) {
      html += '<p class="ni-sub">No talking points yet. Add one and attach it to whatever you want to speak to.</p>';
    }

    html += '</div>';
    index.innerHTML = html;

    index.querySelector('#niTuck').addEventListener('click', (e) => {
      e.stopPropagation();
      tucked = !tucked;
      index.classList.toggle('tucked', tucked);
      buildIndex();
    });

    index.querySelector('#niDesign').addEventListener('click', () => {
      mode = 'design'; store.mode = mode; save(); buildIndex(); paint();
    });
    index.querySelector('#niPresenter').addEventListener('click', () => {
      mode = 'presenter'; store.mode = mode; save(); buildIndex(); paint();
    });

    index.querySelectorAll('.ni-item').forEach((it) => {
      it.addEventListener('click', (e) => { e.stopPropagation(); reveal(it.dataset.id); });
    });

    index.querySelector('#niAdd').addEventListener('click', () => { adding = !adding; buildIndex(); });
    index.querySelector('#niShow').addEventListener('click', () => { showResolved = !showResolved; buildIndex(); paint(); });
    index.querySelector('#niExport').addEventListener('click', exportNotes);
    index.querySelector('#niSave').addEventListener('click', () => {
      const title = index.querySelector('#niTitle').value.trim();
      if (!title) return;
      store.custom = store.custom || [];
      store.custom.push({
        id: 'u' + Date.now(),
        anchor: index.querySelector('#niAnchor').value,
        kind: mode === 'presenter' ? 'decision' : 'q',
        mode: mode,
        title: title,
        body: index.querySelector('#niBody').value.trim(),
        ref: mode === 'presenter' ? 'talking point' : 'yours'
      });
      save();
      notes = NOTES.concat(store.custom);
      adding = false;
      build();
      buildIndex();
      paint();
    });
  }

  function exportNotes() {
    const lines = notes.map((n, i) => {
      const s = st(n.id);
      return [
        '## ' + (i + 1) + '. ' + n.title,
        'kind: ' + kindLabel(n.kind) + '   status: ' + s.status + '   ref: ' + (n.ref || ''),
        n.body,
        s.answer ? 'ANSWER: ' + s.answer : 'ANSWER: (none)',
        ''
      ].join('\n');
    });
    const blob = new Blob([lines.join('\n')], { type: 'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'capstone-commentary.txt';
    a.click();
  }

  /* ---------- wiring ---------- */

  toggle.addEventListener('click', () => {
    on = !on;
    openId = null;
    toggle.classList.toggle('on', on);
    layer.classList.toggle('on', on);
    layer.setAttribute('aria-hidden', String(!on));
    index.classList.toggle('on', on);
    index.setAttribute('aria-hidden', String(!on));
    paint();
  });

  document.addEventListener('click', () => { if (openId !== null) { openId = null; paint(); } });
  index.addEventListener('click', (e) => e.stopPropagation());
  toggle.addEventListener('click', (e) => e.stopPropagation());

  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
    if (e.key.toLowerCase() === 'n') toggle.click();
    if (e.key === 'Escape' && openId !== null) { openId = null; paint(); }
  });

  window.addEventListener('resize', paint);
  // The mockup relayouts on movement change, so keep pins glued to their anchors.
  window.setInterval(() => { if (on) place(); }, 400);

  build();
  buildIndex();
  paint();
})();
