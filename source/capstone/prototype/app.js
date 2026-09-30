/*
 * Playback engine for the capstone vision prototype.
 * The narrative lives in scenario.js. This file only sequences and renders it.
 */

(function () {
  'use strict';

  const el = (id) => document.getElementById(id);

  const dom = {
    curtain: el('curtain'),
    begin: el('begin'),
    cutToggle: el('cutToggle'),
    shell: el('shell'),
    rail: el('rail'),
    canvas: el('canvas'),
    layers: el('layers'),
    wires: el('wires'),
    sweep: el('sweep'),
    spores: el('spores'),
    mods: el('mods'),
    modsEmpty: el('modsEmpty'),
    stream: el('stream'),
    detail: el('detail'),
    promptText: el('promptText'),
    stageIndex: el('stageIndex'),
    stageTitle: el('stageTitle'),
    stageExec: el('stageExec'),
    stageFid: el('stageFid'),
    statPods: el('statPods'),
    statLinks: el('statLinks'),
    statStage: el('statStage'),
    modeChip: el('modeChip'),
    uses: el('uses'),
    frame: el('frame'),
    frameBody: el('frameBody'),
    frameCount: el('frameCount'),
    frameVer: el('frameVer'),
    frameScan: el('frameScan'),
    growthLabel: el('growthLabel'),
    growthTime: el('growthTime'),
    growthFill: el('growthFill'),
    growthTicks: el('growthTicks'),
    btnPlay: el('btnPlay'),
    btnNext: el('btnNext'),
    btnBack: el('btnBack'),
    btnReset: el('btnReset'),
    btnSpeed: el('btnSpeed')
  };

  const NS = 'http://www.w3.org/2000/svg';
  const SPEEDS = [1, 1.5, 2, 3, 0.5];

  const state = {
    stage: -1,
    playing: false,
    speedIdx: 0,
    timers: [],
    started: false,
    linkKeys: new Set(),
    linkList: [],
    linkCount: 0
  };

  const speed = () => SPEEDS[state.speedIdx];
  const pad2 = (n) => String(n).padStart(2, '0');

  // Scripted times are stretched by PACE so the story does not imply instant infrastructure.
  function after(ms, fn) {
    const id = window.setTimeout(fn, (ms * PACE) / speed());
    state.timers.push(id);
    return id;
  }

  // Unscaled timing, used where a delay must match a CSS animation.
  function rawAfter(ms, fn) {
    const id = window.setTimeout(fn, ms);
    state.timers.push(id);
    return id;
  }

  function clearTimers() {
    state.timers.forEach(window.clearTimeout);
    state.timers = [];
  }

  /* ---------- Static construction ---------- */

  function buildRail() {
    dom.rail.innerHTML = '';
    SCENARIO.forEach((stage, i) => {
      const li = document.createElement('li');
      li.className = 'rail-item';
      li.dataset.index = String(i);
      li.innerHTML =
        '<span class="rail-num">' + pad2(i) + '</span>' +
        '<span class="rail-name"></span>' +
        '<span class="rail-tick">+</span>';
      li.querySelector('.rail-name').textContent = stage.title;
      li.addEventListener('click', () => {
        setPlaying(false);
        goTo(i);
      });
      dom.rail.appendChild(li);
    });
  }

  function buildCanvas() {
    dom.layers.innerHTML = '';
    ARCH_LAYERS.forEach((layer) => {
      const row = document.createElement('div');
      row.className = 'layer';
      const tag = document.createElement('span');
      tag.className = 'layer-tag';
      tag.textContent = layer.tag;
      const holder = document.createElement('div');
      holder.className = 'layer-row';

      layer.nodes.forEach((node) => {
        const box = document.createElement('div');
        box.className = 'node';
        box.id = 'node-' + node.id;
        box.innerHTML =
          '<span class="node-name"></span><span class="node-meta"></span>';
        box.querySelector('.node-name').textContent = node.name;
        box.querySelector('.node-meta').textContent = node.meta;
        holder.appendChild(box);
      });

      row.appendChild(tag);
      row.appendChild(holder);
      dom.layers.appendChild(row);
    });
  }

  function buildSpores() {
    for (let i = 0; i < 46; i += 1) {
      const spore = document.createElement('span');
      const size = (1.5 + Math.random() * 5).toFixed(1);
      const icy = Math.random() < 0.28;
      spore.className = 'spore' + (icy ? ' ice' : '');
      spore.style.width = size + 'px';
      spore.style.height = size + 'px';
      spore.style.left = (Math.random() * 100).toFixed(2) + '%';
      spore.style.top = (62 + Math.random() * 55).toFixed(2) + '%';
      spore.style.setProperty('--peak', (0.22 + Math.random() * 0.55).toFixed(2));
      spore.style.setProperty('--drift', (Math.random() * 90 - 45).toFixed(0) + 'px');
      spore.style.boxShadow = '0 0 ' + (4 + Number(size) * 2.4).toFixed(0) + 'px ' +
        (icy ? 'rgba(154, 214, 255, 0.8)' : 'rgba(143, 214, 168, 0.8)');
      spore.style.animationDuration = (16 + Math.random() * 26).toFixed(1) + 's';
      spore.style.animationDelay = (Math.random() * 30).toFixed(1) + 's';
      dom.spores.appendChild(spore);
    }
  }

  /* ---------- Rendering helpers ---------- */

  function renderMod(mod) {
    if (document.getElementById('mod-' + mod.id)) return;
    dom.modsEmpty.style.display = 'none';

    const card = document.createElement('div');
    card.className = 'mod';
    card.id = 'mod-' + mod.id;

    const head = document.createElement('div');
    head.className = 'mod-head';
    const title = document.createElement('span');
    title.className = 'mod-title';
    title.textContent = mod.title;
    head.appendChild(title);
    card.appendChild(head);

    mod.rows.forEach((row) => {
      const line = document.createElement('div');
      line.className = 'mod-row';
      const k = document.createElement('span');
      k.className = 'mod-k';
      k.textContent = row[0];
      const v = document.createElement('span');
      v.className = 'mod-v' + (row[2] ? ' ' + row[2] : '');
      v.textContent = row[1];
      line.appendChild(k);
      line.appendChild(v);
      card.appendChild(line);
    });

    dom.mods.appendChild(card);
  }

  function pushLine(entry) {
    const now = new Date();
    const stamp =
      pad2(now.getHours()) + ':' + pad2(now.getMinutes()) + ':' + pad2(now.getSeconds());

    const row = document.createElement('div');
    row.className = 'line' + (entry.tone ? ' ' + entry.tone : '');
    row.innerHTML =
      '<span class="line-t"></span><span class="line-b"><span class="line-src"></span> </span>';
    row.querySelector('.line-t').textContent = stamp;
    row.querySelector('.line-src').textContent = '[' + entry.src + ']';
    row.querySelector('.line-b').appendChild(document.createTextNode(entry.msg));

    dom.stream.appendChild(row);
    dom.stream.scrollTop = dom.stream.scrollHeight;
  }

  function renderDetail(blocks) {
    dom.detail.innerHTML = '';
    blocks.forEach((block) => {
      const cap = document.createElement('p');
      cap.className = 'detail-cap';
      cap.textContent = block.cap;
      const body = document.createElement('p');
      body.className = 'detail-body';
      body.textContent = block.body;
      dom.detail.appendChild(cap);
      dom.detail.appendChild(body);
    });
  }

  function typePrompt(text) {
    dom.promptText.textContent = '';
    let i = 0;
    const tick = () => {
      if (i > text.length) return;
      dom.promptText.textContent = text.slice(0, i);
      i += 1;
      after(26, tick);
    };
    tick();
  }

  function setNodes(ids, cls) {
    ids.forEach((id) => {
      const node = document.getElementById('node-' + id);
      if (node) node.classList.add(cls);
    });
  }

  function clearHot() {
    document.querySelectorAll('.node.hot').forEach((n) => n.classList.remove('hot'));
  }

  function countUp(target, value) {
    const from = parseInt(target.textContent, 10) || 0;
    if (from === value) return;
    const step = from < value ? 1 : -1;
    let current = from;
    const tick = () => {
      current += step;
      target.textContent = String(current);
      if (current !== value) after(90, tick);
    };
    after(90, tick);
  }

  /* ---------- Growing connections ---------- */

  // Organic vine curves for living workloads; angular circuit routing for machine paths.
  function pathBetween(fromId, toId, kind) {
    const a = document.getElementById('node-' + fromId);
    const b = document.getElementById('node-' + toId);
    if (!a || !b) return null;

    const box = dom.canvas.getBoundingClientRect();
    const ra = a.getBoundingClientRect();
    const rb = b.getBoundingClientRect();
    const sameRow = Math.abs(ra.top - rb.top) < 12;
    const ice = kind === 'ice';

    if (sameRow) {
      const forward = ra.left <= rb.left;
      const sx = (forward ? ra.right : ra.left) - box.left;
      const tx = (forward ? rb.left : rb.right) - box.left;
      const sy = ra.top + ra.height / 2 - box.top;
      const ty = rb.top + rb.height / 2 - box.top;

      if (ice) {
        const step = forward ? 10 : -10;
        return 'M ' + sx + ' ' + sy + ' L ' + (sx + step) + ' ' + sy +
               ' L ' + (tx - step) + ' ' + ty + ' L ' + tx + ' ' + ty;
      }
      const mid = (sx + tx) / 2;
      return 'M ' + sx + ' ' + sy + ' C ' + mid + ' ' + (sy - 20) + ', ' +
             mid + ' ' + (ty - 20) + ', ' + tx + ' ' + ty;
    }

    const sx = ra.left + ra.width / 2 - box.left;
    const sy = ra.bottom - box.top;
    const tx = rb.left + rb.width / 2 - box.left;
    const ty = rb.top - box.top;

    if (ice) {
      const drop = sy + (ty - sy) * 0.38;
      const rise = sy + (ty - sy) * 0.66;
      return 'M ' + sx + ' ' + sy + ' L ' + sx + ' ' + drop +
             ' L ' + tx + ' ' + rise + ' L ' + tx + ' ' + ty;
    }

    const bend = Math.max(20, (ty - sy) * 0.55);
    return 'M ' + sx + ' ' + sy + ' C ' + sx + ' ' + (sy + bend) + ', ' +
           tx + ' ' + (ty - bend) + ', ' + tx + ' ' + ty;
  }

  function growLink(fromId, toId, kind, instant) {
    const key = fromId + '__' + toId;
    if (state.linkKeys.has(key)) return;
    const d = pathBetween(fromId, toId, kind);
    if (!d) return;

    const ice = kind === 'ice' ? ' ice' : '';
    state.linkKeys.add(key);
    state.linkList.push([fromId, toId, kind]);

    const group = document.createElementNS(NS, 'g');
    group.setAttribute('data-key', key);

    const glow = document.createElementNS(NS, 'path');
    glow.setAttribute('class', 'wire-glow' + ice);
    glow.setAttribute('d', d);

    const base = document.createElementNS(NS, 'path');
    base.setAttribute('class', 'wire' + ice);
    base.setAttribute('d', d);

    const pulse = document.createElementNS(NS, 'path');
    pulse.setAttribute('class', 'wire-pulse' + ice);
    pulse.setAttribute('d', d);

    group.appendChild(glow);
    group.appendChild(base);
    group.appendChild(pulse);
    dom.wires.appendChild(group);

    const len = base.getTotalLength();
    [glow, base, pulse].forEach((p) => p.style.setProperty('--len', len));

    state.linkCount += 1;
    dom.statLinks.textContent = String(state.linkCount);

    if (instant) {
      base.style.animation = 'none';
      base.style.strokeDashoffset = '0';
      glow.style.animation = 'none';
      glow.style.strokeDashoffset = '0';
      glow.style.opacity = kind === 'ice' ? '0.2' : '0.16';
    } else {
      rawAfter(kind === 'ice' ? 800 : 1450, () => pulse.classList.add('run'));
    }
  }

  function pulseLink(fromId, toId) {
    const group = dom.wires.querySelector('[data-key="' + fromId + '__' + toId + '"]');
    if (!group) return;
    const pulse = group.querySelector('.wire-pulse');
    pulse.classList.remove('run');
    void pulse.getBoundingClientRect();
    pulse.classList.add('run');
  }

  function clearWires() {
    dom.wires.innerHTML = '';
    state.linkKeys.clear();
    state.linkList = [];
    state.linkCount = 0;
    dom.statLinks.textContent = '0';
  }

  function redrawWires() {
    const existing = state.linkList.slice();
    clearWires();
    existing.forEach((link) => growLink(link[0], link[1], link[2], true));
  }

  /* ---------- The product frame builds itself ---------- */

  function widgetInner(mod) {
    if (mod.kind === 'shell') {
      return '<div class="wg-note">' + mod.note + '</div>';
    }

    if (mod.kind === 'hello') {
      const meta = mod.meta
        .map((m) => '<span>' + m[0] + ' <b>' + m[1] + '</b></span>')
        .join('');
      return '<div class="wg-heading">' + mod.heading + '</div>' +
             '<div class="wg-sub">' + mod.sub + '</div>' +
             '<div class="wg-meta">' + meta + '</div>';
    }

    if (mod.kind === 'tiles') {
      const tiles = mod.tiles
        .map((t) => '<div class="wg-tile"><em>' + t[1] + '</em><span>' + t[0] + '</span></div>')
        .join('');
      return '<div class="wg-tiles">' + tiles + '</div>';
    }

    if (mod.kind === 'bars') {
      const peak = Math.max.apply(null, mod.bars.map((b) => b[1]));
      const bars = mod.bars.map((b, i) => {
        const pct = Math.round((b[1] / peak) * 100);
        return '<div class="wg-bar">' +
          '<span class="wg-bar-name">' + b[0] + '</span>' +
          '<span class="wg-bar-track"><span class="wg-bar-fill" style="width:' + pct +
          '%;animation-delay:' + (i * 140) + 'ms"></span></span>' +
          '<span class="wg-bar-val">' + b[1] + '</span></div>';
      }).join('');
      return bars + '<div class="wg-foot">' + mod.foot + '</div>';
    }

    if (mod.kind === 'health') {
      return mod.pills
        .map((p) => '<div class="wg-pill"><span>' + p[0] + '</span><b>' + p[1] + '</b></div>')
        .join('');
    }

    if (mod.kind === 'infra') {
      return mod.rows
        .map((r) => '<div class="wg-row"><span>' + r[0] + '</span><b>' + r[1] + '</b></div>')
        .join('');
    }

    if (mod.kind === 'map') {
      const chain = mod.chain
        .map((n) => '<span class="wg-node">' + n + '</span>')
        .join('<span class="wg-link">-&gt;</span>');
      return '<div class="wg-chain">' + chain + '</div>' +
             '<div class="wg-foot">' + mod.foot + '</div>';
    }

    return '';
  }

  const LOCK_SVG =
    '<svg viewBox="0 0 16 16" aria-hidden="true">' +
    '<rect x="3.2" y="7" width="9.6" height="7" rx="1.4"></rect>' +
    '<path d="M5.6 7V5.2a2.4 2.4 0 0 1 4.8 0V7"></path></svg>';

  // Every slot exists from the start, locked, so the finished shape is legible before it is real.
  function buildSlots() {
    dom.frameBody.innerHTML = '';
    FRAME_SLOTS.forEach((slot) => {
      const box = document.createElement('div');
      box.className = 'slot';
      box.id = slot.id;
      box.style.gridColumn = 'span ' + slot.span;
      box.style.minHeight = slot.minH + 'px';
      box.innerHTML =
        '<span class="slot-info">i</span>' +
        '<div class="slot-fill"><span class="slot-lock">' + LOCK_SVG +
        '</span><span class="slot-name"></span></div>' +
        '<div class="slot-body"></div>';
      box.querySelector('.slot-name').textContent = slot.name;
      dom.frameBody.appendChild(box);
    });
    updateSlotCount();
  }

  function updateSlotCount() {
    const open = dom.frameBody.querySelectorAll('.slot.open').length;
    dom.frameCount.textContent = open + ' / ' + FRAME_SLOTS.length + ' modules';
  }

  function mountModule(mod, instant) {
    const slot = document.getElementById(mod.id);
    if (!slot || slot.classList.contains('open')) return;

    const body = slot.querySelector('.slot-body');
    body.innerHTML =
      '<div class="wg"><div class="wg-head"><span class="wg-title"></span>' +
      '<span class="wg-tag">mounted</span></div>' + widgetInner(mod) + '</div>';
    body.querySelector('.wg-title').textContent = mod.title;
    if (instant) body.querySelector('.wg').style.animation = 'none';

    slot.classList.add('open');
    if (!instant) {
      slot.classList.add('unlocking');
      rawAfter(900, () => slot.classList.remove('unlocking'));
    }
    updateSlotCount();
  }

  function reloadFrame(version) {
    dom.frame.classList.add('reloading');
    dom.frameScan.classList.remove('run');
    void dom.frameScan.getBoundingClientRect();
    dom.frameScan.classList.add('run');
    dom.frameVer.classList.add('bump');
    rawAfter(300, () => dom.frameVer.classList.remove('bump'));
    rawAfter(700, () => dom.frame.classList.remove('reloading'));
    if (version) dom.frameVer.textContent = version;
  }

  function resetFrame() {
    dom.frameBody.querySelectorAll('.slot').forEach((slot) => {
      slot.classList.remove('open', 'unlocking');
      slot.querySelector('.slot-body').innerHTML = '';
    });
    dom.frameVer.textContent = 'v0.0';
    updateSlotCount();
  }

  /* ---------- Growth progress ---------- */

  function primeGrowth(stage) {
    const steps = stage.stream.length || 1;
    dom.growthTicks.innerHTML = '';
    for (let i = 0; i < steps; i += 1) {
      const tick = document.createElement('span');
      tick.className = 'tick';
      dom.growthTicks.appendChild(tick);
    }
    dom.growthFill.style.width = '0%';

    const elapsed = STAGE_ELAPSED[stage.id] || { value: 'not measured', kind: 'none' };
    dom.growthTime.textContent = elapsed.value;
    dom.growthTime.className = 'growth-time ' + elapsed.kind;
    dom.growthLabel.textContent = 'establishing';
  }

  function renderUses(stage) {
    dom.uses.innerHTML = '';
    (STAGE_USES[stage.id] || []).forEach((use, i) => {
      const card = document.createElement('div');
      card.className = 'use';
      card.style.animationDelay = (i * 130) + 'ms';
      card.innerHTML = '<span class="use-label"></span><span class="use-text"></span>';
      card.querySelector('.use-label').textContent = use.label;
      card.querySelector('.use-text').textContent = use.text;
      dom.uses.appendChild(card);
    });
  }

  function advanceGrowth(stage, i) {
    const steps = stage.stream.length || 1;
    const pct = Math.round(((i + 1) / steps) * 100);
    dom.growthFill.style.width = pct + '%';

    const ticks = dom.growthTicks.children;
    for (let k = 0; k <= i && k < ticks.length; k += 1) ticks[k].className = 'tick done';
    if (i + 1 < ticks.length) ticks[i + 1].className = 'tick active';

    const entry = stage.stream[i];
    const tail = pct === 100 ? 'established' : 'growing';
    dom.growthLabel.innerHTML =
      entry.src + ' <span class="arrow">-&gt;</span> ' + tail;
  }

  function runSweep() {
    dom.sweep.classList.remove('run');
    void dom.sweep.getBoundingClientRect();
    dom.sweep.classList.add('run');

    const work = document.querySelector('.work');
    work.classList.remove('pull');
    void work.getBoundingClientRect();
    work.classList.add('pull');
  }

  /* ---------- Stage control ---------- */

  function resetVisualState() {
    document.querySelectorAll('.node').forEach((n) => n.classList.remove('on', 'hot'));
    dom.mods.querySelectorAll('.mod').forEach((m) => m.remove());
    dom.modsEmpty.style.display = '';
    dom.stream.innerHTML = '';
    dom.statPods.textContent = '0';
    clearWires();
    resetFrame();
  }

  // Replays every stage before the target so a jump lands on a consistent picture.
  function applyHistory(index) {
    resetVisualState();
    for (let i = 0; i < index; i += 1) {
      const stage = SCENARIO[i];
      setNodes(stage.arch, 'on');
      stage.mods.forEach(renderMod);
      (STAGE_LINKS[stage.id] || []).forEach((link) => growLink(link[0], link[1], link[2], true));
      const build = STAGE_WIDGETS[stage.id];
      if (build) {
        build.modules.forEach((mod) => mountModule(mod, true));
        dom.frameVer.textContent = build.version;
      }
      dom.statPods.textContent = String(stage.pods);
    }
  }

  function markRail(index) {
    Array.from(dom.rail.children).forEach((item, i) => {
      item.classList.toggle('active', i === index);
      item.classList.toggle('done', i < index);
    });
  }

  function goTo(index, opts) {
    const options = opts || {};
    if (index < 0 || index >= SCENARIO.length) return;

    clearTimers();
    clearHot();

    // Only continuous playback preserves the current picture; any jump rebuilds it.
    const sequential = index === state.stage + 1;
    state.stage = index;
    const stage = SCENARIO[index];

    if (!sequential || options.rebuild) applyHistory(index);

    markRail(index);
    dom.stageIndex.textContent = pad2(index);
    dom.statStage.textContent = pad2(index);
    dom.stageTitle.textContent = stage.title;
    dom.stageExec.innerHTML = stage.exec;

    const proven = stage.fid === 'proven';
    dom.stageFid.className = 'fid ' + (proven ? 'fid-proven' : 'fid-story');
    dom.stageFid.textContent = proven ? 'Proven' : 'Storyboard';
    dom.modeChip.textContent = proven ? 'Recorded evidence' : 'Storyboard';

    renderDetail(stage.detail);
    typePrompt(stage.prompt);
    primeGrowth(stage);
    renderUses(stage);
    runSweep();

    stage.stream.forEach((entry, i) => {
      after(entry.t + 380, () => {
        pushLine(entry);
        advanceGrowth(stage, i);
      });
    });

    const reveal = 620;
    after(reveal, () => {
      setNodes(stage.arch, 'on');
      setNodes(stage.hot, 'hot');
      countUp(dom.statPods, stage.pods);
    });

    // Connections take root one at a time, after their nodes have appeared.
    const links = STAGE_LINKS[stage.id] || [];
    links.forEach((link, i) => {
      after(reveal + 260 + i * 300, () => growLink(link[0], link[1], link[2], false));
    });

    // The product frame hot-loads this stage's modules and bumps its version.
    const build = STAGE_WIDGETS[stage.id];
    if (build) {
      after(reveal + 520, () => reloadFrame(build.version));
      build.modules.forEach((mod, i) => {
        after(reveal + 900 + i * 420, () => mountModule(mod, false));
      });
    }

    const pulses = STAGE_PULSES[stage.id] || [];
    pulses.forEach((pair, i) => {
      after(reveal + 900 + i * 520, () => pulseLink(pair[0], pair[1]));
    });

    stage.mods.forEach((mod, i) => {
      after(reveal + 700 + i * 320, () => renderMod(mod));
    });

    const last = stage.stream.length
      ? stage.stream[stage.stream.length - 1].t
      : 0;
    const total = last + 380 + (stage.dwell || 1500);

    if (state.playing) {
      after(total, () => {
        if (state.stage < SCENARIO.length - 1) {
          goTo(state.stage + 1);
        } else {
          setPlaying(false);
        }
      });
    }
  }

  function setPlaying(next) {
    state.playing = next;
    dom.btnPlay.textContent = next ? 'Pause' : 'Play';
    if (next) goTo(state.stage < 0 ? 0 : state.stage);
    else clearTimers();
  }

  function reset() {
    clearTimers();
    state.playing = false;
    state.stage = -1;
    resetVisualState();
    dom.promptText.textContent = '';
    dom.detail.innerHTML = '';
    dom.stageExec.textContent = '';
    dom.stageTitle.textContent = 'Cold start';
    dom.stageIndex.textContent = '00';
    dom.statStage.textContent = '00';
    dom.stageFid.textContent = '';
    dom.stageFid.className = '';
    dom.growthFill.style.width = '0%';
    dom.growthTicks.innerHTML = '';
    dom.growthLabel.textContent = 'standby';
    dom.growthTime.textContent = '';
    dom.growthTime.className = 'growth-time';
    dom.uses.innerHTML = '';
    markRail(-1);
    dom.btnPlay.textContent = 'Play';
    dom.shell.classList.remove('live');
    dom.shell.setAttribute('aria-hidden', 'true');
    dom.curtain.classList.remove('gone');
    state.started = false;
  }

  function start() {
    if (state.started) return;
    state.started = true;
    dom.curtain.classList.add('gone');
    dom.shell.setAttribute('aria-hidden', 'false');
    window.setTimeout(() => {
      dom.shell.classList.add('live');
      state.playing = true;
      dom.btnPlay.textContent = 'Pause';
      goTo(0);
    }, 520);
  }

  // The director's cut plays first when asked for, then hands back here.
  function beginPressed() {
    if (state.started) return;
    if (dom.cutToggle && dom.cutToggle.checked && typeof INTRO !== 'undefined') {
      dom.curtain.classList.add('gone');
      INTRO.play(start);
      return;
    }
    start();
  }

  /* ---------- Wiring ---------- */

  dom.begin.addEventListener('click', beginPressed);

  dom.btnPlay.addEventListener('click', () => setPlaying(!state.playing));

  dom.btnNext.addEventListener('click', () => {
    setPlaying(false);
    goTo(Math.min(state.stage + 1, SCENARIO.length - 1));
  });

  dom.btnBack.addEventListener('click', () => {
    setPlaying(false);
    goTo(Math.max(state.stage - 1, 0));
  });

  dom.btnReset.addEventListener('click', reset);

  dom.btnSpeed.addEventListener('click', () => {
    state.speedIdx = (state.speedIdx + 1) % SPEEDS.length;
    dom.btnSpeed.textContent = speed().toFixed(1) + 'x';
  });

  document.addEventListener('keydown', (event) => {
    if (typeof INTRO !== 'undefined' && INTRO.isRunning()) {
      if (event.key === 'Escape' || event.key === ' ' || event.key === 'Enter') {
        event.preventDefault();
        INTRO.finish();
      }
      return;
    }
    if (!state.started) {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        beginPressed();
      }
      return;
    }
    if (event.key === ' ') {
      event.preventDefault();
      setPlaying(!state.playing);
    } else if (event.key === 'ArrowRight') {
      dom.btnNext.click();
    } else if (event.key === 'ArrowLeft') {
      dom.btnBack.click();
    } else if (event.key.toLowerCase() === 'r') {
      reset();
    }
  });

  let resizeTimer = null;
  window.addEventListener('resize', () => {
    window.clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(redrawWires, 180);
  });

  // Cinematic boot: the system draws you in before it hands over control.
  function runBoot() {
    const num = el('bootNum');
    const fill = el('bootFill');
    const line = el('bootLine');
    const steps = [
      [0, 'holding'],
      [12, 'reading cluster identity'],
      [28, 'attaching control plane'],
      [44, 'mounting storage fabric'],
      [61, 'resolving custom location'],
      [78, 'preparing console frame'],
      [93, 'awaiting operator'],
      [100, 'ready']
    ];

    let value = 0;
    let stepIdx = 0;
    const total = 2900;
    const started = performance.now();

    const tick = (now) => {
      const t = Math.min(1, (now - started) / total);
      const eased = 1 - Math.pow(1 - t, 2.4);
      value = Math.round(eased * 100);
      num.textContent = String(value).padStart(2, '0');
      fill.style.width = value + '%';

      while (stepIdx < steps.length - 1 && value >= steps[stepIdx + 1][0]) {
        stepIdx += 1;
        line.textContent = steps[stepIdx][1];
      }

      if (t < 1) {
        window.requestAnimationFrame(tick);
      } else {
        dom.begin.classList.remove('locked');
      }
    };

    window.requestAnimationFrame(tick);
  }

  buildRail();
  buildCanvas();
  buildSlots();
  buildSpores();
  markRail(-1);
  runBoot();
})();
