/*
 * Practice loop.
 *
 * Retrieval before reveal. The whole value is in the attempt, so the answer stays hidden until you
 * ask for it and there are no hints on the question side. Recognising a right answer in a list is
 * not the skill being trained, producing one out loud is.
 *
 * Self marking, because the only useful question is whether you would have said that in front of
 * the room, and no scoring rule can judge that. Marks weight what comes back rather than gating
 * anything, so the deck drifts toward what you keep fumbling.
 */

(function () {
  'use strict';

  const KEY = 'capprep.v1';
  const TRACKS = ['all', 'kubernetes', 'terraform', 'docker', 'azure-local', 'project'];

  // Stored level names are terse. These are what actually reads on screen.
  const LEVEL = { basic: 'basic', foundation: 'core', working: 'working', pressed: 'deeper' };

  let marks = {};
  let track = 'all';
  let current = null;
  let shown = false;

  function el(id) { return document.getElementById(id); }

  function load() {
    try { marks = JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { marks = {}; }
  }
  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(marks)); } catch (e) { /* private mode */ }
  }

  function pool() {
    return window.DECK.filter((d) => track === 'all' || d.track === track);
  }

  // Unseen first, then weighted by how badly it went. A 1 comes back roughly six times as often as
  // a 3, so the deck keeps handing you the things you cannot yet say.
  function pick() {
    const items = pool();
    if (!items.length) return null;

    const unseen = items.filter((d) => !marks[d.id]);
    if (unseen.length) return unseen[Math.floor(Math.random() * unseen.length)];

    const weighted = [];
    items.forEach((d) => {
      const m = marks[d.id] ? marks[d.id].last : 2;
      const n = m === 1 ? 6 : m === 2 ? 3 : 1;
      for (let i = 0; i < n; i++) weighted.push(d);
    });
    let next = weighted[Math.floor(Math.random() * weighted.length)];
    // Do not hand back the same card twice running unless it is the only one.
    if (next === current && items.length > 1) {
      next = weighted[Math.floor(Math.random() * weighted.length)];
    }
    return next;
  }

  function list(node, arr) {
    node.innerHTML = '';
    arr.forEach((t) => {
      const li = document.createElement('li');
      li.textContent = t;
      node.appendChild(li);
    });
  }

  // Commands get a console rather than a sentence, so a thing you type never reads as prose.
  // A trailing hash is a comment on the line, a leading hash is a comment line on its own.
  function console_(node, lines, shell) {
    node.innerHTML = '';
    (lines || []).forEach((raw) => {
      const row = document.createElement('div');
      const text = String(raw);

      if (text.trim().charAt(0) === '#') {
        row.className = 'con-note';
        row.textContent = text.trim().replace(/^#\s?/, '');
        node.appendChild(row);
        return;
      }

      row.className = 'con-line';
      const p = document.createElement('span');
      p.className = 'con-p';
      p.textContent = shell === 'ps' ? 'PS>' : '$';
      row.appendChild(p);

      const cut = text.indexOf('#');
      const cmd = document.createElement('span');
      cmd.className = 'con-c';
      cmd.textContent = cut === -1 ? text : text.slice(0, cut).replace(/\s+$/, '');
      row.appendChild(cmd);

      if (cut !== -1) {
        const c = document.createElement('span');
        c.className = 'con-note inline';
        c.textContent = text.slice(cut).replace(/^#\s?/, '');
        row.appendChild(c);
      }
      node.appendChild(row);
    });
  }

  function render() {
    current = pick();
    shown = false;
    if (!current) return;

    el('cardTrack').textContent = current.track;
    el('cardNum').textContent = '#' + (window.DECK.indexOf(current) + 1);
    el('cardId').textContent = current.id;
    el('cardLevel').textContent = LEVEL[current.level] || current.level;
    el('cardLevel').className = 'lvl lvl-' + current.level;
    el('q').textContent = current.q;

    list(el('say'), current.say);
    el('dia').hidden = !current.diagram;
    el('diagram').textContent = current.diagram || '';
    el('cmdWrap').hidden = !current.cmds;
    console_(el('cmds'), current.cmds, current.shell);
    el('helpWrap').hidden = !current.help;
    console_(el('help'), current.help, current.shell);
    el('why').textContent = current.why;
    el('ours').textContent = current.ours;
    el('artWrap').hidden = !current.artifact;
    el('artFile').textContent = current.artifact ? current.artifact.file : '';
    el('artifact').textContent = current.artifact ? current.artifact.body : '';
    el('src').textContent = current.src;

    el('answer').hidden = true;
    el('marks').hidden = true;
    el('reveal').hidden = false;
    el('prompt').hidden = false;

    const seen = marks[current.id];
    el('hint').textContent = seen
      ? 'You have answered this ' + seen.n + ' time' + (seen.n === 1 ? '' : 's') + '. Last time: ' + label(seen.last) + '.'
      : 'You have not seen this one before.';

    stat();
  }

  function label(m) {
    return m === 3 ? 'knew it' : m === 2 ? 'roughly' : 'not yet';
  }

  function reveal() {
    if (shown || !current) return;
    shown = true;
    el('answer').hidden = false;
    el('reveal').hidden = true;
    el('prompt').hidden = true;
    el('marks').hidden = false;
  }

  function mark(m) {
    if (!shown || !current) return;
    const prev = marks[current.id] || { n: 0 };
    marks[current.id] = { n: prev.n + 1, last: m };
    save();
    render();
  }

  function stat() {
    const items = pool();
    const weak = items.filter((d) => marks[d.id] && marks[d.id].last === 1).length;
    const solid = items.filter((d) => marks[d.id] && marks[d.id].last === 3).length;
    const unseen = items.filter((d) => !marks[d.id]).length;
    el('stat').textContent = items.length + ' cards, ' + unseen + ' new, ' + solid + ' known, ' + weak + ' to work on';
  }

  function buildTracks() {
    const nav = el('tracks');
    nav.innerHTML = '';
    TRACKS.forEach((t) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'track' + (t === track ? ' on' : '');
      b.textContent = t;
      b.addEventListener('click', () => {
        track = t;
        buildTracks();
        render();
      });
      nav.appendChild(b);
    });
  }

  el('reveal').addEventListener('click', reveal);
  el('marks').addEventListener('click', (e) => {
    const b = e.target.closest('[data-mark]');
    if (b) mark(Number(b.dataset.mark));
  });
  el('reset').addEventListener('click', () => {
    marks = {};
    save();
    render();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); shown ? null : reveal(); return; }
    if (!shown) return;
    if (e.key === '1') mark(3);
    if (e.key === '2') mark(2);
    if (e.key === '3') mark(1);
  });

  load();
  buildTracks();
  render();
})();
