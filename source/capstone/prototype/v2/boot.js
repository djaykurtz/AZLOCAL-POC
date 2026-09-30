/*
 * Start gate for v2.
 *
 * The console renders underneath this overlay on load, so lifting the gate reveals movement 00
 * already in place. If the intro is chosen it plays first, and its closing act hands over to the
 * same movement. Chaos, then the starting line, then four machines available to build on.
 *
 * The intro is opt out rather than opt in, because it is the answer to the question the room
 * always asks, which is why any of this took as long as it did.
 */

(function () {
  'use strict';

  const gate = document.getElementById('gate');
  const go = document.getElementById('gateGo');
  const opt = document.getElementById('gateIntro');

  function lift() {
    gate.classList.add('off');
    window.setTimeout(() => { gate.hidden = true; }, 520);
  }

  function start() {
    // intro.js declares INTRO with const, so it is a lexical global rather than a window property.
    const hasIntro = typeof INTRO !== 'undefined';

    // Arming is deferred so the evidence terminal does not type behind the title sequence.
    const begin = () => {
      window.M.go(0);
      if (window.EVIDENCE) window.EVIDENCE.arm(0);
    };

    if (opt.checked && hasIntro) {
      // Both overlays fade, so lifting the gate and fading the intro up together would show the
      // console between them. Snap the intro to full opacity first, then fade the gate over it.
      const introEl = document.getElementById('intro');
      introEl.classList.add('instant');
      INTRO.play(begin);
      void introEl.offsetHeight;
      introEl.classList.remove('instant');
      lift();
      return;
    }

    lift();
    begin();
  }

  go.addEventListener('click', start);

  // Enter starts without reaching for the mouse, but not while the checkbox has focus.
  document.addEventListener('keydown', function onKey(e) {
    if (gate.hidden) { document.removeEventListener('keydown', onKey); return; }
    if (e.key === 'Enter' && e.target !== opt) { e.preventDefault(); start(); }
  });

  go.focus();
}());
