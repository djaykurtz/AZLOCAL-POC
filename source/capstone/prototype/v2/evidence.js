/*
 * The run panel for v2.
 *
 * The column beside the diagram already listed the commands behind each movement. This replays
 * them, so the room watches the system do the thing rather than reading that it once did.
 *
 * This is not a proof panel and it is not arguing with anyone. It is what was typed, what came
 * back, and how long it really took. Runs that failed are shown the same way as runs that worked,
 * because what was attempted is part of explaining how Azure Local behaves.
 *
 * Runs come from ../shared/runs.js and bind by stage index. Movements with no capture say so
 * rather than hiding the panel, since a column that appears and vanishes reads as a glitch.
 *
 * Playback is armed by boot.js after the gate lifts and the intro finishes. Before that the panel
 * stays primed but silent, because mockup.js renders underneath the intro and a terminal typing
 * behind a title sequence would be a bug the audience can see.
 */

const EVIDENCE = (function () {
  'use strict';

  const SPEED = 6;

  let dom = null;
  let timers = [];
  let run = null;
  let armed = false;

  function el(id) { return document.getElementById(id); }

  function ready() {
    if (dom) return true;
    if (!window.RUNS) return false;
    dom = {
      root: el('ev'),
      note: el('evNote'),
      dot: el('evDot'),
      host: el('evHost'),
      body: el('evBody'),
      foot: el('evFoot'),
      replay: el('evReplay')
    };
    if (!dom.root) { dom = null; return false; }
    dom.replay.addEventListener('click', () => play());
    return true;
  }

  function clear() {
    timers.forEach(window.clearTimeout);
    timers = [];
  }

  function stamp(ms) {
    const s = Math.floor(ms / 1000);
    return String(Math.floor(s / 60)).padStart(2, '0') + ':' +
      String(s % 60).padStart(2, '0') + '.' + String(Math.floor((ms % 1000) / 100));
  }

  // Mirrors the cutaway: a keyed line rewrites its own row rather than appending a duplicate.
  function row(cls, ms, text, key) {
    if (key) {
      const found = dom.body.querySelector('[data-key="' + key + '"]');
      if (found) {
        found.className = 'evrow ' + cls;
        found.querySelector('.evtxt').textContent = text;
        found.querySelector('.evts').textContent = stamp(ms);
        return;
      }
    }
    const r = document.createElement('div');
    r.className = 'evrow ' + cls;
    if (key) r.dataset.key = key;
    const t = document.createElement('span');
    t.className = 'evts';
    t.textContent = stamp(ms);
    const x = document.createElement('span');
    x.className = 'evtxt';
    x.textContent = text;
    r.appendChild(t);
    r.appendChild(x);
    dom.body.appendChild(r);
    dom.body.scrollTop = dom.body.scrollHeight;
  }

  function play() {
    if (!run) return;
    clear();
    dom.body.innerHTML = '';
    dom.body.style.setProperty('--kind', 'var(--k-' + run.kind + ')');
    dom.dot.className = 'ev-dot live';

    const factor = 1 / SPEED;
    const lines = run.cmd.split('\n');

    lines.forEach((line, i) => {
      timers.push(window.setTimeout(() => row('cmd', 0, line), i * 220 * factor));
    });

    const offset = lines.length * 220 * factor;

    run.lines.forEach((ln) => {
      timers.push(window.setTimeout(() => row(ln.tone || '', ln.t, ln.s, ln.key), offset + ln.t * factor));
    });

    const last = run.lines[run.lines.length - 1].t;
    timers.push(window.setTimeout(() => {
      dom.dot.className = 'ev-dot' + (run.status === 'fail' ? ' bad' : '');
    }, offset + last * factor + 60));
  }

  // Called from mockup.js on every render, including while the intro is still on screen.
  function show(stageIndex) {
    if (!ready()) return;

    const found = window.runsForStage(stageIndex);
    clear();
    dom.body.innerHTML = '';

    // The panel never leaves. A movement with nothing captured says so, because a column that
    // appears and vanishes as you navigate reads as a glitch, and "not captured" is itself a fact.
    if (!found.length) {
      run = null;
      dom.root.classList.add('idle');
      dom.dot.className = 'ev-dot none';
      dom.host.textContent = 'no capture';
      dom.note.textContent = '';
      dom.body.innerHTML = '<p class="ev-empty">No capture for this movement. ' +
        'The commands are listed underneath.</p>';
      dom.foot.hidden = true;
      return;
    }

    run = found[0];
    dom.root.classList.remove('idle');
    dom.host.textContent = run.host;
    dom.dot.className = 'ev-dot';

    // A duration only appears when one was actually measured. An empty column beats a hedge.
    dom.note.textContent = (run.real && run.real !== 'not timed') ? run.real : '';
    dom.foot.hidden = true;

    if (armed) play();
  }

  // boot.js calls this once the gate is down and the intro is done.
  function arm(stageIndex) {
    armed = true;
    show(stageIndex);
  }

  return { show, arm, play, currentId: () => (run ? run.id : null) };
})();

window.EVIDENCE = EVIDENCE;
