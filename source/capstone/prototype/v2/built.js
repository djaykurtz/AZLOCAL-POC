/*
 * BUILT. The cutaway.
 *
 * Not an overlay. The idea is that the designed interface is removed over this area so the thing
 * underneath is visible, which is why nothing behind it is blurred and why what shows through is
 * darker and denser than the console around it.
 *
 * Three payloads, chosen by where you are in the arc, because the cutaway tells its own story:
 *
 *   00 to 01   portal    the web interface, where this actually starts and gets confirmed
 *   02 to 09   terminal  the commands, once it is clear how much more they do
 *   10         next      where else this would be worth pointing
 *
 * Content is keyed off the movement, so adding a movement does not need anything here.
 */

const BUILT = (function () {
  'use strict';

  // Slower than the side panel on purpose. This is the stop and look moment, and steps that
  // arrive closer than about 300ms apart blur into one another rather than being read.
  const SPEED = 1.5;

  let dom = null;
  let timers = [];
  let waits = {};         // keyed rows currently animating an ellipsis
  let open = false;
  let armed = true;       // sub-slide mode, on by default. Next stops here before advancing.

  function el(id) { return document.getElementById(id); }

  function ready() {
    if (dom) return true;
    dom = {
      root: el('built'), num: el('builtNum'), title: el('builtTitle'),
      sub: el('builtSub'),
      host: el('builtHost'), real: el('builtReal'),
      term: el('builtTerm'), steps: el('builtSteps'),
      capL: el('builtCapL'), capR: el('builtCapR'),
      btn: el('btnBuilt'), close: el('builtClose')
    };
    if (!dom.root || !dom.btn) { dom = null; return false; }
    dom.close.addEventListener('click', () => hide());
    dom.btn.addEventListener('click', () => toggle());
    return true;
  }

  function clear() {
    timers.forEach(window.clearTimeout);
    timers = [];
    Object.keys(waits).forEach((k) => window.clearInterval(waits[k]));
    waits = {};
  }

  // The credits sit after the deck, so the closing frame belongs to the last numbered movement
  // rather than to the last stage.
  function lastNumbered() {
    if (!window.M) return 10;
    for (let i = window.M.count() - 1; i >= 0; i -= 1) {
      const s = window.M.stageData(i);
      if (s && !s.unnumbered) return i;
    }
    return 0;
  }

  // Which payload this movement gets.
  function kindFor(i) {
    if (PORTAL[i]) return 'portal';
    if (i >= lastNumbered()) return 'next';
    return 'terminal';
  }

  // Portal LAYOUT is drawn in every case, because no screenshot has been taken. The DATA behind
  // it is a different question per frame, so each one carries its own provenance line.
  //
  // Movement 00 deliberately has no entry here. Its BUILT frame is the terminal kind, because what
  // was true before Azure Local existed is a switch port survey, not an empty blade.
  const PORTAL = {
    1: {
      crumb: ['Home', 'Azure Arc', 'Machines'],
      title: 'Machines',
      type: 'Azure Arc',
      meta: '6 registered | 4 in the cluster',
      grid: '1.4fr 0.9fr 0.8fr 1.5fr 0.9fr',
      cols: ['Name', 'Status', 'Cluster', 'Model', 'Class'],
      // From capstone/media/evidence-2026-09-09-arc-and-cluster.txt. Guests are left out because
      // at this point in the story they do not exist yet.
      rows: [
        ['AZL-NODE-01', 'Connected', 'MEMBER', 'Precision 7960 Rack', 'ThirdParty'],
        ['AZL-NODE-02', 'Connected', 'MEMBER', 'Precision 7960 Rack', 'ThirdParty'],
        ['azl-node-03', 'Connected', '-', 'Precision 7960 Rack', 'ThirdParty'],
        ['AZL-NODE-04', 'Connected', 'MEMBER', 'Precision 7960 Rack', 'ThirdParty'],
        ['AZL-NODE-05', 'Connected', '-', 'Precision 7960 Rack', 'ThirdParty'],
        ['azl-node-06', 'Connected', 'MEMBER', 'Precision 7960 Rack', 'ThirdParty']
      ],
      empty: '',
      note: 'All six are registered with Arc and all six are Connected. Registration is what puts ' +
            'a machine on this list, and it happens before any cluster exists. Only four became ' +
            'members. Note what Azure calls the model: ThirdParty. The portal is already telling ' +
            'the truth about the hardware, and it is not flattering.',
      sketch: 'Every value read live from Azure on 2026-09-09.'
    },
    9: {
      crumb: ['Home', 'Resource groups', 'rg-azlocal-poc-001'],
      title: 'rg-azlocal-poc-001',
      type: '',
      meta: '53 resources | contoso-lab-sub',
      grid: '2fr 56px 1.7fr',
      cols: ['Resource type', 'Count', 'What it is'],
      rows: [
        ['MS.HybridCompute/machines/extensions', '20', 'four agents on every cluster node'],
        ['MS.HybridCompute/machines', '8', 'six physical, two guests'],
        ['MS.AzureStackHCI/*galleryImages', '6', 'local and marketplace images'],
        ['MS.AzureStackHCI/storageContainers', '4', 'storage paths on the cluster'],
        ['MS.AzureStackHCI/networkInterfaces', '2', 'one per guest machine'],
        ['MS.AzureStackHCI/logicalNetworks', '2', 'InfraLNET and TenantLNET'],
        ['MS.AzureStackHCI/virtualHardDisks', '1', 'one staged disk'],
        ['cluster, AKS, bridge, location', '4', 'one of each'],
        ['Insights, KeyVault, Storage, Attest', '6', 'monitoring, secrets, artifacts']
      ],
      empty: '',
      note: 'Grouped by type, because fifty three individual rows is a scroll rather than a point.',
      sketch: 'Every count read live from Azure on 2026-09-09.'
    }
  };

  const PORTAL_SIDE = {
    1: [
      { name: 'Why four, and not six', dur: 'ADR 0004',
        body: 'Three way mirror needs three machines to hold a copy, so the fourth is the ' +
              'one you can afford to lose. Building all six before four worked would have added ' +
              'storage, memory and validation risk without improving the odds of a first clean ' +
              'deployment.' },
      { name: 'What the spare actually buys', dur: 'node 03',
        body: 'Parts, not capacity. Node 05 was stripped to repair node 02 before deployment ' +
              'started, and node 03 is the last machine still sealed. That is worth more here ' +
              'than a fifth vote, because adding a machine is a validation pass and a rebalance ' +
              'rather than a failover.' },
      { name: 'Same model is not the same machine', dur: 'measured',
        body: 'Firmware levels differed out of the box. Drives differ by vendor, Samsung on 01 ' +
              'to 04 and KIOXIA on 05 and 06. One adapter on node 02 reported subsystem ' +
              '000615B3 where every other port reads 008015B3, and validation refuses a mismatch.' }
    ],
    9: [
      { name: 'Nothing here was clicked into existence', dur: '',
        body: 'The deployment created most of it. Terraform created one machine and removed it ' +
              'again. The rest arrived as a consequence of registering hardware with Arc.' },
      { name: 'Twenty of the fifty three are extensions', dur: '',
        body: 'Four agents on every node: Lifecycle Manager, Remote Support, Device Management, ' +
              'and Telemetry and Diagnostics. Management surface rather than workload.' },
      { name: 'What this blade still cannot tell you', dur: '',
        body: 'Which port carries which VLAN, whether the storage pool is repairing, or that ' +
              'Windows enumerated two adapters in the opposite order. That is the other column.' }
    ]
  };

  // The lead card carries the thesis of the whole section: the constraints in this deck were
  // bought, not inherent. Everything after it is written as an opportunity rather than a caveat,
  // because by this point the limitations have already been stated three times.
  const NEXT_CARDS = [
    { kind: 'proposed', tone: 'lead', title: 'The same platform, on hardware bought for the job',
      desc: 'Four things this project deferred share one cause between them. A managed database, ' +
            'a second Kubernetes worker, node pool scale, and more guests than the cluster can ' +
            'hold. All memory. These are 32 GB workstations that happened to be spare, and a node ' +
            'specified for Azure Local carries several times that. Nothing about the platform ' +
            'needed to change. The shopping list did.' },
    { kind: 'candidate', title: 'Work that never stops and never spikes',
      desc: 'Build agents, test runners, nightly batch. The machines cost the same busy or idle, ' +
            'so the work that suits them is the work that keeps them busy. Cloud meters that ' +
            'same flat pattern by the hour, every hour, forever.',
      need: 'Needs somebody to own the physical estate. Hardware is a person, not just a purchase.' },
    { kind: 'candidate', title: 'Work that is tied to a place',
      desc: 'Instruments and test equipment do not move to a region, and neither does data with ' +
            'a residency constraint. If a cable has to reach it, the compute lives in the building.' },
    { kind: 'candidate', title: 'Work where the data is the expensive part',
      desc: 'Anything that produces more than it consumes. Traces, captures, images, telemetry. ' +
            'Moving it out costs more than working on it in place, and the cluster is already ' +
            'sitting next to whatever made it.' },
    { kind: 'proposed', title: 'Disposable dev environments',
      desc: 'A container image with every dependency pulled in at build time, spun up in the ' +
            'cluster on demand and thrown away afterwards. Arc joined, so it is inventoried and ' +
            'governed like everything else in here.',
      need: 'Needs a private registry. There is nowhere yet to push an image the cluster can pull.' },
    { kind: 'boundary', tone: 'edge', title: 'Where it still would not fit',
      desc: 'Elastic demand, because a rack cannot absorb a spike however it is specified. And ' +
            'anything you want to stop paying for while it idles, which is the same cost model ' +
            'that makes everything above it work.' }
  ];

  const NEXT_SIDE = [
    { name: 'Three layers, not one', dur: 'posture',
      body: 'Everything Azure already enforces. Then the defaults Azure Local sets itself, ' +
            'stricter than people expect. Then a physical estate the cloud never asked about.' },
    { name: 'Two deliberate deviations', dur: 'recorded',
      body: 'Windows corporate security monitoring extension skipped under an approved exception. A deployment ' +
            'account holding interactive and batch logon rights that normal policy refuses.' },
    { name: 'Eight residual risks', dur: 'unsigned',
      body: 'Accepted in the document, not signed off by anybody. Listing them is the point. An ' +
            'attack surface nobody has enumerated is not smaller, it is unmeasured.' },
    { name: 'The line worth ending on', dur: '',
      body: 'Moving on premises does not reduce the security surface. It adds to it. You keep ' +
            'every control the cloud gave you, and then you add a building, a rack, a set of out ' +
            'of band management controllers, and a domain.' }
  ];

  function stamp(ms) {
    const s = Math.floor(ms / 1000);
    return String(Math.floor(s / 60)).padStart(2, '0') + ':' +
      String(s % 60).padStart(2, '0') + '.' + String(Math.floor((ms % 1000) / 100));
  }

  // A line carrying a key rewrites the row with that key instead of appending, so a step can sit
  // unresolved and then land in place. `wait` cycles the trailing dots, `pop` is the long
  // celebration used on the payoff lines.
  function row(ln, ms, cls) {
    const text = ln.s;
    const key = ln.key;
    let target = null;

    if (key) {
      if (waits[key]) { window.clearInterval(waits[key]); delete waits[key]; }
      const found = dom.term.querySelector('[data-key="' + key + '"]');
      if (found) {
        found.className = 'cut-row ' + cls;
        found.querySelector('.cut-x').textContent = text;
        // The clock moves with it. Watching one line take time is the point.
        found.querySelector('.cut-t').textContent = stamp(ms);
        void found.offsetWidth;          // restart the emphasis animation
        found.classList.add(ln.pop ? 'pop' : 'hit');
        target = found;
      }
    }

    if (!target) {
      const r = document.createElement('div');
      r.className = 'cut-row ' + cls;
      if (key) r.dataset.key = key;
      const t = document.createElement('span');
      t.className = 'cut-t';
      t.textContent = stamp(ms);
      const x = document.createElement('span');
      x.className = 'cut-x';
      x.textContent = text;
      r.appendChild(t);
      r.appendChild(x);
      dom.term.appendChild(r);
      dom.term.scrollTop = dom.term.scrollHeight;
      if (ln.pop) r.classList.add('pop');
      target = r;
    }

    if (ln.wait && key) {
      target.classList.add('waiting');
      const cell = target.querySelector('.cut-x');
      const base = text.replace(/\.+$/, '');
      let n = 3;
      waits[key] = window.setInterval(() => {
        n = (n % 3) + 1;
        cell.textContent = base + '.'.repeat(n);
      }, 420);
    } else {
      target.classList.remove('waiting');
    }
  }

  // A movement can own more than one run. Movement 00 owns the failure and the re-check after the
  // repair, and playing only the first one left the terminal ending on the problem.
  function playRuns(runs) {
    clear();
    dom.term.innerHTML = '';
    const factor = 1 / SPEED;
    let base = 0;

    runs.forEach((run, ri) => {
      const lines = run.cmd.split('\n');
      // A marked gap, not a blank row. The repair itself is the right pane's job, so the terminal
      // says only that time passed and what changed, then comes back with the retest.
      if (ri > 0 && run.gap) {
        const gaps = Array.isArray(run.gap) ? run.gap : [run.gap];
        const step = 2200 * factor;
        gaps.forEach((label, gi) => {
          timers.push(window.setTimeout(() => {
            const g = document.createElement('div');
            g.className = 'cut-gap';
            const m = /^(.*?)(FIXED!)\s*$/.exec(label);
            if (m) {
              g.textContent = m[1];
              const b = document.createElement('b');
              b.textContent = m[2];
              g.appendChild(b);
            } else {
              g.textContent = label;
            }
            dom.term.appendChild(g);
            dom.term.scrollTop = dom.term.scrollHeight;
          }, base + gi * step));
        });
        base += gaps.length * step + 1600 * factor;
      } else if (ri > 0) {
        base += 900 * factor;
      }

      const start = base;
      lines.forEach((line, i) => {
        timers.push(window.setTimeout(() => row({ s: line }, 0, 'cmd'), start + i * 240 * factor));
      });

      const offset = start + lines.length * 240 * factor;
      let last = 0;
      run.lines.forEach((ln) => {
        timers.push(window.setTimeout(() => row(ln, ln.t, ln.tone || ''), offset + ln.t * factor));
        if (ln.t > last) last = ln.t;
      });
      base = offset + last * factor;
    });
  }

  function renderSteps(stage) {
    dom.steps.innerHTML = '';
    (stage.groups || []).forEach((g) => {
      const d = document.createElement('div');
      d.className = 'cut-step ' + g.status;
      d.innerHTML =
        '<div class="cut-step-head">' +
          '<span class="cut-step-name"></span><span class="cut-step-dur"></span>' +
        '</div>' +
        '<div class="cut-step-cmd"></div><pre class="cut-step-out"></pre>';
      d.querySelector('.cut-step-name').textContent = g.name;
      d.querySelector('.cut-step-dur').textContent = g.dur;
      d.querySelector('.cut-step-cmd').textContent = g.cmd;
      d.querySelector('.cut-step-out').textContent = g.out;
      dom.steps.appendChild(d);
    });
  }

  function todo(node, text) {
    node.innerHTML = '';
    const p = document.createElement('p');
    p.className = 'cut-todo';
    p.textContent = text;
    node.appendChild(p);
  }

  // Reuses the step frame so the right pane looks the same whatever is in it.
  function panel(node, items, src) {
    node.innerHTML = '';
    items.forEach((it) => {
      const d = document.createElement('div');
      d.className = 'cut-step';
      d.innerHTML =
        '<div class="cut-step-head">' +
          '<span class="cut-step-name"></span><span class="cut-step-dur"></span>' +
        '</div><p class="cut-note"></p>';
      d.querySelector('.cut-step-name').textContent = it.name;
      d.querySelector('.cut-step-dur').textContent = it.dur || '';
      d.querySelector('.cut-note').textContent = it.body;
      node.appendChild(d);
    });
    if (src) {
      const p = document.createElement('p');
      p.className = 'cut-src';
      p.textContent = src;
      node.appendChild(p);
    }
  }

  function portalView(node, p) {
    node.innerHTML = '';
    const w = document.createElement('div');
    w.className = 'pv';

    const bar = document.createElement('div');
    bar.className = 'pv-bar';
    p.crumb.forEach((c, i) => {
      if (i) {
        const sep = document.createElement('span');
        sep.className = 'pv-sep';
        sep.textContent = '/';
        bar.appendChild(sep);
      }
      const s = document.createElement('span');
      s.className = 'pv-crumb' + (i === p.crumb.length - 1 ? ' is-last' : '');
      s.textContent = c;
      bar.appendChild(s);
    });
    w.appendChild(bar);

    const head = document.createElement('div');
    head.className = 'pv-head';
    head.innerHTML =
      '<span class="pv-icon" aria-hidden="true"></span>' +
      '<span class="pv-h"><span class="pv-title"></span><span class="pv-type"></span></span>';
    head.querySelector('.pv-title').textContent = p.title;
    head.querySelector('.pv-type').textContent = [p.type, p.meta].filter(Boolean).join(' | ');
    w.appendChild(head);

    if (p.rows.length) {
      const t = document.createElement('div');
      t.className = 'pv-table';

      // A column of short values reads better centred, and it stops a count crowding the long
      // name beside it. Five characters is the cutoff, judged on the values rather than the
      // heading, so a wide heading over narrow data still centres.
      const narrow = p.cols.map((c, i) =>
        p.rows.length > 0 && p.rows.every((r) => String(r[i]).length <= 5));

      const hr = document.createElement('div');
      hr.className = 'pv-tr pv-th';
      hr.style.gridTemplateColumns = p.grid;
      p.cols.forEach((c, i) => {
        const d = document.createElement('span');
        d.textContent = c;
        if (narrow[i]) d.className = 'pv-mid';
        hr.appendChild(d);
      });
      t.appendChild(hr);
      p.rows.forEach((r) => {
        const tr = document.createElement('div');
        tr.className = 'pv-tr';
        tr.style.gridTemplateColumns = p.grid;
        r.forEach((c, i) => {
          const d = document.createElement('span');
          d.textContent = c;
          if (c === 'Connected') d.className = 'pv-ok';
          if (narrow[i]) d.className += (d.className ? ' ' : '') + 'pv-mid';
          tr.appendChild(d);
        });
        t.appendChild(tr);
      });
      w.appendChild(t);
    } else {
      const e = document.createElement('p');
      e.className = 'pv-empty';
      e.textContent = p.empty;
      w.appendChild(e);
    }

    const n = document.createElement('p');
    n.className = 'pv-note';
    n.textContent = p.note;
    w.appendChild(n);

    const s = document.createElement('p');
    s.className = 'pv-sketch';
    s.textContent = p.sketch || 'Drawn from the real resource names. Not a capture yet.';
    w.appendChild(s);

    node.appendChild(w);
  }

  function nextView(node, cards) {
    node.innerHTML = '';
    const w = document.createElement('div');
    w.className = 'nx';
    cards.forEach((c) => {
      const d = document.createElement('div');
      d.className = 'nx-card' + (c.tone ? ' is-' + c.tone : '');
      d.innerHTML =
        '<span class="nx-k"></span><span class="nx-t"></span>' +
        '<p class="nx-d"></p><p class="nx-need"></p>';
      d.querySelector('.nx-k').textContent = c.kind;
      d.querySelector('.nx-t').textContent = c.title;
      d.querySelector('.nx-d').textContent = c.desc;
      const need = d.querySelector('.nx-need');
      if (c.need) need.textContent = c.need; else need.remove();
      w.appendChild(d);
    });
    node.appendChild(w);
  }

  function fill(i) {
    const stage = window.M.stageData(i);
    const kind = kindFor(i);

    dom.num.textContent = String(i).padStart(2, '0') + '.5';
    dom.title.textContent = stage.title;
    dom.sub.textContent = stage.builtSub || 'underneath the picture, this is what ran';
    dom.root.dataset.kind = kind;

    if (kind === 'terminal') {
      const found = window.runsForStage(i);
      const run = found.length ? found[0] : null;
      dom.host.textContent = run ? run.host : '';
      dom.real.textContent = (run && run.real && run.real !== 'not timed') ? run.real : '';
      dom.capL.textContent = 'Terminal';
      dom.capR.textContent = 'Every command behind this movement';
      if (found.length) { playRuns(found); } else { todo(dom.term, 'No capture for this movement.'); }
      renderSteps(stage);
      return;
    }

    if (kind === 'portal') {
      dom.host.textContent = 'portal.azure.com';
      dom.real.textContent = '';
      dom.capL.textContent = 'Portal';
      dom.capR.textContent = 'What this screen does not show you';
      portalView(dom.term, PORTAL[i]);
      panel(dom.steps, PORTAL_SIDE[i] || []);
      return;
    }

    dom.host.textContent = '';
    dom.real.textContent = '';
    dom.capL.textContent = 'Where this goes next';
    dom.capR.textContent = 'And the surface that comes with it';
    nextView(dom.term, NEXT_CARDS);
    panel(dom.steps, NEXT_SIDE, 'docs/access/security-posture-and-boundaries.md');
  }

  // Every movement carries a frame, so the rhythm stops on all of them. The credits are not a
  // movement and have nothing underneath them, so Next walks straight past.
  function hasBuilt(i) {
    const s = window.M ? window.M.stageData(i) : null;
    return !!s && !s.unnumbered;
  }

  // Returns true when BUILT handled the press and the deck should not advance.
  function interceptNext(i) {
    if (open) { hide(); return false; }
    if (armed && hasBuilt(i)) { show(); return true; }
    return false;
  }

  function show() {
    if (!ready() || !window.M) return;
    // A close may still be animating out. Cancel it rather than fighting it.
    const hole = dom.root.querySelector('.cut-hole');
    hole.classList.remove('closing');
    dom.root.classList.remove('closing');
    fill(window.M.stage());
    dom.root.hidden = false;
    dom.root.setAttribute('aria-hidden', 'false');
    dom.btn.classList.add('open');
    open = true;
  }

  function hide() {
    if (!ready() || !open) return;
    clear();
    open = false;
    dom.btn.classList.remove('open');

    // Collapse toward the button that opened it, so the cutaway has somewhere to go.
    const hole = dom.root.querySelector('.cut-hole');
    const h = window.FIT.rect(hole);
    const b = window.FIT.rect(dom.btn);
    hole.style.setProperty('--dx', ((b.left + b.width / 2) - (h.left + h.width / 2)).toFixed(0) + 'px');
    hole.style.setProperty('--dy', ((b.top + b.height / 2) - (h.top + h.height / 2)).toFixed(0) + 'px');
    hole.classList.add('closing');
    dom.root.classList.add('closing');

    timers.push(window.setTimeout(() => {
      hole.classList.remove('closing');
      dom.root.classList.remove('closing');
      dom.root.hidden = true;
      dom.root.setAttribute('aria-hidden', 'true');
    }, 300));
  }

  // A gear, not a door. The press changes what Next does, and Next is the only thing that opens
  // a frame. Pressing it while armed shifts back down, closing anything open on the way.
  function toggle() {
    if (armed) {
      if (open) hide();
      setArmed(false);
      return;
    }
    setArmed(true);
  }

  function setArmed(v) {
    armed = !!v;
    if (ready()) dom.btn.classList.toggle('armed', armed);
    const rail = document.querySelector('.rail');
    if (rail) rail.classList.toggle('armed', armed);
    // The bar belongs to the pane the cutaway opens over, not to the whole console.
    const work = document.querySelector('.work');
    if (work) work.classList.toggle('armed', armed);
  }

  // Wire up at load. ready() is what attaches the button handler, so nothing works until it runs.
  // Re-assert the armed default afterwards so the button, rail and work pane carry its classes.
  ready();
  setArmed(armed);

  return {
    show, hide, toggle, interceptNext, setArmed,
    isOpen: () => open,
    isArmed: () => armed,
    refresh: () => { if (open && window.M) fill(window.M.stage()); }
  };
})();

window.BUILT = BUILT;

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && window.BUILT.isOpen()) window.BUILT.hide();
});
