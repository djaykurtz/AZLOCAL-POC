/*
 * Standalone player for the shared run list. This file is the player, not the record.
 *
 * The runs live in ../shared/runs.js because they are the command layer under the v2 visual, not
 * the private property of this page. v2 reads the same file and binds each run to the movement it
 * belongs to. Anything added there appears here for free.
 *
 * This page exists to browse and rehearse every run in one place, including the ones that do not
 * belong to a movement. v2 is where an audience sees them.
 *
 * Two honesty rules baked into the design:
 *   - One run is live. Every other one is a replay. The footer always says which.
 *   - Compression is stated. A step that really took hours and replays in seconds says so, so
 *     nobody leaves the room thinking it was instant.
 */

const RUNS = window.RUNS;

(function () {
  'use strict';

  const el = (id) => document.getElementById(id);
  const stage = el('stage');
  const list = el('claimList');
  const body = el('termBody');
  const hostEl = el('termHost');
  const noteEl = el('termNote');
  const footEl = el('termFoot');
  const dot = document.querySelector('.dot');

  let speed = 6;
  let current = null;
  let forceRecorded = false;
  let timers = [];

  const kindVar = (k) => 'var(--k-' + k + ')';

  function clearTimers() {
    timers.forEach((t) => window.clearTimeout(t));
    timers = [];
  }

  function stamp(ms) {
    const s = Math.floor(ms / 1000);
    return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0') + '.' +
      String(Math.floor((ms % 1000) / 100));
  }

  function addRow(cls, ms, text) {
    const row = document.createElement('div');
    row.className = 'row ' + cls;
    const ts = document.createElement('span');
    ts.className = 'ts';
    ts.textContent = stamp(ms);
    const tx = document.createElement('span');
    tx.className = 'txt';
    tx.textContent = text;
    row.appendChild(ts);
    row.appendChild(tx);
    body.appendChild(row);
    body.scrollTop = body.scrollHeight;
    return row;
  }

  function play(claim) {
    clearTimers();
    current = claim;
    body.innerHTML = '';
    body.style.setProperty('--kind', kindVar(claim.kind));

    hostEl.textContent = claim.host;

    // A live claim does not replay. It hands you the command and keeps the recording in reserve,
    // so a dead network is a shrug rather than a dead end.
    if (claim.live && !forceRecorded) {
      dot.className = 'dot';
      noteEl.textContent = 'live';
      body.innerHTML =
        '<div class="cue">' +
          '<p class="cue-lead">Run this for real, in the terminal beside you.</p>' +
          '<pre class="cue-cmd"></pre>' +
          '<p class="cue-why">It is read only. It changes nothing, it takes about three seconds, and it is the ' +
          'one moment that proves the rest of this was not a video.</p>' +
          '<button type="button" class="cue-fall" id="btnFallback">It is not answering. Show the recording.</button>' +
        '</div>';
      body.querySelector('.cue-cmd').textContent = claim.cmd;
      body.querySelector('#btnFallback').addEventListener('click', () => {
        forceRecorded = true;
        play(claim);
      });
      footEl.textContent = '';
      return;
    }

    dot.className = 'dot live';

    // Speed 0 means dump everything at once, which is what you want when the room has questions.
    const factor = speed === 0 ? 0 : 1 / speed;
    const last = claim.lines[claim.lines.length - 1].t;

    noteEl.textContent = claim.real === 'not timed'
      ? ''
      : (speed === 0 ? 'real run ' + claim.real : speed + 'x, real run ' + claim.real);

    claim.cmd.split('\n').forEach((line, i) => {
      const at = i * 220 * factor;
      timers.push(window.setTimeout(() => addRow('cmd', 0, line), at));
    });

    const offset = claim.cmd.split('\n').length * 220 * factor;

    claim.lines.forEach((ln) => {
      timers.push(window.setTimeout(() => {
        addRow(ln.tone || '', ln.t, ln.s);
      }, offset + ln.t * factor));
    });

    timers.push(window.setTimeout(() => {
      dot.className = 'dot' + (claim.status === 'fail' ? ' bad' : '');
    }, offset + last * factor + 60));

    footEl.textContent = '';
  }

  RUNS.forEach((c) => {
    const li = document.createElement('li');
    li.className = 'claim' + (c.status === 'fail' ? ' bad' : '');
    li.style.setProperty('--kind', kindVar(c.kind));
    li.innerHTML =
      '<div class="claim-top">' +
        '<span class="claim-mark"></span>' +
        '<span class="claim-where"></span>' +
      '</div>' +
      '<div class="claim-text"></div>' +
      '<div class="claim-cmd"></div>';

    li.querySelector('.claim-mark').textContent = c.status === 'fail' ? 'x' : 'ok';
    li.querySelector('.claim-where').textContent = c.live ? 'live' : c.where;
    if (c.live) li.classList.add('is-live');
    li.querySelector('.claim-text').textContent = c.what;
    li.querySelector('.claim-cmd').textContent = c.cmd;

    li.addEventListener('click', () => {
      Array.from(list.children).forEach((n) => n.classList.remove('on'));
      li.classList.add('on');
      forceRecorded = false;
      play(c);
    });

    list.appendChild(li);
  });

  el('layoutSeg').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    Array.from(e.currentTarget.children).forEach((n) => n.classList.remove('on'));
    b.classList.add('on');
    stage.dataset.layout = b.dataset.layout;
  });

  el('speedSeg').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    Array.from(e.currentTarget.children).forEach((n) => n.classList.remove('on'));
    b.classList.add('on');
    speed = Number(b.dataset.speed);
    if (current) play(current);
  });

  el('btnReplay').addEventListener('click', () => { if (current) play(current); });

  // v2 opens this player on the run already on screen, so the big terminal continues the thought
  // instead of starting over somewhere else in the list.
  function openFromHash() {
    const id = (window.location.hash.match(/run=([\w-]+)/) || [])[1];
    const i = id ? RUNS.findIndex((c) => c.id === id) : -1;
    return i >= 0 ? (list.children[i].click(), true) : false;
  }

  window.addEventListener('hashchange', openFromHash);
  if (!openFromHash()) list.firstElementChild.click();
}());
