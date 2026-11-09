import { listen } from "@tauri-apps/api/event";
import { renderer } from "./render";
import { defaults } from "./domain";
document.body.innerHTML =
  '<main class="stage desktop-mode"><canvas id="waves"></canvas><div id="clock" class="clock"></div><div id="graph" class="graph"></div><div id="plain-text" class="plain-display"></div></main>';
const visual = renderer(
  document.querySelector("#waves"),
  document.querySelector("#graph"),
  document.querySelector("#clock"),
);
let state = {
    settings: { ...defaults, color: defaults.tint },
    line: { words: [], active: -1, index: -1 },
    playing: false,
    audio: { level: 0, bands: [] },
  },
  received = 0,
  last = 0;
await listen("display-state", (event) => {
  state = {
    ...event.payload,
    settings: { ...state.settings, ...event.payload.settings },
  };
  received = performance.now();
  document.querySelector("#plain-text").textContent = state.plainText || "";
});
function draw(now) {
  requestAnimationFrame(draw);
  if (now - last < 33) return;
  last = now;
  visual.draw(now, {
    ...state,
    playing: state.playing && now - received < 3000,
  });
}
requestAnimationFrame(draw);
