#!/usr/bin/env python3
"""Assemble artifact.html (the publishable page) from index.html (the dev mock).

Keeps one copy of the drawing code: index.html is what you open locally, artifact.html
is the same script wrapped in the page the Artifact viewer expects.
"""
import pathlib

src = pathlib.Path("index.html").read_text()
js = src[src.index("<script>") + 8: src.index("</script>")]
core = js[: js.index("function init()")]

HEAD = '''<title>4sight Rear View</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
  /* One phone screen on a neutral stage. The screen owns its own colours, so this page
     commits to a single dark look rather than following the viewer's theme. */
  :root {
    --stage: #15181C;
    --stage-2: #1D2127;
    --ink: #ECEFF3;
    --ink-dim: #99A3AE;
    --accent: #F5A623;
    color-scheme: dark;
  }
  body {
    margin: 0;
    min-height: 100svh;
    box-sizing: border-box;
    background: radial-gradient(120% 90% at 50% 0%, var(--stage-2), var(--stage));
    color: var(--ink);
    font: 400 15px/1.45 ui-rounded, -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding-left: max(16px, env(safe-area-inset-left, 0px));
    padding-right: max(16px, env(safe-area-inset-right, 0px));
    padding-block: 12px;
  }
  .stage { display: grid; place-items: center; }
  /* Width-driven, so the frame can never be wider than the viewport. The height term
     only shrinks it further when the window is short. */
  canvas {
    display: block;
    width: min(100%, calc((100svh - 292px) * 393 / 852));
    height: auto;
    max-width: 100%;
    aspect-ratio: 393 / 852;
    border-radius: 24px;
    box-shadow: 0 18px 48px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.07);
  }
  .controls { display: flex; flex-direction: column; gap: 9px; }
  .row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; min-width: 0; }
  button {
    font: inherit; font-size: 13px; color: var(--ink);
    background: rgba(255,255,255,.07); border: 1px solid rgba(255,255,255,.1);
    border-radius: 999px; padding: 7px 13px; cursor: pointer; min-height: 36px;
  }
  button[aria-pressed="true"] {
    background: var(--accent); border-color: var(--accent); color: #17191C; font-weight: 600;
  }
  button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  input[type=range] { flex: 1 1 140px; min-width: 0; accent-color: var(--accent); height: 36px; }
  .caption { color: var(--ink-dim); font-size: 12.5px; margin: 0; }
  .t {
    font-variant-numeric: tabular-nums; color: var(--ink-dim);
    font-size: 12.5px; min-width: 46px; text-align: right;
  }
</style>'''

BODY = '''<div class="stage">
  <canvas id="screen" width="786" height="1704" aria-label="4sight front phone screen"></canvas>
</div>
<div class="controls">
  <div class="row">
    <button id="play" aria-pressed="true">Pause</button>
    <input id="scrub" type="range" min="0" max="21" step="0.05" value="5.3" aria-label="Scenario time">
    <button id="demo" aria-pressed="false" title="FrameMessage.demo: bicycles and people count as threats">Demo mode</button>
    <span class="t" id="clock">4.5s</span>
  </div>
  <div class="row" id="marks"></div>
  <p class="caption">Cyclists and pedestrians are drawn grey: the engine only treats them as threats in demo mode. Turn on Demo mode to see the overtaking cyclist and the person stepping out of a parked car raise alerts.</p>
</div>'''

INIT = '''
const MARKS = [
  ['level 3', 5.2], ['cyclist', 11], ['right hook', 12.5], ['pedestrians', 14.6],
  ['turn ahead', 18.5], ['straight behind', 20.5],
];

function init() {
  const canvas = document.getElementById('screen');
  const ctx = canvas.getContext('2d');
  ctx.scale(canvas.width / W, canvas.height / H);
  window.__ctx = ctx;

  const scrub = document.getElementById('scrub');
  const clock = document.getElementById('clock');
  const play = document.getElementById('play');
  const marks = document.getElementById('marks');

  let playing = true;
  let t = parseFloat(scrub.value);
  let last = performance.now();

  function show(next) {
    t = (next + LOOP) % LOOP;
    scrub.value = t.toFixed(2);
    clock.textContent = t.toFixed(1) + 's';
    draw(t);
    for (const b of marks.children) b.setAttribute('aria-pressed', String(Math.abs(t - b.__t) < 0.3));
  }
  function setPlaying(on) {
    playing = on;
    play.textContent = on ? 'Pause' : 'Play';
    play.setAttribute('aria-pressed', String(on));
  }

  for (const [label, at] of MARKS) {
    const b = document.createElement('button');
    b.textContent = label;
    b.__t = at;
    b.setAttribute('aria-pressed', 'false');
    b.addEventListener('click', () => { setPlaying(false); show(at); });
    marks.appendChild(b);
  }
  scrub.addEventListener('input', () => { setPlaying(false); show(parseFloat(scrub.value)); });
  play.addEventListener('click', () => { last = performance.now(); setPlaying(!playing); });
  const demo = document.getElementById('demo');
  demo.addEventListener('click', () => {
    DEMO = !DEMO;
    demo.setAttribute('aria-pressed', String(DEMO));
    show(t);
  });

  const params = new URLSearchParams(location.search);
  if (params.has('t')) { setPlaying(false); show(parseFloat(params.get('t'))); window.__ready = true; }
  else show(t);

  (function loop(now) {
    const dt = (now - last) / 1000;
    last = now;
    if (playing) show(t + dt);
    requestAnimationFrame(loop);
  })(performance.now());
}
init();
'''

pathlib.Path("artifact.html").write_text(HEAD + "\n" + BODY + "\n<script>\n" + core + INIT + "\n</script>\n")
print("wrote artifact.html")
