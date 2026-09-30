/*
 * Optional "director's cut" intro for the capstone vision prototype.
 *
 * This is the part of the story the main storyboard skips: what it took to get four
 * machines into a state that met the requirements. It is opt-in, it never runs unless the operator
 * asks for it, and it hands control back to app.js when it finishes or when it is skipped.
 *
 * Tone note. The vibe is an old instructional cartoon. A calm narrator reads the official
 * requirement, the hardware tries to comply, and the caveats pile up faster than they clear. The
 * comedy is in the accumulation, so caveat cards stay on screen until a trial resolves.
 *
 * Every number and quoted requirement here came from the real build. The step list is the one
 * honest exception: the deployment ran 54 steps and only some of their names are recorded, so the
 * unnamed ones render as redacted bars rather than invented text.
 */

const INTRO = (function () {
  'use strict';

  const NODES = ['01', '02', '03', '04', '05', '06'];

  // Short ids drive the logic. The rack shows what the machines are actually called.
  const NODE_NAME = (n) => 'AZL-NODE-' + n;

  let dom = null;
  let timers = [];
  let clockId = null;
  let onDone = null;
  let running = false;
  let held = false;
  let heldAt = 0;
  let heldTotal = 0;
  let actLabel = '';

  /* ---------- plumbing ---------- */

  // Both decks load this file from different depths, so a relative path in a plate() call would
  // resolve against whichever document included it. Anchor to this script instead.
  const MEDIA = new URL('../media/',
    (document.currentScript && document.currentScript.src) || window.location.href).href;

  // One dial for the whole intro. Every cue and every act length runs through it.
  let PACE = 1.55;

  // The intro stops itself at every trial boundary so the presenter can talk into the gap. Turn
  // it off with T for an unattended run through.
  let stopAtTrials = true;
  let curAct = 0;
  let actPace = 1;        // per trial multiplier, applied on top of PACE
  let gateAt = -1;        // trial the gate is holding for, -1 when nothing is held
  let curtain = false;    // true while the fade between trials is running
  let actEndsAt = 0;      // when the current trial runs out of cues, in performance.now() terms

  const FADE = 520;       // matches .intro-stage opacity transition
  const KEEP_TAIL = 3200; // narration this close to a trial's end stays up for the gate

  // Spelled out, and never counted against a total. Nobody knew how many of these there would be
  // until they stopped happening, so nothing in the intro is allowed to imply a finite set.
  const ORDINAL = ['First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth',
    'Ninth', 'Tenth', 'Eleventh', 'Twelfth'];

  function trialName(i) {
    return 'The ' + (ORDINAL[i] || String(i + 1) + 'th') + ' Trial';
  }

  // Each cue records when it is due, so the whole timeline can be frozen and released rather
  // than only run at a fixed rate.
  function schedule(ms, fn) {
    const delay = Math.round(ms * PACE);
    const rec = { fn: fn, left: delay, fire: performance.now() + delay, id: 0, spent: false };
    rec.id = window.setTimeout(() => { rec.spent = true; fn(); }, delay);
    timers.push(rec);
  }

  // Trial bodies schedule through here so a trial can run at its own rate. Sequencing uses
  // schedule directly, because act boundaries must not move with the trial they open.
  function at(ms, fn) {
    schedule(ms * actPace, fn);
  }

  function clearAll() {
    timers.forEach((t) => window.clearTimeout(t.id));
    timers = [];
    if (clockId) window.cancelAnimationFrame(clockId);
    clockId = null;
  }

  /* ---------- the presenter owns the pace ---------- */

  // Space freezes every pending cue where it stands, so a beat can be talked over for as long as
  // it deserves and then released. Nothing is rescheduled relative to the clock, only to the
  // moment of release, which is what keeps the couplet rhythm intact across a hold.
  function freeze() {
    const now = performance.now();
    held = true;
    heldAt = now;
    timers.forEach((t) => {
      if (t.spent) return;
      t.left = Math.max(0, t.fire - now);
      window.clearTimeout(t.id);
    });
  }

  function thaw() {
    held = false;
    const paused = performance.now() - heldAt;
    heldTotal += paused;
    // The trial's end time is wall clock, so a hold has to push it along with everything else.
    if (actEndsAt) actEndsAt += paused;
    timers.forEach((t) => {
      if (t.spent) return;
      t.fire = performance.now() + t.left;
      t.id = window.setTimeout(() => { t.spent = true; t.fn(); }, t.left);
    });
  }

  // The trial label owns a fixed slot and never changes length. Everything transient goes to the
  // pause lamp or to the prompt line, both of which sit outside the track's layout.
  function paused(on) {
    if (dom.state) dom.state.classList.toggle('on', !!on);
  }

  function prompt(text) {
    if (!dom.prompt) return;
    dom.prompt.textContent = text || '';
    dom.prompt.classList.toggle('on', !!text);
  }

  function toggleHold() {
    if (!running) return;
    if (!held) { freeze(); } else { thaw(); }
    paused(held);
  }

  // Fires immediately before a trial's own cue, so freezing here catches that cue too and the
  // trial opens on release rather than playing into an empty room.
  //
  // The label holds the trial that just ended and nothing else. It used to carry the cautionary
  // line as well, which overran the track and truncated. The prompt names the next trial, which
  // makes the same point without asserting a count nobody knew.
  function trialGate(idx) {
    if (!stopAtTrials || held) return;
    freeze();
    gateAt = idx;
    paused(true);
    dom.act.textContent = trialName(idx - 1);
    prompt('Space for ' + ACTS[idx].name);
  }

  // Release from a gate drops the curtain first. Whatever the trial left on screen holds through
  // the talking, goes to black, and the next trial opens on a clean field.
  function releaseGate() {
    if (curtain) return;
    curtain = true;
    gateAt = -1;
    paused(false);
    prompt('');
    dom.stage.classList.add('blackout');
    window.setTimeout(() => {
      if (!running) { curtain = false; return; }
      thaw();
      window.requestAnimationFrame(() => {
        dom.stage.classList.remove('blackout');
        curtain = false;
      });
    }, FADE);
  }

  function setPace(v) {
    PACE = Math.min(3, Math.max(0.6, Math.round(v * 100) / 100));
    // Cue delays are baked in at schedule time, so replay the current trial under the new pace
    // rather than leaving half of it running at the old one.
    seek(curAct);
    flash('pace ' + PACE.toFixed(2));
  }

  // A prompt that clears itself, for settings changes nobody needs left on screen.
  let flashId = 0;
  function flash(text) {
    prompt(text);
    window.clearTimeout(flashId);
    flashId = window.setTimeout(() => { if (gateAt < 0) prompt(''); }, 1400);
  }

  // Guarded on running so it cannot fight the deck's own keys once the intro is gone.
  document.addEventListener('keydown', (e) => {
    if (!running || curtain) return;
    const advance = e.code === 'Space' || e.key === 'Enter' || e.key === 'ArrowRight';
    if (advance && gateAt >= 0) { e.preventDefault(); releaseGate(); return; }
    if (e.code === 'Space') { e.preventDefault(); toggleHold(); return; }
    if (held && (e.key === 'Enter' || e.key === 'ArrowRight')) { e.preventDefault(); toggleHold(); return; }
    if (e.key === 't' || e.key === 'T') {
      stopAtTrials = !stopAtTrials;
      flash('trial stops ' + (stopAtTrials ? 'on' : 'off'));
      return;
    }
    if (e.key === '[') { e.preventDefault(); setPace(PACE - 0.1); return; }
    if (e.key === ']') { e.preventDefault(); setPace(PACE + 0.1); }
  });

  function mk(cls, html) {
    const node = document.createElement('div');
    node.className = cls;
    if (html) node.innerHTML = html;
    return node;
  }

  function field() {
    return dom.field;
  }

  function clearField() {
    dom.field.innerHTML = '';
    dom.banners.innerHTML = '';
    sayReset();
  }

  /* ---------- narration ---------- */

  /*
   * Narration runs as couplets rather than one line replacing another. Two lines stream in and
   * sit together long enough for a slow reader, then leave in the order they arrived, oldest
   * first. A short gap of nothing, then the next pair starts on a clean line.
   *
   * Entry is driven by the act cues and exit by a timer, which is what keeps the gap from
   * depending on how far apart the next two cues happen to be.
   */
  const TOP_OUT = 1400;  // after the second line lands, the first starts leaving
  const BOT_OUT = 2300;  // and the second follows it
  const PAIR = 1700;     // second line of a couplet follows the first
  const CYCLE = 5000;    // and the next couplet follows the first line of this one
  const OPEN = 2400;     // narration waits for the act slate to clear

  let capLines = [];

  function sayReset() {
    capLines = [];
    if (dom && dom.cap) dom.cap.innerHTML = '';
  }

  function say(text, tone) {
    // A third line means the pair overstayed, so clear whatever is left without ceremony.
    if (capLines.length >= 2) {
      capLines.forEach((n) => n.remove());
      capLines = [];
    }

    // Tone is accepted so the script can still mark its turns, but it never reaches the DOM.
    // Narration is one colour, because text changing colour mid sequence reads as a fault.
    const line = mk('intro-cap-text icap-r' + (capLines.length + 1));
    line.textContent = text;
    dom.cap.appendChild(line);
    capLines.push(line);
    void line.offsetHeight;
    line.classList.add('icap-in');

    if (capLines.length === 2) {
      const pair2 = capLines;
      // A couplet landing at the end of a trial stays put, so the gate has something to hold on
      // screen while the presenter talks. The next trial's clearField takes it away.
      if (actEndsAt && performance.now() + BOT_OUT * PACE > actEndsAt - KEEP_TAIL) return;
      at(TOP_OUT, () => pair2[0].classList.add('icap-out'));
      at(BOT_OUT, () => pair2[1].classList.add('icap-out'));
      at(BOT_OUT + 420, () => {
        pair2.forEach((n) => n.remove());
        if (capLines === pair2) capLines = [];
      });
    }
  }

  // Tone belongs to the couplet, not the line. Two colours on screen at once reads as a fault
  // rather than as a turn.
  function pair(t, a, b, tone) {
    at(t, () => say(a, tone));
    if (b) at(t + PAIR, () => say(b, tone));
  }

  function slate(kicker, title) {
    dom.slate.innerHTML =
      '<p class="intro-slate-kick"></p><h2 class="intro-slate-title"></h2>';
    dom.slate.querySelector('.intro-slate-kick').textContent = kicker;
    dom.slate.querySelector('.intro-slate-title').textContent = title;
    dom.slate.classList.add('on');
    at(1900, () => dom.slate.classList.remove('on'));
  }

  /* ---------- set pieces ---------- */

  function rack(list) {
    const existing = dom.field.querySelector('.irack');
    if (existing) existing.remove();
    const wrap = mk('irack');
    const all = list || NODES;
    // Two interlocking rows rather than one line, which is how they actually sit in the rack.
    const split = Math.ceil(all.length / 2);
    const rows = [mk('irack-row'), mk('irack-row offset')];
    wrap.appendChild(rows[0]);
    wrap.appendChild(rows[1]);
    all.forEach((n, i) => {
      const box = mk('iserver');
      box.dataset.node = n;
      box.style.setProperty('--i', String(i));
      box.innerHTML =
        '<div class="iserver-face">' +
        '<span class="iserver-led"></span>' +
        '<span class="iserver-bays"><i></i><i></i><i></i><i></i></span>' +
        '</div>' +
        '<span class="iserver-name">' + NODE_NAME(n) + '</span>';
      rows[i < split ? 0 : 1].appendChild(box);
    });
    field().appendChild(wrap);
    window.requestAnimationFrame(() => {
      wrap.querySelectorAll('.iserver').forEach((b) => b.classList.add('in'));
    });
    return wrap;
  }

  function node(n) {
    return dom.field.querySelector('.iserver[data-node="' + n + '"]');
  }

  function banner(text, source) {
    const b = mk('ibanner');
    b.innerHTML = '<p class="ibanner-text"></p><p class="ibanner-src"></p>';
    b.querySelector('.ibanner-text').textContent = text;
    b.querySelector('.ibanner-src').textContent = source || 'requirement';
    dom.banners.appendChild(b);
    window.requestAnimationFrame(() => b.classList.add('on'));
    return b;
  }

  // Node stamps sit on their own node. Stamps thrown at the field share one spot, so they get
  // stacked rather than landing on top of each other.
  let fieldStamps = 0;
  function stamp(target, text, tone) {
    const s = mk('istamp' + (tone ? ' istamp-' + tone : ''));
    s.textContent = text;
    s.style.setProperty('--rot', (Math.random() * 16 - 8).toFixed(1) + 'deg');
    const host = target || field();
    if (host === dom.field) {
      s.style.setProperty('--sy', (fieldStamps * 62) + 'px');
      fieldStamps += 1;
    }
    host.appendChild(s);
    window.requestAnimationFrame(() => s.classList.add('on'));
    return s;
  }

  // A stamp with nothing under it is just floating text. Put it on the thing it is judging, and
  // fall back to the field only if that diagram is not on screen yet.
  function stampOn(sel, text, tone) {
    const host = field().querySelector(sel);
    const s = stamp(host || field(), text, tone);
    if (host) s.classList.add('istamp-over');
    return s;
  }

  // Caveat cards deliberately accumulate. The clutter is the point.
  let cardSlot = 0;
  function card(text) {
    const c = mk('icard');
    c.textContent = text;
    const lane = cardSlot % 6;
    c.style.setProperty('--x', (6 + lane * 15.6) + '%');
    c.style.setProperty('--y', (55 + (cardSlot % 3) * 9) + '%');
    c.style.setProperty('--rot', (Math.random() * 10 - 5).toFixed(1) + 'deg');
    cardSlot += 1;
    field().appendChild(c);
    window.requestAnimationFrame(() => c.classList.add('on'));
    return c;
  }

  // The inverse of the celebration later in the deck. Same energy, wrong direction.
  function slam(text) {
    const c = card(text);
    c.classList.add('islam');
    window.setTimeout(() => c.classList.add('hit'), 60);
    return c;
  }

  // A photograph in the same hairline frame the deck uses for evidence. If the file is not there
  // the frame and caption still stand, so a missing image cannot collapse the beat around it.
  function plate(src, cap, slot) {
    const p = mk('iplate');
    p.style.setProperty('--n', String(slot || 0));
    p.innerHTML = '<span class="iplate-shot"><img alt=""></span><span class="iplate-cap"></span>';
    p.querySelector('.iplate-cap').textContent = cap;
    const img = p.querySelector('img');
    img.onerror = () => p.classList.add('pending');
    img.src = src;
    field().appendChild(p);
    void p.offsetHeight;
    p.classList.add('on');
    return p;
  }

  function sweepCards() {
    cardSlot = 0;
    fieldStamps = 0;
    field().querySelectorAll('.icard, .istamp').forEach((n, i) => {
      window.setTimeout(() => n.classList.add('off'), i * 40);
    });
  }

  /* ---------- act one: the requirements ---------- */

  function actRequirements() {
    clearField();
    slate('The First Trial', '');

    at(1400, () => rack(NODES));

    pair(OPEN,
      'This project started as an exploration of what Azure Local has to offer.',
      'The resources available were the medium to build out a cluster.');

    pair(OPEN + CYCLE,
      'Dell Precision 7960 Rack. Workstations really, enterprise oriented but not servers.',
      'And certainly not on the Azure Local catalog.');

    at(OPEN + CYCLE * 2, () => say('The list of requirements is short, and completely reasonable.'));

    const b = OPEN + CYCLE * 2;
    at(b, () => banner('Secure Boot must be present and turned on.', 'system requirements'));
    at(b + 800, () => banner('TPM version 2.0 must be present and turned on.', 'system requirements'));
    at(b + 1600, () => banner('At least two SSD class drives per machine, 500 GB or larger.', 'system requirements'));
    at(b + 2400, () => banner('32 GB of memory, minimum.', 'system requirements'));
    at(b + 3200, () => banner('Network adapters must run signed manufacturer drivers.', 'host network requirements'));

    pair(OPEN + CYCLE * 3,
      'But after the hardware was configured and made accessible,',
      'cracks started to appear...', 'turn');
    at(OPEN + CYCLE * 3 + 600, () => {
      NODES.forEach((n, i) => {
        window.setTimeout(() => node(n).classList.add('bad'), i * 120);
      });
    });

    at(OPEN + CYCLE * 4, () => say('Zero storage drives to be found?', 'turn'));
    at(OPEN + CYCLE * 4 + 400, () => stampOn('.irack', '0 poolable drives', 'red'));

    // Lands late enough that the tail guard keeps it up, so the trial gate holds on this line.
    at(OPEN + CYCLE * 5 + 1500, () => say('Not one requirement truly qualified on the first day.', 'turn'));
  }

  /* ---------- act two: which secure boot ---------- */

  function actSecureBoot() {
    clearField();
    slate('The Second Trial', 'Getting the hardware to agree with itself');
    rack(NODES);
    at(200, () => NODES.forEach((n) => node(n).classList.add('bad')));
    // The requirement is the thing under examination all trial, so it is up from the first frame.
    at(300, () => banner('Secure Boot must be present and turned on.', 'the requirement, in full'));

    pair(OPEN,
      'Six machines, same model and form factor. We treated them as identical.',
      'Two of them installed. The other four stopped at a black screen.', 'turn');
    at(OPEN + PAIR + 500, () => stampOn('.irack', '0xc0430001 error.', 'red'));

    pair(OPEN + CYCLE,
      'Their firmware had been altered but there was nothing indicating that.',
      'One of those changes dropped the certificate that signs the boot loader.', 'turn');
    at(OPEN + CYCLE + PAIR + 700, () => card('UEFI0073. Unable to boot because of the Secure Boot policy.'));

    at(OPEN + CYCLE * 2 - 700, () => sweepCards());
    pair(OPEN + CYCLE * 2,
      'Restore factory keys, standard policy, trust firmware and OS.',
      'Now the four carried what the working two carried.', 'good');
    at(OPEN + CYCLE * 2 + PAIR + 600, () => card('Certificate scope back to Device Firmware and OS, not firmware alone.'));

    at(OPEN + CYCLE * 3 - 700, () => sweepCards());
    pair(OPEN + CYCLE * 3,
      'But the OS on the disk was sealed for Secure Boot being off.',
      'Turning it on gave back the same error it gave before.', 'turn');

    pair(OPEN + CYCLE * 4,
      'Nothing here was certified, so we assumed the stricter mode was required.',
      'It is not. We used the looser one and the check passed.', 'turn');
    at(OPEN + CYCLE * 4 + PAIR + 600, () => card('The check asks one question. Is Secure Boot enabled.'));

    at(OPEN + CYCLE * 5, () => say('So all six were rebuilt from bare metal, with Secure Boot already on.', 'good'));
    at(OPEN + CYCLE * 5 + 900, () => {
      NODES.forEach((n) => node(n).classList.remove('bad'));
    });
  }

  /* ---------- act three: the trap ---------- */

  function actTrap() {
    clearField();
    slate('The Third Trial', 'The most dangerous button on the screen');

    at(1600, () => {
      const m = mk('imenu');
      m.innerHTML =
        '<div class="imenu-head">Server Configuration</div>' +
        '<div class="imenu-row"><span>1)</span> Domain/Workgroup</div>' +
        '<div class="imenu-row"><span>2)</span> Computer Name</div>' +
        '<div class="imenu-row"><span>3)</span> Add Local Administrator</div>' +
        '<div class="imenu-row"><span>4)</span> Configure Remote Management</div>' +
        '<div class="imenu-row"><span>5)</span> Windows Update Settings</div>' +
        '<div class="imenu-row imenu-hot"><span>6)</span> Download and Install Updates</div>' +
        '<div class="imenu-row"><span>8)</span> Network Settings</div>';
      field().appendChild(m);
      window.requestAnimationFrame(() => m.classList.add('on'));
    });

    pair(OPEN,
      'The machines were imaged. Same media, every node.',
      'The systems start up to the Server Core wizard.');

    pair(OPEN + CYCLE,
      'Name the machine. Set the address. Turn on remote management.',
      'And the next selection installs security updates.', 'turn');

    at(OPEN + CYCLE * 2 - 400, () => {
      const m = field().querySelector('.imenu');
      if (m) m.classList.add('armed');
    });
    pair(OPEN + CYCLE * 2,
      'It seems like the responsible thing to do.',
      'But that pick stops you from building the cluster.', 'turn');
    at(OPEN + CYCLE * 2 + PAIR, () => stampOn('.imenu', 'Recipe mismatch', 'red'));

    at(OPEN + CYCLE * 3 - 900, () => card('The image is signed against a recipe that pins exact updates.'));
    at(OPEN + CYCLE * 3 + 400, () => card('Any updates and the check no longer matches.'));
    at(OPEN + CYCLE * 3 + PAIR, () => card('AzStackHci_OSImageRecipeValidation_LCU. Arc bootstrap refuses the node.'));

    pair(OPEN + CYCLE * 3,
      'Some nodes had already done it to themselves, overnight, unattended.',
      'While a warning exists. It is buried in a place you search for.');

    at(OPEN + CYCLE * 4 - 600, () => sweepCards());
    pair(OPEN + CYCLE * 4,
      'Nothing at this point tells you not to update.',
      'The solution, complete re-image. Do not run security updates.', 'turn');

    at(OPEN + CYCLE * 5 - 400, () => {
      const m = field().querySelector('.imenu');
      if (m) m.classList.add('off');
    });
    at(OPEN + CYCLE * 5, () => say('Let the platform handle it with onboarding, to keep validation.', 'good'));
  }

  /* ---------- act five: drives ---------- */

  function actDrives() {
    clearField();
    slate('The Fourth Trial', 'Dell Precision versus accuracy');

    at(1400, () => rack(NODES).classList.add('irack-tuck'));
    at(1600, () => NODES.forEach((n) => node(n).classList.add('bad')));

    at(OPEN + 200, () => {
      const c = mk('ipart ipart-card ipart-solution');
      c.innerHTML = '<span class="ipart-kick">Solution?</span>' +
        '<span class="ipart-name">Quad NVMe carrier</span>' +
        '<span class="ipart-sub">x16, four drives</span>';
      field().appendChild(c);
      window.requestAnimationFrame(() => c.classList.add('on'));
    });

    pair(OPEN,
      'The storage problem had a prudent answer. Buy a carrier card.',
      'Dell makes the official one for this chassis. The DPWC400.');

    // The carrier card beat runs long on purpose. It is the one place a photograph explains
    // something a sentence cannot, so everything after it is pushed back to make room.
    const HOLD = CYCLE * 4;
    const lid = OPEN + CYCLE;
    const fail = lid + CYCLE;

    pair(lid,
      'We passed on it. The cost, and how long it would take to arrive.',
      'Six ASUS PCIe 4x M.2 cards instead.');

    // Text, then a photograph, then text, then the second photograph. The images are not a
    // substitute for the lines, so line A holds alone while the first plate is looked at.
    at(fail, () => say('The cooler stands half an inch past its own bracket.', 'turn'));
    at(fail + 1400, () => stamp(field(), 'Lid will not close', 'red').classList.add('istamp-big'));
    at(fail + 3400, () => plate(MEDIA + '04-dell-dpwc400-front.png',
      'Dell DPWC400. The part we passed on.', 0));
    at(fail + 5200, () => say('Dell\'s own card does exactly the same thing.', 'turn'));
    at(fail + 8000, () => plate(MEDIA + '04-dell-dpwc400-back-overhang.png',
      'The cooler stands past its own bracket.', 1));
    at(fail + 17500, () => {
      field().querySelectorAll('.iplate').forEach((p) => p.classList.add('off'));
      const c = field().querySelector('.ipart-card');
      if (c) c.classList.add('eject');
    });

    at(OPEN + CYCLE * 2 + HOLD - 700, () => sweepCards());
    at(OPEN + CYCLE * 2 + HOLD + 300, () => {
      const c = mk('ipart ipart-card ipart-good');
      c.innerHTML = '<span class="ipart-name">Generic quad carrier</span><span class="ipart-sub">within spec</span>';
      field().appendChild(c);
      window.requestAnimationFrame(() => c.classList.add('on'));
    });
    pair(OPEN + CYCLE * 2 + HOLD,
      'A generic card keeps everything inside the bracket.',
      'Then the slot is bifurcated. x4 x4 x4 x4, one per drive.', 'good');

    pair(OPEN + CYCLE * 3 + HOLD,
      'Three data drives per node, matched on every node.',
      'A mixed count blocks the node from ever joining.');

    at(OPEN + CYCLE * 4 + HOLD - 700, () => sweepCards());
    pair(OPEN + CYCLE * 4 + HOLD,
      'Node 05 came up with one drive, and an older part.',
      'Node 03 would not hold a session long enough to validate.', 'turn');
    at(OPEN + CYCLE * 4 + HOLD + 400, () => {
      const n5 = node('05');
      if (n5) { n5.classList.add('bad'); stamp(n5, '1 data drive', 'red'); }
    });
    at(OPEN + CYCLE * 4 + HOLD + PAIR + 400, () => {
      const n3 = node('03');
      if (n3) { n3.classList.add('bad'); stamp(n3, 'unstable', 'red'); }
    });

    at(OPEN + CYCLE * 5 + HOLD - 800, () => {
      sweepCards();
      ['03', '05'].forEach((n) => {
        const el = node(n);
        if (el) el.classList.add('dark');
      });
      ['01', '02', '04', '06'].forEach((n, i) => {
        window.setTimeout(() => {
          const el = node(n);
          if (el) { el.classList.remove('bad'); el.classList.add('good'); }
        }, i * 160);
      });
    });

    pair(OPEN + CYCLE * 5 + HOLD,
      'Two out of contention. Four still standing.',
      'Which is the number we had committed to anyway.', 'good');
    at(OPEN + CYCLE * 5 + HOLD + PAIR, () => stampOn('.irack', '4 of 6 usable', 'green'));
    at(OPEN + CYCLE * 5 + HOLD + PAIR + 900, () => {
      dom.banners.innerHTML = '';
      banner('Four nodes. Three-way mirror, plus one node you can afford to lose.', 'proof of concept scope');
    });
  }

  /* ---------- act six: drivers ---------- */

  function actDrivers() {
    clearField();
    slate('The Fifth Trial', 'Drivers and hardware never meant for this');

    at(1400, () => {
      const wrap = rack(NODES);
      wrap.classList.add('irack-small');
      ['01', '02', '04', '06'].forEach((n) => {
        const el = node(n);
        if (el) el.classList.add('good');
      });
      ['03', '05'].forEach((n) => {
        const el = node(n);
        if (el) el.classList.add('dark');
      });
    });

    pair(OPEN,
      'Validation found the network cards did not match each other.',
      'One adapter on node 02 was a different subsystem ID.', 'turn');
    at(OPEN + 500, () => {
      const n2 = node('02');
      if (n2) { n2.classList.remove('good'); n2.classList.add('bad'); stamp(n2, 'Not matched', 'red'); }
    });
    at(OPEN + PAIR + 700, () => card('Driver version, component ID, description. None of them line up.'));

    pair(OPEN + CYCLE,
      'Node 05 was already out of contention. So node 05 became the parts bin.',
      'We pulled its adapter, put it in node 02, and benched node 05 permanently.');
    at(OPEN + CYCLE + 400, () => {
      const n5 = node('05');
      if (n5) { n5.classList.remove('dark'); n5.classList.add('donor'); }
    });
    at(OPEN + CYCLE + PAIR + 600, () => {
      const n5 = node('05');
      if (n5) n5.classList.add('dark');
      const n2 = node('02');
      if (n2) { n2.classList.remove('bad'); n2.classList.add('good'); }
    });

    at(OPEN + CYCLE * 2 - 700, () => sweepCards());
    pair(OPEN + CYCLE * 2,
      'And then there is the drivers.',
      'Every adapter was on a stock Microsoft driver, which Azure Local refuses.', 'turn');
    at(OPEN + CYCLE * 2 + PAIR + 800, () => card('The management NIC was running a generic driver from 2007.'));

    pair(OPEN + CYCLE * 3,
      'Hardware validation had already passed every machine.',
      'That check never looks at who wrote the driver.', 'turn');
    at(OPEN + CYCLE * 3 + PAIR + 700, () => card('Green on the validator. The documentation said otherwise.'));

    at(OPEN + CYCLE * 4, () => say('Storage had a pre-flight gate, but networking did not.'));

    pair(OPEN + CYCLE * 5,
      'The storage cards were easily matched to a Server driver package.',
      'The management NIC is a workstation part. Nobody ships one for Server.', 'turn');

    pair(OPEN + CYCLE * 6,
      'So you find the same silicon in an enterprise SKU, a PowerEdge, and pull that archive apart.',
      'Then you convince the installer it is landing on Windows Server 2022.');

    at(OPEN + CYCLE * 7 - 700, () => sweepCards());
    at(OPEN + CYCLE * 7, () => say('Generic hardware, fine. Generic driver? DENIED!', 'turn'));
    at(OPEN + CYCLE * 7 + 900, () => card('Dell does not certify this chassis for Windows Server, let alone for Azure Local.'));

    at(OPEN + CYCLE * 8 - 700, () => sweepCards());
    at(OPEN + CYCLE * 8, () => say('After days of tinkering, 25 hardware checks behind us.', 'good'));
    at(OPEN + CYCLE * 8 + 700, () => stampOn('.irack', '0 critical', 'green'));
  }

  /* ---------- act four: the wire ---------- */

  function actNetwork() {
    clearField();
    slate('The Sixth Trial', 'The wire');

    at(1600, () => banner('Two isolated storage VLANs. No gateway. No routing.', 'network requirements'));
    at(2600, () => banner('RoCEv2 requires priority flow control on priority 3, no-drop.', 'network requirements'));
    at(3600, () => banner('Every host and every switch port must agree, exactly.', 'network requirements'));

    at(OPEN + PAIR - 400, () => {
      const g = mk('iwire');
      g.innerHTML =
        '<div class="iwire-sw" data-sw="SW1"><span>SW1</span><em>VLAN 711</em></div>' +
        '<div class="iwire-sw" data-sw="SW2"><span>SW2</span><em>VLAN 712</em></div>' +
        '<div class="iwire-nodes">' +
        ['01', '02', '04', '06'].map((n) =>
          '<span class="iwire-n"><b>' + n + '</b>' +
          '<i class="iwire-ports"><s>Port3</s><s>Port4</s></i></span>').join('') +
        '</div>';
      field().appendChild(g);
      window.requestAnimationFrame(() => g.classList.add('on'));
    });

    // Stamps in this act belong on the diagram they are judging. Thrown at the field they land in
    // the empty column between the banners and the diagram, stamping nothing.

    pair(OPEN,
      'The last requirement was a fabric unlike any network most people run.',
      'We built it exactly as documented. Zero of six connections.');
    at(OPEN + PAIR + 900, () => stampOn('.iwire', '0 / 6', 'red'));

    pair(OPEN + CYCLE,
      'Then came days of back and forth with the network team.',
      'Packet captures, frame by frame, at both ends of every link.', 'turn');
    at(OPEN + CYCLE + PAIR + 700, () => card('Nobody builds a network shaped like this. That part was expected.'));

    pair(OPEN + CYCLE * 2,
      'Their standard patterns came off, and untagged traffic passed.',
      'Which looked very much like the answer.', 'turn');
    at(OPEN + CYCLE * 2 + PAIR + 500, () => stampOn('.iwire', 'untagged: PASSES', 'green'));

    at(OPEN + CYCLE * 3 - 900, () => sweepCards());
    at(OPEN + CYCLE * 3 - 200, () => card('Lossless RDMA depends on priority flow control, carried in the 802.1p bits inside the tag.'));
    at(OPEN + CYCLE * 3 + PAIR, () => slam('A native VLAN strips the tag. The priority goes with it.'));
    pair(OPEN + CYCLE * 3,
      'It was the most dangerous result of the whole project.',
      'Every test passes. The fabric quietly stops being lossless.', 'turn');

    at(OPEN + CYCLE * 4 - 700, () => sweepCards());
    at(OPEN + CYCLE * 4 - 400, () => {
      const m = mk('imap');
      m.innerHTML =
        '<div class="imap-head"><span>node</span><span>Port3 &rarr; sw1 / 711</span><span>Port4 &rarr; sw2 / 712</span></div>' +
        '<div class="imap-row"><span>01</span><span>00-00-5E-00-53-06</span><span>00-00-5E-00-53-01</span></div>' +
        '<div class="imap-row odd"><span>02</span><span>00-00-5E-00-53-03</span><span>00-00-5E-00-53-04</span></div>' +
        '<div class="imap-row"><span>04</span><span>00-00-5E-00-53-07</span><span>00-00-5E-00-53-08</span></div>' +
        '<div class="imap-row"><span>06</span><span>00-00-5E-00-53-09</span><span>00-00-5E-00-53-0A</span></div>';
      field().appendChild(m);
      window.requestAnimationFrame(() => m.classList.add('on'));
    });
    pair(OPEN + CYCLE * 4,
      'So we read every port and device ID off both ends of every cable.',
      'Windows had enumerated the two ports in the opposite order.', 'turn');
    at(OPEN + CYCLE * 4 + PAIR + 300, () => {
      field().querySelectorAll('.iwire-n').forEach((n, i) => {
        if (i !== 1) window.setTimeout(() => n.classList.add('swapped'), i * 220);
      });
    });
    at(OPEN + CYCLE * 4 + PAIR + 1100, () => card('Three of the four nodes had Port3 and Port4 on the wrong switch.'));

    at(OPEN + CYCLE * 5 + 900, () => {
      const m = field().querySelector('.imap');
      if (m) m.classList.add('reveal');
    });
    pair(OPEN + CYCLE * 5,
      'Every test we ran was correct, and measuring the wrong wire.',
      'The cabling was right. The naming was wrong.', 'turn');
    at(OPEN + CYCLE * 5 + PAIR + 700, () => card('Node 02 was the exception. Its Port4 is the card we took from node 05.'));

    at(OPEN + CYCLE * 6 - 700, () => sweepCards());
    at(OPEN + CYCLE * 6 + 700, () => stampOn('.iwire', 'switchport mode trunk', 'amber'));
    at(OPEN + CYCLE * 6 + PAIR, () => {
      field().querySelectorAll('.iwire-n').forEach((n) => n.classList.add('ok'));
    });
    pair(OPEN + CYCLE * 6,
      'One rename, and one line of configuration the second switch never got.',
      'Both fabrics passed, tagged.', 'good');
  }

  /* ---------- close ---------- */

  function actClose() {
    clearField();
    dom.stage.classList.add('closing');

    pair(OPEN,
      'Some of it never got explained.',
      'Why two nodes booted when four would not. Why the firmware differed at all.', 'turn');

    pair(OPEN + CYCLE,
      'Nobody ever went back to find out.',
      'Some things you fight for weeks. Some things quietly let you through.');

    at(OPEN + CYCLE * 2 - 800, () => {
      const c = mk('iclose');
      c.innerHTML =
        '<p class="iclose-kick">The deployment itself</p>' +
        '<p class="iclose-big">2h 13m</p>' +
        '<p class="iclose-sub">54 of 54 steps. Not one of them failed.</p>';
      field().appendChild(c);
      window.requestAnimationFrame(() => c.classList.add('on'));
    });

    pair(OPEN + CYCLE * 2,
      'The deployment was never the hard part.',
      'Getting four machines to the starting line took much longer than anticipated.');

    at(OPEN + CYCLE * 3, () => say('Now the project can begin.', 'good'));
  }

  /* ---------- sequencing ---------- */

  const ACTS = [
    { name: 'Requirements',  run: actRequirements, dur: 34000 },
    { name: 'The rebuild',   run: actSecureBoot,   dur: 31500, pace: 1.1 },
    { name: 'The trap',      run: actTrap,         dur: 32500, pace: 1.1 },
    { name: 'Drives',        run: actDrives,       dur: 53000 },
    { name: 'Drivers',       run: actDrivers,   dur: 47000, pace: 1.05 },
    { name: 'The Wire',      run: actNetwork,   dur: 38000, pace: 1.1 },
    { name: 'Starting line', run: actClose,        dur: 21000 }
  ];

  // A trial's length on the timeline, including any rate of its own.
  function actLen(a) { return a.dur * (a.pace || 1); }

  const TOTAL = ACTS.reduce((sum, a) => sum + actLen(a), 0);

  // How much of the timeline is already behind us, and when that was true. Seeking moves both,
  // which is what lets the progress bar stay honest after a jump.
  let baseMs = 0;
  let clockAt = 0;

  // Rebuild the schedule from an act boundary rather than trying to fast forward. Every act clears
  // the field on entry anyway, so this also guarantees no leftovers from the act we skipped.
  function seek(from) {
    clearAll();
    clearField();
    held = false;
    heldTotal = 0;
    gateAt = -1;
    curtain = false;
    actEndsAt = 0;
    paused(false);
    prompt('');
    dom.stage.classList.remove('blackout');
    baseMs = ACTS.slice(0, from).reduce((s, a) => s + actLen(a), 0);
    clockAt = performance.now();

    let offset = 0;
    for (let i = from; i < ACTS.length; i++) {
      const act = ACTS[i];
      const idx = i;
      // Scheduled first at the same offset, so it fires first and freezes the trial cue behind it.
      if (i > from) schedule(offset, () => trialGate(idx));
      schedule(offset, () => {
        curAct = idx;
        actPace = act.pace || 1;
        actEndsAt = performance.now() + actLen(act) * PACE;
        actLabel = trialName(idx) + ' \u00b7 ' + act.name;
        dom.act.textContent = actLabel;
        markCurrent(idx);
        act.run();
      });
      offset += actLen(act);
    }
    schedule(offset, finish);
  }

  function buildMarks() {
    if (!dom.track || dom.track.dataset.built) return;
    let offset = 0;
    ACTS.forEach((act, i) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'intro-mark';
      b.style.left = ((offset / TOTAL) * 100).toFixed(3) + '%';
      b.title = trialName(i) + ', ' + act.name;
      b.setAttribute('aria-label', 'Jump to ' + trialName(i) + ', ' + act.name);
      b.onclick = () => seek(i);
      dom.track.appendChild(b);
      offset += actLen(act);
    });
    dom.track.dataset.built = '1';
  }

  function markCurrent(i) {
    if (!dom.track) return;
    Array.from(dom.track.querySelectorAll('.intro-mark')).forEach((m, j) => {
      m.classList.toggle('on', j === i);
      m.classList.toggle('done', j < i);
    });
  }

  function play(done) {
    if (running) return;
    dom = {
      root: document.getElementById('intro'),
      stage: document.getElementById('introStage'),
      field: document.getElementById('introField'),
      banners: document.getElementById('introBanners'),
      slate: document.getElementById('introSlate'),
      cap: document.getElementById('introCap'),
      act: document.getElementById('introAct'),
      state: document.getElementById('introState'),
      prompt: document.getElementById('introPrompt'),
      fill: document.getElementById('introFill'),
      track: document.getElementById('introTrack'),
      skip: document.getElementById('introSkip')
    };
    if (!dom.root) { done(); return; }

    running = true;
    onDone = done;
    cardSlot = 0;
    held = false;
    heldTotal = 0;
    dom.root.classList.add('on');
    dom.root.setAttribute('aria-hidden', 'false');
    dom.stage.classList.remove('closing');

    buildMarks();
    seek(0);

    const span = TOTAL * PACE;
    const tick = (now) => {
      if (!held) {
        const t = Math.min(1, (baseMs * PACE + (now - clockAt) - heldTotal) / span);
        dom.fill.style.width = (t * 100).toFixed(2) + '%';
      }
      if (running) window.requestAnimationFrame(tick);
    };
    window.requestAnimationFrame(tick);

    dom.skip.onclick = finish;
  }

  function finish() {
    if (!running) return;
    running = false;
    held = false;
    clearAll();
    dom.root.classList.remove('on');
    dom.root.setAttribute('aria-hidden', 'true');
    window.setTimeout(() => {
      clearField();
      dom.cap.textContent = '';
      if (onDone) onDone();
    }, 620);
  }

  function isRunning() {
    return running;
  }

  return { play, finish, isRunning, hold: toggleHold };
})();
