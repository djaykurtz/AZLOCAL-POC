/*
 * The acceptance criteria checklist.
 *
 * The original brief, on screen for the whole run, so every movement is visibly answering
 * something that was asked for at the start rather than showing whatever happened to get built.
 *
 * The marks are deliberately not all ticks. The traceability table has five different outcomes
 * and flattening them into green checkmarks would be the dishonest version. An architecture
 * finding, where the Azure resource does not exist on Azure Local and something else covers the
 * original intent, is a different answer from a pass and reads as a different mark. Those two are
 * arguably the most interesting results in the project, so they get their own glyph rather than
 * being quietly ticked or quietly left blank.
 *
 * Everything here is meant to be rearranged. `s` is the list of movements that earn an item, so
 * moving a criterion to a different movement is a one line edit. An item with more than one
 * movement marks partially on the first and completes on the last, which is how Availability Sets
 * works: movement 07 proves the update domain half, movement 08 proves the fault domain half.
 *
 * Sources:
 *   docs/planning/original-poc-acceptance-criteria.md        the criteria and the traceability
 *   docs/planning/azure-local-platform-boundary-research.md   the findings, with Learn citations
 *   docs/planning/omitted-elements-and-technology-equivalents.md
 *   docs/planning/poc-requirements-gap-audit.md
 */

const CRIT = (function () {
  'use strict';

  const GLYPH = { done: 'v', bound: '~', find: '=', defer: '-' };

  // Ordered by the movement that completes an item, not the one that first touches it, so the
  // list only ever travels forward. Scale Sets completes beside Availability Sets, because the two
  // are the same finding: an Azure resource that does not exist here, and an outcome that does.
  const ITEMS = [
    { t: 'Fact finding with the network and datacenter roles', m: 'done', s: [0] },
    { t: 'Six node deployment target', m: 'bound', s: [1],
      n: 'four by scope decision, 03 and 05 out' },
    { t: 'Three or more Azure Local nodes', m: 'done', s: [2] },
    { t: 'Subscription, resource groups, security', m: 'done', s: [2] },
    { t: 'Kubernetes container cluster', m: 'done', s: [3] },
    { t: 'Azure integrated load balancer', m: 'bound', s: [4],
      n: 'internal Service proven. An external VIP needs a subscription action we chose not to request' },
    { t: 'Auto-scale on demand', m: 'defer', s: [4],
      n: 'AKS Arc supports it. Metrics Server was never installed, so manual scale is what was proven' },
  { t: 'Automated and scripted VM deployment', m: 'done', s: [5] },
    { t: 'Manual IaaS VM deployment', m: 'done', s: [5] },
    { t: 'Docker container workloads', m: 'done', s: [6] },
    { t: 'Corporate network VM connectivity', m: 'done', s: [6] },
    { t: 'VM Availability Sets', m: 'find', s: [7, 8],
      n: ['update domains proven by the cluster itself',
          'update and fault domains proven by the cluster itself'] },
    { t: 'VM Scale Sets', m: 'find', s: [4, 7, 8],
      n: ['instances scaled from one model, 2 to 3 to 2',
          'the whole set replaced without losing an endpoint',
          'no VMSS resource on Azure Local. A Deployment is the shape that does it'] },
    { t: 'Azure DevOps pipelines and hybrid workers', m: 'done', s: [10],
      n: 'GitHub Actions validation authored, and the five places Azure Local changes a pipeline documented' },
    { t: 'Azure database software as a service', m: 'defer', s: [10],
      n: 'no workload chosen, and the managed option needs 16 GB free on Kubernetes against about four' },
    { t: 'Azure Storage Services', m: 'defer', s: [10],
      n: 'S2D is block storage, not blob, queue or table' },
    { t: 'Threat model', m: 'bound', s: [10],
      n: 'boundaries documented, formal artifact pending' },
    { t: 'Demo of findings', m: 'done', s: [10] }
  ];

  let dom = null;
  let rows = [];
  let timers = [];
  let last = -1;

  function el(id) { return document.getElementById(id); }

  function build() {
    if (dom) return true;
    dom = { list: el('ac'), meta: el('acMeta') };
    if (!dom.list) { dom = null; return false; }

    dom.list.innerHTML = '';
    dom.meta.textContent = ITEMS.length + ' Goals';
    rows = ITEMS.map((it) => {
      const li = document.createElement('li');
      li.className = 'ac-row pending m-' + it.m;
      li.innerHTML =
        '<span class="ac-box"><span class="ac-mark"></span></span>' +
        '<span class="ac-txt"><span class="ac-t"></span><span class="ac-n"></span></span>';
      li.querySelector('.ac-mark').textContent = GLYPH[it.m];
      li.querySelector('.ac-t').textContent = it.t;
      dom.list.appendChild(li);
      return li;
    });
    return true;
  }

  function clear() {
    timers.forEach(window.clearTimeout);
    timers = [];
  }

  function noteFor(it, reached) {
    if (!it.n) return '';
    if (Array.isArray(it.n)) return it.n[Math.min(reached, it.n.length) - 1] || '';
    return it.n;
  }

  function show(stage) {
    if (!build()) return;
    const moved = stage !== last;
    if (moved) clear();

    let landing = [];

    ITEMS.forEach((it, i) => {
      const row = rows[i];
      const reached = it.s.filter((n) => n <= stage).length;
      const complete = reached === it.s.length;

      row.classList.toggle('pending', reached === 0);
      row.classList.toggle('part', reached > 0 && !complete);
      row.classList.toggle('done', complete);
      row.classList.toggle('active', it.s.indexOf(stage) !== -1);
      row.querySelector('.ac-n').textContent = reached ? noteFor(it, reached) : '';

      if (moved && it.s.indexOf(stage) !== -1) landing.push(row);
    });

    // The mark is the last beat of the movement, not part of arriving at it. Held back so the
    // diagram gets to settle first, then staggered so several landing at once reads as a
    // sequence rather than a flash. Scale and opacity only, so it survives a remote session.
    if (moved) {
      landing.forEach((row, k) => {
        timers.push(window.setTimeout(() => {
          row.classList.add('just');
          timers.push(window.setTimeout(() => row.classList.remove('just'), 1400));
        }, 1100 + k * 260));
      });
    }

    last = stage;
  }

  return { show, count: () => ITEMS.length };
})();

window.CRIT = CRIT;
