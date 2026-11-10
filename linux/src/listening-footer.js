import { timeLabel } from "./domain.js";

export function listeningFooter({ interactive = true } = {}) {
  return `<section class="now-playing" aria-label="Now playing" hidden><div class="track-meta"><h2 id="title"></h2><p id="artist"></p></div><div class="track-progress"><span id="time">0:00</span>${interactive ? '<input id="seek" aria-label="Playback position" type="range" min="0" max="100" step=".1" value="0">' : '<div id="seek" class="progress-track" role="progressbar" aria-label="Playback position" aria-valuemin="0"><span></span></div>'}<span id="duration">0:00</span></div></section>`;
}
export function updateFooter(root, track, position = 0) {
  const footer = root.querySelector(".now-playing");
  if (!footer) return;
  footer.hidden = !track;
  if (!track) return;
  for (const [id, text] of [["title", track.title], ["artist", track.artist], ["time", timeLabel(position)], ["duration", timeLabel(track.duration || 0)]]) {
    const node = root.querySelector("#" + id);
    if (node.textContent !== (text || "")) node.textContent = text || "";
    if (id === "title" || id === "artist") node.title = text || "";
  }
  const seek = root.querySelector("#seek"), duration = Math.max(0, track.duration || 0);
  const progress = duration ? Math.min(1, Math.max(0, position / duration)) : 0;
  seek.style.setProperty("--progress", `${progress * 100}%`);
  if (seek.tagName === "INPUT") {
    seek.max = duration || 1;
    if (root.activeElement !== seek) seek.value = position;
    seek.disabled = !track.canSeek;
  } else {
    seek.setAttribute("aria-valuemax", String(duration));
    seek.setAttribute("aria-valuenow", String(Math.min(duration, Math.max(0, position))));
    seek.setAttribute("aria-valuetext", `${timeLabel(position)} of ${timeLabel(duration)}`);
  }
}
