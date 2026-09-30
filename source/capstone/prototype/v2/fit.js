/*
 * The deck is a fixed 1536 by 864 canvas, scaled to fit whatever window it lands in.
 *
 * Teams pipes the audience a video of whatever the presenter shares, so nobody downstream ever
 * sees a different aspect ratio, only a different resolution. That makes one composition scaled
 * to fit the correct mechanism and fluid reflow the wrong one. Nothing moves relative to anything
 * else, a browser toolbar appearing changes the scale factor rather than the layout, and every
 * fixed pixel size in the stylesheets becomes correct again because the canvas never changes.
 *
 * The catch: getBoundingClientRect reports post-transform pixels while style.left is written in
 * pre-transform ones. Anything that measures an element and then positions something against it
 * has to go through rect(), which returns stage space so both ends agree.
 */
const FIT = (function () {
  'use strict';

  const W = 1536;
  const H = 864;

  let stage = null;
  let s = 1;

  function apply() {
    if (!stage) stage = document.getElementById('stage');
    if (!stage) return;
    s = Math.min(window.innerWidth / W, window.innerHeight / H);
    // Scale first, so the -50% pullback resolves in scaled pixels and the bars come out even.
    stage.style.transform = 'scale(' + s + ') translate(-50%, -50%)';
    api.s = s;
  }

  function rect(el) {
    if (!stage) stage = document.getElementById('stage');
    const r = el.getBoundingClientRect();
    if (!stage) return r;
    const o = stage.getBoundingClientRect();
    return {
      left: (r.left - o.left) / s,
      top: (r.top - o.top) / s,
      right: (r.right - o.left) / s,
      bottom: (r.bottom - o.top) / s,
      width: r.width / s,
      height: r.height / s
    };
  }

  const api = { W: W, H: H, s: 1, rect: rect, apply: apply };

  // window.resize alone is not enough. An iframe or an embedded viewer can change the painted
  // area without firing it, which would strand the stage at a scale for a window that is gone.
  window.addEventListener('resize', apply);
  window.addEventListener('orientationchange', apply);
  document.addEventListener('DOMContentLoaded', apply);
  window.addEventListener('load', apply);
  window.addEventListener('pageshow', apply);
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', apply);
  }
  if (window.ResizeObserver) {
    new ResizeObserver(apply).observe(document.documentElement);
  }
  apply();

  return api;
})();

window.FIT = FIT;
