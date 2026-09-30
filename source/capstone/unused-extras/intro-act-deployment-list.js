/*
 * CUT: intro act "Then the deployment ran its own list".
 *
 * What it was
 *   An act between the SConfig update trap and the drives act. It rendered all 54 deployment
 *   steps as a scrolling list, seven of them named and the rest as redacted bars, ticking to
 *   54 of 54 over fifteen seconds while the narration made the point that the prechecks pass
 *   and do not cover most of that list.
 *
 * Why it went
 *   Movement 02.5 in the main deck already covers the deployment run against real evidence, so
 *   the intro was spending forty seconds setting up something the deck then proves properly.
 *   The intro was also running long, and this was the act that earned its place least.
 *
 * What it needs to come back
 *   The NAMED_STEPS map below, the .iscroll / .istep CSS which is still in v2/intro.css, an
 *   entry in the ACTS array, and a slate renumber. It depends on mk(), field(), pair(), at(),
 *   slate(), clearField(), OPEN, CYCLE and clockId from intro.js, so it has to live inside that
 *   module rather than beside it.
 */

// Only the steps worth stopping on. Naming the obvious ones flattens the joke, and most of the
// 54 step names were never recorded anyway, so the rest render as redacted bars.
const NAMED_STEPS = {
  16: 'Create cluster',
  17: 'Configure networking',
  24: 'Enable BitLocker on cluster shared volumes',
  32: 'Reserve Arc infrastructure addresses',
  40: 'Deploy Arc infrastructure',
  47: 'Register custom location',
  52: 'Finalize security settings'
};

function actSteps() {
  clearField();
  slate('Act four', 'Then the deployment ran its own list');

  const scroll = mk('iscroll');
  scroll.innerHTML =
    '<div class="iscroll-head"><span class="iscroll-cap">Deployment steps</span>' +
    '<span class="iscroll-count" id="introCount">0 / 54</span></div>' +
    '<div class="iscroll-view"><div class="iscroll-list" id="introList"></div></div>';
  field().appendChild(scroll);

  const list = scroll.querySelector('#introList');
  const count = scroll.querySelector('#introCount');

  for (let i = 1; i <= 54; i += 1) {
    const row = mk('istep');
    const label = NAMED_STEPS[i];
    row.innerHTML =
      '<span class="istep-n">' + String(i).padStart(2, '0') + '</span>' +
      (label
        ? '<span class="istep-name"></span>'
        : '<span class="istep-redact" style="width:' + (34 + ((i * 37) % 46)) + '%"></span>');
    if (label) row.querySelector('.istep-name').textContent = label;
    list.appendChild(row);
  }

  at(OPEN, () => {
    const rows = list.children;
    const total = 15000;
    const started = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - started) / total);
      const eased = t < 0.82 ? t / 0.82 : 1;
      const idx = Math.round(eased * 54);
      count.textContent = idx + ' / 54';
      list.style.transform = 'translateY(' + -Math.max(0, (idx - 7) * 30) + 'px)';
      for (let i = 0; i < idx && i < rows.length; i += 1) rows[i].classList.add('done');
      if (t < 1) clockId = window.requestAnimationFrame(step);
    };
    clockId = window.requestAnimationFrame(step);
  });

  pair(OPEN,
    'With the machines finally acceptable, we started the deployment.',
    'Fifty four steps.');

  pair(OPEN + CYCLE,
    'Most of them you never look at.',
    'Until one of them stops.', 'turn');

  pair(OPEN + CYCLE * 2,
    'The prechecks had passed. The prechecks do not cover most of this list.',
    'And nothing here arrives in parallel.', 'turn');

  pair(OPEN + CYCLE * 3,
    'Fix one, run it again, wait, and meet the next one.',
    'That is what two months actually looks like.');
}

// ACTS entry it had:
//   { name: 'The list', run: actSteps, dur: 22500 }
