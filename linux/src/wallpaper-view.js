import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { renderer } from "./render";
import { listeningFooter, updateFooter } from "./listening-footer";
import { createDesktopState } from "./desktop-state";

document.body.classList.add("desktop-mode");
document.body.innerHTML = `<main class="stage"><canvas id="waves" aria-hidden="true"></canvas><div id="clock" class="clock"></div><div id="graph" class="graph" role="img"></div>${listeningFooter({ interactive: false })}</main>`;
const visual = renderer(document.querySelector("#waves"), document.querySelector("#graph"), document.querySelector("#clock"));
const timeline = createDesktopState();
let timer = 0, frame = 0, lastDraw = -Infinity, dirty = true;
function wake() {
  dirty = true;
  clearTimeout(timer); cancelAnimationFrame(frame);
  frame = requestAnimationFrame(draw);
}
await listen("display-state", (event) => { timeline.receive(event.payload, performance.now()); wake(); });
await listen("audio-frame", (event) => timeline.audio(event.payload, performance.now()));
await listen("audio-ended", () => { timeline.receive({ audioActive: false }, performance.now()); wake(); });
await listen("power-state", (event) => { timeline.power(event.payload, performance.now()); wake(); });
new ResizeObserver(wake).observe(document.documentElement);
// Listeners are installed before requesting the complete cached state (including wallpaper).
await invoke("wallpaper_ready");
function draw(now) {
  const state = timeline.frame(now);
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const animated = state.playing && state.settings.motion && !reduced;
  const interval = animated ? (state.onBattery ? 50 : 1000 / 30) : state.playing ? 100 : 1000;
  if (!state.sleeping && (now - lastDraw >= interval || (dirty && !state.playing))) {
    visual.draw(now, state);
    updateFooter(document, state.track, state.position);
    lastDraw = now; dirty = false;
  }
  timer = setTimeout(() => { frame = requestAnimationFrame(draw); }, animated ? 0 : interval);
}
wake();
