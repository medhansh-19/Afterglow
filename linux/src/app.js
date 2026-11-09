import "./style.css";
import { call, native, saveImage, isWindows, platformName } from "./bridge";
import {
  defaults,
  newLibrary,
  readLibrary,
  recordingKey,
  positionAt,
  resolveLine,
  appearance,
  colorCollection,
  collectionName,
  snapshotAppearance,
  excerptText,
  escape as e,
  timeLabel,
} from "./domain";
import { renderer } from "./render";
import { CLOCK_STYLES } from "./clock-preview";

const $ = (s) => document.querySelector(s);
const transportIcons = {
  play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 5 11 7-11 7z"/></svg>',
  pause:
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 5h4v14H6zm8 0h4v14h-4z"/></svg>',
  previous:
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 5h3v14H5zm14 0L9 12l10 7z"/></svg>',
  next: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 5h3v14h-3zM5 5v14l10-7z"/></svg>',
  stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6h12v12H6z"/></svg>',
};
let lastPublish = 0,
  lastWallpaper = "",
  onBattery = false,
  sleeping = false,
  revision = 0,
  lastRender = "";
$("#app").innerHTML =
  `<main class="stage"><canvas id="waves" aria-hidden="true"></canvas><header class="topbar"><span class="brand">afterglow<span>${platformName.toUpperCase()} PREVIEW</span></span><div class="top-actions"><button id="focus" title="Focus Mode (Ctrl+Shift+F)">Focus</button><button id="desktop" title="Desktop Mode (Ctrl+Shift+D)">Desktop</button><button id="controls" aria-label="Controls" aria-haspopup="dialog" title="Controls (Ctrl+K)">Controls <span>⌃K</span></button></div></header><div id="clock" class="clock"></div><div id="graph" class="graph" role="img"></div><div id="plain-text" class="plain-display"></div><section id="welcome" class="welcome"><span class="eyebrow">YOUR MUSIC, IN A DIFFERENT LIGHT</span><h1>Put on a song.<br><em>Stay a little longer.</em></h1><p>Connect a music player to bring its words,<br>colors and movement into the room.</p><div class="welcome-actions"><button class="primary" id="connect">Connect a player</button><button id="demo">Try the silent demo</button></div><p class="preview-note">${native ? (isWindows ? "Spotify, Apple Music and Windows media players · Audio stays on this computer" : "Spotify and other MPRIS players · Audio stays on this computer") : `Browser preview · Install the ${platformName} app to connect your music`}</p></section><section class="now-playing" hidden><div class="track-meta"><img id="artwork" alt="" hidden><div><h2 id="title"></h2><p id="artist"></p></div><button id="save-song" title="Save song to a collection">♡</button></div><div class="transport"><button data-transport="previous" aria-label="Previous track">${transportIcons.previous}</button><button data-transport="toggle" id="play" aria-label="Play or pause">${transportIcons.play}</button><button data-transport="next" aria-label="Next track">${transportIcons.next}</button><button data-transport="stop" aria-label="Stop playback">${transportIcons.stop}</button><span id="time">0:00</span><input id="seek" aria-label="Playback position" type="range" min="0" max="100" step=".1"><span id="duration">0:00</span></div><div class="track-detail"><span id="lyric-source" hidden></span><span id="beat-state">Beat sync off</span></div></section><div id="notice" class="notice" role="status" hidden></div><button id="exit-focus" hidden>Exit Focus · Esc</button></main><dialog id="panel" aria-labelledby="panel-title"><header class="panel-header"><div><span class="eyebrow">AFTERGLOW</span><h2 id="panel-title">Controls</h2></div><button id="close-panel" aria-label="Close controls">✕</button></header><nav class="tabs" aria-label="Controls"><button data-tab="player">Player</button><button data-tab="appearance">Appearance</button><button data-tab="lyrics">Lyrics</button><button data-tab="collections">Collections</button><button data-tab="cards">Lyric cards</button><button data-tab="audio">Beat sync</button><button data-tab="help">Help</button></nav><div id="panel-body"></div></dialog><input type="file" id="import-file" accept=".lrc,.txt,.yaml,.yml" hidden><input type="file" id="wallpaper-file" accept="image/png,image/jpeg,image/webp" hidden>`;
let library = newLibrary(),
  persistenceReady = false,
  saveTimer,
  saveQueue = Promise.resolve(),
  track = null,
  documentLyrics = null,
  sample = null,
  selectedBus = null,
  selectionGeneration = 0,
  lyricGeneration = 0,
  artworkGeneration = 0,
  demo = false,
  demoStart = 0,
  key = "",
  lastLine = { index: -1, words: [], active: -1 },
  audio = { level: 0, bands: [] },
  audioIndex = null,
  captureActive = false,
  capturePending = false,
  focused = false,
  desktop = false,
  panelTab = "player",
  draft = {},
  albumColor = null,
  lastDraw = 0,
  lastPoll = 0,
  polling = false,
  cardSelection = new Set(),
  selectedExcerpt = null;
const visual = renderer($("#waves"), $("#graph"), $("#clock"));
let scheduledTimer = 0,
  scheduledFrame = 0;
function wake() {
  clearTimeout(scheduledTimer);
  cancelAnimationFrame(scheduledFrame);
  lastDraw = 0;
  if (desktop) scheduledTimer = setTimeout(() => tick(performance.now()), 0);
  else scheduledFrame = requestAnimationFrame(tick);
}

async function confirmDeletion(name) {
  const dialog = document.createElement("dialog");
  dialog.setAttribute("aria-labelledby", "delete-title");
  dialog.innerHTML = `<h2 id="delete-title">Delete ${e(name)}?</h2><p>This removes the collection and its saved memberships. Other collections and music remain available.</p><div class="button-row"><button id="cancel-delete" autofocus>Cancel</button><button id="confirm-delete">Delete collection</button></div>`;
  document.body.append(dialog);
  const trigger = document.activeElement;
  return new Promise((resolve) => {
    let confirmed = false;
    dialog.querySelector("#cancel-delete").onclick = () => dialog.close();
    dialog.querySelector("#confirm-delete").onclick = () => { confirmed = true; dialog.close(); };
    dialog.addEventListener("close", () => { dialog.remove(); trigger?.focus(); resolve(confirmed); }, { once: true });
    dialog.showModal();
  });
}
function notice(text) {
  $("#notice").textContent = String(text);
  $("#notice").hidden = !text;
}
function report(error) {
  if (native)
    call("client_error", {
      message: error instanceof Error ? error.message : String(error),
    }).catch(() => {});
  notice(error instanceof Error ? error.message : String(error));
}
function persist() {
  revision++;
  wake();
  if (!persistenceReady) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const snapshot = structuredClone(library);
    saveQueue = saveQueue
      .catch(() => {})
      .then(() => call("save_library", { library: snapshot }))
      .catch((err) => report(`Changes could not be saved: ${err}`));
  }, 200);
}
function effective() {
  const value = { ...appearance(library, key, albumColor), ...draft };
  const collection = colorCollection(library, key);
  value.color =
    collection?.color ||
    (value.albumColor && albumColor ? albumColor : value.tint);
  if (!/^#[0-9a-f]{6}$/i.test(value.color)) value.color = defaults.tint;
  return value;
}
async function load() {
  try {
    library = readLibrary(await call("load_library"));
    persistenceReady = true;
    selectedBus = library.playerBus;
  } catch (err) {
    report(
      `Your saved library could not be loaded. Its original file has been preserved. ${err}`,
    );
  }
  await refreshPlayers();
}
function trackUI() {
  wake();
  const connected = !!track;
  $("#welcome").hidden = connected;
  $(".now-playing").hidden = !connected;
  $("#title").textContent = track?.title || "No track";
  $("#artist").textContent = track?.artist || "";
  $("#duration").textContent = timeLabel(track?.duration || 0);
  $("#seek").max = track?.duration || 1;
  $("#seek").disabled = !demo && !track?.canSeek;
  $("#play").innerHTML = sample?.playing
    ? transportIcons.pause
    : transportIcons.play;
  $("#play").setAttribute("aria-label", sample?.playing ? "Pause" : "Play");
  document
    .querySelectorAll("[data-transport]")
    .forEach(
      (button) =>
        (button.disabled =
          demo && ["next", "previous"].includes(button.dataset.transport)),
    );
  $("#save-song").textContent = library.collections.some((c) =>
    c.songs?.some((s) => s.key === key),
  )
    ? "♥"
    : "♡";
}
async function selectTrack(next) {
  if (track?.bus !== next?.bus) audioIndex = null;
  const nextKey = next ? recordingKey(next) : "";
  const changed = nextKey !== key;
  track = next;
  sample = next ? { ...next, received: performance.now() } : null;
  if (changed) {
    revision++;
    artworkGeneration++;
    key = nextKey;
    draft = {};
    documentLyrics = null;
    lastLine = { index: -1, words: [], active: -1 };
    albumColor = null;
    $("#artwork").hidden = true;
    cardSelection.clear();
    selectedExcerpt = null;
    await stopCapture();
    if (next) {
      fetchArtwork(next);
      loadLyrics();
    }
  }
  trackUI();
  syncCapture();
}
async function fetchArtwork(next) {
  const generation = ++artworkGeneration;
  if (demo) return;
  try {
    const uri = await call("artwork", { bus: next.bus });
    if (generation !== artworkGeneration || track?.bus !== next.bus) return;
    if (!uri) return;
    const image = new Image();
    image.onload = () => {
      if (generation !== artworkGeneration) return;
      $("#artwork").src = uri;
      $("#artwork").hidden = false;
      const canvas = document.createElement("canvas");
      canvas.width = 32;
      canvas.height = 32;
      const ctx = canvas.getContext("2d");
      ctx.drawImage(image, 0, 0, 32, 32);
      const bytes = ctx.getImageData(0, 0, 32, 32).data;
      let best = null,
        score = 0;
      for (let i = 0; i < bytes.length; i += 4) {
        const r = bytes[i],
          g = bytes[i + 1],
          b = bytes[i + 2],
          max = Math.max(r, g, b),
          min = Math.min(r, g, b),
          s = (max - min) * (max > 45 && max < 245 ? 1 : 0);
        if (s > score) {
          score = s;
          const boost = Math.max(1, 220 / Math.max(1, max));
          best = [r, g, b]
            .map((c) => Math.min(255, Math.round(c * boost)))
            .map((c) => c.toString(16).padStart(2, "0"))
            .join("");
        }
      }
      albumColor = best ? "#" + best : null;
    };
    image.src = uri;
  } catch {
    /* Missing artwork keeps the selected custom accent. */
  }
}
async function loadLyrics(bypassCache = false) {
  if (!track) return;
  const generation = ++lyricGeneration,
    currentKey = key;
  $("#lyric-source").textContent = "Finding lyrics…";
  try {
    let response;
    if (library.imports[currentKey])
      response = { document: library.imports[currentKey] };
    else
      response = await call("lyrics", {
        request: demo
          ? { command: "demo" }
          : {
              command: "resolve",
              track: {
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
              },
              allowPlainFallback: library.settings.allowPlainFallback,
              allowTimedFallback: library.settings.allowTimedFallback,
              bypassCache,
            },
      });
    if (generation !== lyricGeneration || currentKey !== key) return;
    if (response.error) throw Error(response.error);
    documentLyrics = response.document;
    revision++;
    wake();
    $("#lyric-source").textContent = documentLyrics
      ? documentLyrics.instrumental
        ? "Instrumental"
        : `${documentLyrics.source === "local" ? "Imported lyrics" : documentLyrics.source}${documentLyrics.retrievedFromCache ? " · Cached" : ""}${documentLyrics.automaticMatch ? " · Nearby recording" : ""}${documentLyrics.lines?.some((l) => l.words?.length) ? " · Word timed" : documentLyrics.lines?.length ? " · Line timed" : " · Untimed text"}`
      : "No lyrics found · Import your own in Controls";
    if ($("#panel").open && panelTab === "lyrics") renderPanel();
  } catch (err) {
    if (generation === lyricGeneration) {
      $("#lyric-source").textContent = "Lyrics unavailable · Retry in Controls";
      report(err);
    }
  }
}
async function refreshPlayers() {
  if (polling || demo || selectedBus === "") return;
  polling = true;
  const generation = selectionGeneration,
    started = performance.now();
  try {
    const players = await call("players", { selected: selectedBus });
    if (generation !== selectionGeneration) return;
    const chosen =
      players.find((p) => p.bus === selectedBus) ||
      (!selectedBus ? players.find((p) => p.playing) || players[0] : null);
    if (chosen) {
      if (selectedBus == null) {
        selectedBus = chosen.bus;
        library.playerBus = selectedBus;
        persist();
      }
      chosen.received = started;
      await selectTrack(chosen);
      sample.received = started;
    } else if (track && !demo) {
      await selectTrack(null);
      notice(
        selectedBus
          ? "Your player disconnected. Reopen it or choose another player in Controls."
          : "Start music in a compatible player, then connect it in Controls.",
      );
    }
  } catch (err) {
    if (generation === selectionGeneration && !track) report(err);
  } finally {
    polling = false;
  }
}
async function startDemo() {
  selectionGeneration++;
  demo = true;
  selectedBus = null;
  demoStart = performance.now();
  await selectTrack({
    bus: "demo",
    identity: "Silent demo",
    title: "Afterglow",
    artist: "Original silent demonstration",
    album: "Afterglow",
    duration: 120,
    position: 0,
    playing: true,
    rate: 1,
    canSeek: true,
  });
  notice("Silent demo · Timing is synthetic. No music or audio capture.");
}
async function transport(action, position) {
  if (!track) return;
  try {
    if (demo) {
      const p = positionAt(sample, performance.now());
      sample = {
        ...sample,
        position: action === "seek" ? position : action === "stop" ? 0 : p,
        playing:
          action === "toggle"
            ? !sample.playing
            : action === "stop"
              ? false
              : sample.playing,
        received: performance.now(),
      };
      trackUI();
      syncCapture();
      return;
    }
    await call("transport", {
      bus: track.bus,
      action,
      position: position ?? null,
    });
    await refreshPlayers();
  } catch (err) {
    report(err);
  }
}
async function stopCapture() {
  captureActive = false;
  await call("audio_stop").catch(report);
  audio = { level: 0, bands: [] };
}
async function syncCapture() {
  const should =
    !sleeping &&
    audioIndex != null &&
    !demo &&
    !!sample?.playing &&
    (desktop || !document.hidden) &&
    !$("#panel").open;
  if (!should) {
    if (captureActive) await stopCapture();
    return;
  }
  if (captureActive || capturePending) return;
  capturePending = true;
  try {
    await call("audio_start", { index: audioIndex });
    captureActive = true;
    if (
      !sample?.playing ||
      (!desktop && document.hidden) ||
      $("#panel").open ||
      audioIndex == null
    )
      await stopCapture();
    else $("#beat-state").textContent = "Beat sync · Selected audio stream";
  } catch (err) {
    audioIndex = null;
    report(err);
    $("#beat-state").textContent = "Beat sync unavailable";
  } finally {
    capturePending = false;
  }
}
async function toggleFocus() {
  try {
    if (native) {
      const { getCurrentWindow } = await import("@tauri-apps/api/window");
      await getCurrentWindow().setFullscreen(!focused);
    }
    focused = !focused;
    document.body.classList.toggle("focus-mode", focused);
    $("#exit-focus").hidden = !focused;
  } catch (err) {
    report(err);
  }
}
async function toggleDesktop() {
  try {
    lastWallpaper = "";
    await call("desktop_mode", { enabled: !desktop });
    desktop = !desktop;
    wake();
    document.body.classList.toggle("desktop-mode", desktop);
    $("#desktop").textContent = desktop ? "Return to window" : "Desktop";
    notice(
      desktop
        ? "Desktop mode · Use the tray menu to return to the window."
        : "",
    );
  } catch (err) {
    report(err);
  }
}
function openPanel(tab = "player") {
  panelTab = tab;
  renderPanel();
  if (!$("#panel").open) $("#panel").showModal();
  syncCapture();
}
function option(value, current, label = value) {
  return `<option value="${e(value)}" ${value === current ? "selected" : ""}>${e(label)}</option>`;
}
function toggle(name, label, value) {
  return `<label class="toggle"><span>${label}</span><input data-setting="${name}" type="checkbox" ${value ? "checked" : ""}></label>`;
}
function select(name, label, values, current) {
  return `<label>${label}<select data-setting="${name}">${values.map((v) => option(v, current)).join("")}</select></label>`;
}
function renderPanel() {
  const s = effective();
  $(".tabs")
    .querySelectorAll("button")
    .forEach((b) =>
      b.setAttribute(
        "aria-current",
        b.dataset.tab === panelTab ? "page" : "false",
      ),
    );
  const sections = {
    player: () =>
      `<h3>Your music player</h3><p>Open your player and start a song. Afterglow reads its ${isWindows ? "Windows media-session" : "MPRIS"} playback information locally.</p><div id="players-list" class="list">Finding players…</div><div class="button-row"><button id="refresh-players">Refresh players</button><button id="try-demo">Try silent demo</button>${track ? '<button id="disconnect">Disconnect</button>' : ""}</div>`,
    appearance: () =>
      `<h3>Appearance & wallpaper</h3><div class="form-grid"><label>Lyric color<input type="color" data-setting="tint" value="${e(s.tint)}"></label>${toggle("albumColor", "Use album colors", s.albumColor)}${select("marker", "Word marker", ["diamond", "circle", "triangle", "star", "octagon", "rectangle", "sparkle"], s.marker)}<label>Custom emoji<input data-setting="emoji" value="${e(s.emoji)}" maxlength="12"></label><label>Word size<input type="range" data-setting="fontSize" min="22" max="60" value="${s.fontSize}"></label>${toggle("motion", "Flowing animation", s.motion)}${toggle("estimatedWords", "Estimate word progression for line-timed lyrics", s.estimatedWords)}${toggle("chorusMemory", "Remember chorus arrangements", s.chorusMemory)}</div><div class="button-row"><button id="choose-wallpaper">Choose wallpaper</button><button id="clear-wallpaper">Remove wallpaper</button></div><label>Wallpaper opacity<input type="range" data-setting="opacity" min="0" max="1" step=".05" value="${s.opacity}"></label><h3>Clock</h3><div class="form-grid">${toggle("clock", "Show clock", s.clock)}<label>Clock color<input type="color" data-setting="clockColor" value="${e(s.clockColor)}"></label>${toggle("clockFollowsLyrics", "Clock follows lyric color", s.clockFollowsLyrics)}${select("clockStyle", "Clock style", CLOCK_STYLES, s.clockStyle)}${select("format", "Hour format", ["System", "12", "24"], s.format)}${toggle("seconds", "Show seconds", s.seconds)}${toggle("date", "Show date", s.date)}<label>Clock size<input type="range" data-setting="clockSize" min="70" max="140" value="${s.clockSize}"></label></div><h3>Saved scenes & colors</h3><p>Save this appearance for the current recording. Other songs use your defaults.</p><div class="button-row"><button id="save-scene" ${!track ? "disabled" : ""}>${library.scenes[key] ? "Update" : "Save"} scene for this song</button><button id="remove-scene" ${!library.scenes[key] ? "disabled" : ""}>Remove song scene</button><button id="save-color">Save this color</button></div><div class="swatches">${library.colors.map((c, i) => `<button data-color="${i}" style="--swatch:${e(c.color)}" title="${e(c.name)}">${e(c.name)}<span data-delete-color="${i}" aria-label="Delete color">×</span></button>`).join("")}</div><div class="button-row"><button id="capture-map" ${!track ? "disabled" : ""}>Export lyric map</button><button id="copy-map" ${!track ? "disabled" : ""}>Copy lyric map</button><button id="reset-appearance">Reset default appearance</button></div>`,
    lyrics: () =>
      `<h3>Lyrics & timing</h3><p>${e($("#lyric-source").textContent || "Connect a player first.")}</p><label>Adjustment: ${Number(library.timing[key] || 0).toFixed(1)} s<input type="range" id="timing" min="-5" max="5" step=".1" value="${library.timing[key] || 0}" ${!track ? "disabled" : ""}></label><p>Positive values display lyrics later. Word timestamps are preserved; estimated progression is used only when enabled.</p><div class="button-row"><button id="retry-lyrics" ${!track ? "disabled" : ""}>Retry synced lyrics</button><button id="import-lyrics" ${!track ? "disabled" : ""}>Import LRC, TXT or YAML</button><button id="remove-import" ${!library.imports[key] ? "disabled" : ""}>Remove import</button></div>${toggle("allowTimedFallback", "Use Karalyr and NetEase backups", s.allowTimedFallback)}${toggle("allowPlainFallback", "Allow untimed lyrics.ovh fallback", s.allowPlainFallback)}${documentLyrics?.alternatives?.length ? `<h3>Choose another recording</h3>${documentLyrics.alternatives.map((a, i) => `<button class="list-row" data-alternative="${i}">${e(a.title)} · ${e(a.artist)} · ${timeLabel(a.duration)}</button>`).join("")}` : ""}<div class="lyric-list">${(documentLyrics?.lines || []).map((l, i) => `<button class="lyric-row" data-line="${i}"><time>${timeLabel(l.time)}</time><span>${e(l.text || "Instrumental")}</span></button>`).join("") || `<p class="plain-lyrics">${e(documentLyrics?.plainText || "No lyrics loaded.")}</p>`}</div>`,
    collections: () =>
      `<h3>Collections & saved songs</h3><div class="inline-form"><input id="collection-name" aria-label="New collection name" placeholder="New collection name" maxlength="40"><button id="new-collection">Create collection</button></div>${
        track
          ? `<label>Lyric color from<select id="color-source">${option("", library.colorSource[key] || "", "Automatic")}${library.collections
              .filter((c) => c.songs.some((s) => s.key === key))
              .map((c) => option(c.id, library.colorSource[key], c.name))
              .join("")}</select></label>`
          : ""
      }${library.collections.map((c) => `<section class="collection" data-collection="${e(c.id)}"><div class="collection-heading"><input data-rename="${e(c.id)}" aria-label="Collection name" value="${e(c.name)}" maxlength="40"><label class="color-control">Color<input type="color" data-collection-color="${e(c.id)}" value="${c.color || "#b9a5ef"}"></label><button data-clear-collection-color="${e(c.id)}">Inherit</button><button data-add-song="${e(c.id)}" ${!track ? "disabled" : ""}>Save current song</button>${!["liked", "favorites"].includes(c.id) ? `<button data-delete-collection="${e(c.id)}" aria-label="Delete collection">×</button>` : ""}</div>${c.songs.map((song, i) => `<div class="saved-song"><span>${e(song.track.title)}<small>${e(song.track.artist)}</small></span><button data-remove-song="${e(c.id)}" data-song-index="${i}" aria-label="Remove ${e(song.track.title)}">×</button></div>`).join("") || "<p>No saved songs yet.</p>"}</section>`).join("")}`,
    cards: () =>
      `<h3>Lyric cards</h3><p>Select up to six lines and 280 characters. Cards export at 1080 × 1350.</p><div class="card-layout"><div class="lyric-list">${
        (documentLyrics?.lines || [])
          .filter((l) => l.text)
          .map((l) => {
            const i = documentLyrics.lines.indexOf(l);
            return `<label class="card-line"><input type="checkbox" data-card-line="${i}" ${cardSelection.has(i) ? "checked" : ""}>${e(l.text)}</label>`;
          })
          .join("") || "<p>Connect a song with lyrics to create a card.</p>"
      }</div><div><canvas id="card-preview" width="1080" height="1350" aria-label="Lyric card preview"></canvas><div class="button-row"><button id="save-excerpt">Save excerpt</button><button id="export-card">Export PNG</button><button id="copy-card">Copy image</button></div></div></div><h3>Saved excerpts</h3><div class="list">${library.excerpts.map((x, i) => `<div class="saved-song"><button data-excerpt="${i}">${e(x.track.title)}<small>${e(x.text)}</small></button><button data-delete-excerpt="${i}" aria-label="Delete excerpt">×</button></div>`).join("") || "<p>No saved excerpts yet.</p>"}</div>`,
    audio: () =>
      `<h3>Beat sync</h3><p>Choose the audio stream belonging to your player. Only that stream is analyzed locally. Afterglow does not capture your microphone, record audio files, or upload audio.</p><div id="audio-list" class="list">Finding audio streams…</div><div class="button-row"><button id="refresh-audio">Refresh audio streams</button><button id="stop-audio">Disable beat sync</button></div><p>Capture pauses with playback, while the app is hidden, and while controls are open. If your output device changes, select the stream again.</p>`,
    help: () =>
      `<h3>Afterglow for ${platformName}</h3><button id="enable-shortcuts">Enable global shortcuts</button>${isWindows ? '<button id="disable-shortcuts">Disable global shortcuts</button>' : ""}<p id="shortcut-status">${isWindows ? "Windows reserves Ctrl+Shift+F/D/B/A/M while Afterglow runs. A conflict is reported without replacing another app’s binding." : "Your desktop will ask you to approve the bindings."}</p><p>This is a development preview. The Mac app remains available separately. ${platformName} desktop integration is still being validated.</p><dl><dt>Open controls</dt><dd>Ctrl+K</dd><dt>Focus Mode</dt><dd>Ctrl+Shift+F</dd><dt>Desktop Mode</dt><dd>Ctrl+Shift+D</dd><dt>Beat sync settings</dt><dd>Ctrl+Shift+B</dd><dt>Appearance</dt><dd>Ctrl+Shift+A</dd><dt>Export lyric map</dt><dd>Ctrl+Shift+M</dd></dl><p>${isWindows ? "Choose Enable global shortcuts to register these bindings for the current session." : "These shortcuts work while Afterglow is focused. To use them globally on your desktop, bind the installed application with <code>--action focus</code>, <code>--action desktop</code>, <code>--action beats</code>, <code>--action appearance</code>, or <code>--action capture</code> in your desktop’s keyboard settings."}</p><p>${isWindows ? "Desktop mode places a separate click-through view behind desktop icons on the current monitor. Explorer restarts and monitor changes still need hardware testing." : "Desktop mode uses X11 desktop windows or Wayland Layer Shell on compatible KDE/wlroots compositors. GNOME Wayland needs separate integration. Desktop behavior is still being validated."} Passive screenshot detection is not available in this preview; use Export lyric map.</p><p>${isWindows ? "Players must publish Windows media sessions. Beat sync uses a selected process tree on Windows 11; a browser tree may include multiple tabs. Choose the player process explicitly. Protected audio may be silent." : "Apple Music on Linux depends on browser MPRIS support. The browser may expose audio for multiple tabs as one stream."}</p><p>Metadata is sent only to enabled lyric providers. Artwork is fetched from the player’s artwork host. Collections, scenes, wallpapers and imports stay on this computer.</p>`,
  };
  $("#panel-body").innerHTML = sections[panelTab]();
  if (panelTab === "player") listPlayers();
  if (panelTab === "audio") listAudio();
  if (panelTab === "cards") drawCard();
}
async function listPlayers() {
  try {
    const players = await call("players");
    if (panelTab !== "player") return;
    $("#players-list").innerHTML = players.length
      ? players
          .map(
            (p) =>
              `<button class="list-row" data-bus="${e(p.bus)}"><strong>${e(p.identity)}</strong><span>${e(p.title || "No active track")} ${p.playing ? "· Playing" : ""}</span></button>`,
          )
          .join("")
      : `<p>No players found. Start Spotify${isWindows ? ", Apple Music or another Windows media player" : " or another MPRIS player"}, then refresh.</p>`;
  } catch (err) {
    if ($("#players-list")) $("#players-list").textContent = String(err);
  }
}
async function listAudio() {
  try {
    const streams = await call("audio_streams");
    if (panelTab !== "audio") return;
    $("#audio-list").innerHTML = streams.length
      ? streams
          .map(
            (s) =>
              `<button class="list-row" data-audio="${s.index}"><strong>${e(s.name)}</strong><span>${e(s.binary)} ${s.index === audioIndex ? "· Selected" : ""}</span></button>`,
          )
          .join("")
      : "<p>No active audio streams. Start playback, then refresh.</p>";
  } catch (err) {
    if ($("#audio-list")) $("#audio-list").textContent = String(err);
  }
}
function cardData() {
  if (selectedExcerpt) return selectedExcerpt;
  if (!track) throw Error("Connect a song first.");
  return {
    track: {
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
    },
    text: excerptText(documentLyrics?.lines || [], cardSelection),
    color: effective().color,
  };
}
function cardCanvas(data) {
  const canvas = document.createElement("canvas");
  canvas.width = 1080;
  canvas.height = 1350;
  const c = canvas.getContext("2d");
  c.fillStyle = "#101014";
  c.fillRect(0, 0, 1080, 1350);
  const g = c.createRadialGradient(540, 600, 0, 540, 600, 900);
  g.addColorStop(0, data.color + "35");
  g.addColorStop(1, "#101014");
  c.fillStyle = g;
  c.fillRect(0, 0, 1080, 1350);
  c.fillStyle = data.color;
  c.font = "500 52px Manrope, sans-serif";
  const rows = [];
  for (const line of data.text.split("\n")) {
    let row = "";
    for (const word of line.split(/\s+/)) {
      if (c.measureText(row + " " + word).width > 880 && row) {
        rows.push(row);
        row = word;
      } else row += (row ? " " : "") + word;
    }
    rows.push(row);
  }
  let y = 600 - rows.length * 36;
  rows.forEach((row) => {
    c.fillText(row, 100, y, 880);
    y += 72;
  });
  c.fillStyle = "#eee";
  c.font = "32px Manrope, sans-serif";
  c.fillText(data.track.title, 100, 1110, 880);
  c.fillStyle = "#999";
  c.font = "25px Manrope, sans-serif";
  c.fillText(data.track.artist, 100, 1160, 880);
  c.font = "20px Manrope, sans-serif";
  c.fillText("AFTERGLOW", 100, 1260);
  return canvas;
}
function drawCard() {
  const canvas = $("#card-preview");
  if (!canvas) return;
  try {
    const source = cardCanvas(cardData());
    canvas.getContext("2d").drawImage(source, 0, 0);
  } catch {
    const c = canvas.getContext("2d");
    c.fillStyle = "#101014";
    c.fillRect(0, 0, 1080, 1350);
    c.fillStyle = "#999";
    c.font = "36px sans-serif";
    c.fillText("Choose your favorite lines.", 100, 650);
  }
}
async function captureMap(copy = false) {
  if (!track) throw Error("Connect a song first.");
  await saveImage(
    await visual.drawMap(track, lastLine, effective().color),
    "Afterglow-lyric-map.png",
    copy,
  );
}
async function action(id) {
  switch (id) {
    case "disable-shortcuts":
      await call("disable_shortcuts");
      notice("Global shortcuts disabled.");
      return;
    case "enable-shortcuts":
      await call("enable_shortcuts");
      notice(isWindows ? "Global shortcuts enabled for this session." : "Complete shortcut setup in your desktop’s permission dialog.");
      return;
    case "controls":
    case "connect":
      return openPanel("player");
    case "focus":
    case "exit-focus":
      return toggleFocus();
    case "desktop":
      return toggleDesktop();
    case "demo":
    case "try-demo":
      $("#panel").close();
      return startDemo();
    case "save-song":
      return openPanel("collections");
    case "close-panel":
      $("#panel").close();
      return syncCapture();
    case "refresh-players":
      return listPlayers();
    case "disconnect":
      selectionGeneration++;
      lyricGeneration++;
      demo = false;
      selectedBus = "";
      library.playerBus = "";
      persist();
      await selectTrack(null);
      notice("Disconnected. Choose a player or try the demo.");
      return renderPanel();
    case "retry-lyrics":
      return loadLyrics(true);
    case "import-lyrics":
      return $("#import-file").click();
    case "remove-import":
      delete library.imports[key];
      persist();
      return loadLyrics(true);
    case "choose-wallpaper":
      return $("#wallpaper-file").click();
    case "clear-wallpaper":
      draft.wallpaper = null;
      library.settings.wallpaper = null;
      persist();
      return;
    case "save-scene":
      if (track) {
        library.scenes[key] = snapshotAppearance(effective());
        persist();
        renderPanel();
        notice("Scene saved for this recording.");
      }
      return;
    case "remove-scene":
      delete library.scenes[key];
      draft = {};
      persist();
      return renderPanel();
    case "reset-appearance":
      const wallpaper = library.settings.wallpaper;
      const providerSettings = { allowPlainFallback: library.settings.allowPlainFallback, allowTimedFallback: library.settings.allowTimedFallback };
      library.settings = { ...defaults, ...providerSettings, wallpaper };
      const activeCollection = colorCollection(library, key);
      if (activeCollection?.color) activeCollection.color = defaults.tint;
      draft = {};
      persist();
      return renderPanel();
    case "save-color":
      library.colors.push({
        name: `Color ${library.colors.length + 1}`,
        color: effective().color,
      });
      persist();
      return renderPanel();
    case "capture-map":
      return captureMap();
    case "copy-map":
      return captureMap(true);
    case "new-collection": {
      let name;
      try { name = collectionName(library, $("#collection-name").value); }
      catch (err) { $("#collection-name").setAttribute("aria-invalid", "true"); $("#collection-name").focus(); throw err; }
      library.collections.push({
        id: crypto.randomUUID(),
        name,
        color: null,
        songs: [],
      });
      persist();
      return renderPanel();
    }
    case "refresh-audio":
      return listAudio();
    case "stop-audio":
      audioIndex = null;
      await stopCapture();
      $("#beat-state").textContent = "Beat sync off";
      return listAudio();
    case "save-excerpt": {
      const data = cardData();
      library.excerpts.push({ ...data, id: crypto.randomUUID() });
      persist();
      notice("Excerpt saved.");
      return renderPanel();
    }
    case "export-card":
      return saveImage(cardCanvas(cardData()), "Afterglow-lyric-card.png");
    case "copy-card":
      return saveImage(
        cardCanvas(cardData()),
        "Afterglow-lyric-card.png",
        true,
      );
  }
}
$("#app").addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button || button.disabled) return;
  Promise.resolve()
    .then(async () => {
      if (button.dataset.transport) return transport(button.dataset.transport);
      if (button.dataset.tab) {
        panelTab = button.dataset.tab;
        return renderPanel();
      }
      if (button.dataset.bus) {
        selectionGeneration++;
        demo = false;
        selectedBus = button.dataset.bus;
        library.playerBus = selectedBus;
        persist();
        $("#panel").close();
        await selectTrack(null);
        return refreshPlayers();
      }
      if (button.dataset.audio) {
        audioIndex = Number(button.dataset.audio);
        $("#panel").close();
        return syncCapture();
      }
      if (button.dataset.alternative) {
        documentLyrics = {
          ...documentLyrics,
          lines:
            documentLyrics.alternatives[Number(button.dataset.alternative)]
              .lines,
          manualMatch: true,
        };
        return renderPanel();
      }
      if (button.dataset.line)
        return transport(
          "seek",
          documentLyrics.lines[Number(button.dataset.line)].time +
            (library.timing[key] || 0),
        );
      if (button.dataset.addSong) {
        const c = library.collections.find(
          (c) => c.id === button.dataset.addSong,
        );
        if (!c.songs.some((s) => s.key === key))
          c.songs.push({
            key,
            track: {
              title: track.title,
              artist: track.artist,
              album: track.album,
              duration: track.duration,
            },
          });
        persist();
        trackUI();
        return renderPanel();
      }
      if (button.dataset.removeSong) {
        const collection = library.collections.find((c) => c.id === button.dataset.removeSong);
        const removed = collection.songs.splice(Number(button.dataset.songIndex), 1)[0];
        if (library.colorSource[removed.key] === collection.id) delete library.colorSource[removed.key];
        persist();
        trackUI();
        return renderPanel();
      }
      if (button.dataset.deleteCollection) {
        const collection = library.collections.find((c) => c.id === button.dataset.deleteCollection);
        if (!await confirmDeletion(collection.name)) return;
        library.collections = library.collections.filter((c) => c.id !== collection.id);
        for (const [song, source] of Object.entries(library.colorSource))
          if (source === collection.id) delete library.colorSource[song];
        persist();
        return renderPanel();
      }
      if (button.dataset.clearCollectionColor) {
        library.collections.find(
          (c) => c.id === button.dataset.clearCollectionColor,
        ).color = null;
        persist();
        return renderPanel();
      }
      if (button.dataset.color) {
        const remove = event.target.dataset.deleteColor;
        if (remove !== undefined) library.colors.splice(Number(remove), 1);
        else {
          draft.tint = library.colors[Number(button.dataset.color)].color;
          draft.albumColor = false;
          library.settings.tint = draft.tint;
          library.settings.albumColor = false;
        }
        persist();
        return renderPanel();
      }
      if (button.dataset.excerpt) {
        selectedExcerpt = library.excerpts[Number(button.dataset.excerpt)];
        return drawCard();
      }
      if (button.dataset.deleteExcerpt) {
        library.excerpts.splice(Number(button.dataset.deleteExcerpt), 1);
        selectedExcerpt = null;
        persist();
        return renderPanel();
      }
      return action(button.id);
    })
    .catch(report);
});
$("#panel-body").addEventListener("input", (event) => {
  const input = event.target;
  try {
    if (input.dataset.setting) {
      const name = input.dataset.setting;
      let value =
        input.type === "checkbox"
          ? input.checked
          : input.type === "range"
            ? Number(input.value)
            : input.value;
      if (name === "emoji")
        value =
          [
            ...new Intl.Segmenter(undefined, {
              granularity: "grapheme",
            }).segment(value),
          ][0]?.segment || "✨";
      const activeCollection = colorCollection(library, key);
      if (["tint", "albumColor"].includes(name) && activeCollection?.color) {
        if (name === "tint") activeCollection.color = value;
        else if (value) {
          // A collection keeps its independent color when album mode is unavailable.
          notice("Choose Inherit in Collections to use the song’s album color.");
          input.checked = false;
        }
      } else {
        draft[name] = value;
        library.settings[name] = value;
      }
      persist();
    }
    if (input.id === "timing") {
      library.timing[key] = Number(input.value);
      persist();
    }

    if (input.dataset.collectionColor) {
      library.collections.find(
        (c) => c.id === input.dataset.collectionColor,
      ).color = input.value;
      persist();
    }
    if (input.id === "color-source") {
      if (input.value) library.colorSource[key] = input.value;
      else delete library.colorSource[key];
      persist();
    }
    if (input.dataset.cardLine) {
      const i = Number(input.dataset.cardLine);
      input.checked ? cardSelection.add(i) : cardSelection.delete(i);
      selectedExcerpt = null;
      try {
        excerptText(documentLyrics.lines, cardSelection);
      } catch (err) {
        cardSelection.delete(i);
        input.checked = false;
        throw err;
      }
      drawCard();
    }
  } catch (err) {
    report(err);
  }
});
$("#panel-body").addEventListener("change", (event) => {
  const input = event.target;
  if (!input.dataset.rename || event.isComposing) return;
  try {
    const collection = library.collections.find((c) => c.id === input.dataset.rename);
    collection.name = collectionName(library, input.value, collection.id);
    input.removeAttribute("aria-invalid");
    persist();
  } catch (err) {
    input.setAttribute("aria-invalid", "true"); input.focus(); report(err);
  }
});
$("#import-file").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  event.target.value = "";
  if (!file || !track) return;
  const currentKey = key;
  try {
    if (file.size > 500000)
      throw Error("Lyrics files must be smaller than 500 KB.");
    const response = await call("lyrics", {
      request: {
        command: "import",
        text: await file.text(),
        fileExtension: file.name.split(".").pop(),
      },
    });
    if (response.error || !response.document)
      throw Error(response.error || "No lyrics found.");
    library.imports[currentKey] = response.document;
    persist();
    if (key === currentKey) await loadLyrics();
    notice("Lyrics imported for this recording.");
  } catch (err) {
    report(err);
  }
});
$("#wallpaper-file").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  event.target.value = "";
  if (!file) return;
  try {
    if (file.size > 10000000)
      throw Error("Choose an image smaller than 10 MB.");
    const image = await createImageBitmap(file);
    const canvas = document.createElement("canvas");
    const scale = Math.min(1, 1920 / image.width);
    canvas.width = image.width * scale;
    canvas.height = image.height * scale;
    canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
    image.close();
    draft.wallpaper = canvas.toDataURL("image/jpeg", 0.8);
    library.settings.wallpaper = draft.wallpaper;
    persist();
    notice("Wallpaper copied into your local library.");
  } catch (err) {
    report(err);
  }
});
$("#seek").addEventListener("change", (event) =>
  transport("seek", Number(event.target.value)),
);
$("#panel").addEventListener("close", () => syncCapture());
document.addEventListener("visibilitychange", () => {
  syncCapture();
  if (!document.hidden) refreshPlayers();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && focused && !$("#panel").open) {
    toggleFocus();
    return;
  }
  if (
    !event.ctrlKey ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)
  )
    return;
  const name = event.key.toLowerCase();
  if (name === "k") {
    event.preventDefault();
    openPanel();
  }
  if (event.shiftKey) {
    const actions = {
      f: toggleFocus,
      d: toggleDesktop,
      b: () => openPanel("audio"),
      a: () => openPanel("appearance"),
      m: () => captureMap(),
    };
    if (actions[name]) {
      event.preventDefault();
      Promise.resolve(actions[name]()).catch(report);
    }
  }
});
if (native) {
  const { listen } = await import("@tauri-apps/api/event");
  await listen("shortcut-state", (event) => {
    notice(event.payload);
    if ($("#shortcut-status"))
      $("#shortcut-status").textContent = event.payload;
  });
  await listen("power-state", (event) => {
    if (typeof event.payload.onBattery === "boolean")
      onBattery = event.payload.onBattery;
    if (typeof event.payload.sleeping === "boolean") {
      sleeping = event.payload.sleeping;
      if (sleeping) captureActive = false;
      syncCapture();
      if (!sleeping) refreshPlayers();
    }
  });
  await listen("audio-frame", (event) => {
    audio = event.payload;
  });
  await listen("audio-ended", (event) => {
    captureActive = false;
    audioIndex = null;
    audio = { level: 0, bands: [] };
    $("#beat-state").textContent = "Beat sync disconnected";
    report(event.payload);
  });
  await listen("restore-window", () => {
    desktop = false;
    document.body.classList.remove("desktop-mode");
    $("#desktop").textContent = "Desktop";
    wake();
  });
  await listen("action", (event) => {
    dispatchAction(event.payload).catch(report);
  });
}
async function dispatchAction(action) {
  if (desktop && ["focus", "beats", "appearance", "capture"].includes(action))
    await toggleDesktop();
  const actions = {
    focus: toggleFocus,
    desktop: toggleDesktop,
    beats: () => openPanel("audio"),
    appearance: () => openPanel("appearance"),
    capture: () => captureMap(),
  };
  if (actions[action]) await actions[action]();
}
function tick(now) {
  const animate =
    sample?.playing &&
    effective().motion &&
    (desktop || !document.hidden) &&
    !sleeping;
  scheduledTimer = setTimeout(
    () =>
      desktop
        ? tick(performance.now())
        : (scheduledFrame = requestAnimationFrame(tick)),
    animate ? (desktop ? 33 : 0) : 1000,
  );
  if ((document.hidden && !desktop) || sleeping) return;
  const settings = effective(),
    interval = sample?.playing && settings.motion ? (onBattery ? 66 : 33) : 200;
  if (now - lastDraw < interval) return;
  lastDraw = now;
  const position = positionAt(sample, now);
  if (demo && sample?.playing && position >= sample.duration) {
    sample = {
      ...sample,
      position: sample.duration,
      playing: false,
      received: now,
    };
    trackUI();
  }
  lastLine = resolveLine(
    documentLyrics?.lines || [],
    position - (library.timing[key] || 0),
    settings.estimatedWords,
    track?.duration || 120,
  );
  const signature = [
    key,
    lastLine.index,
    lastLine.active,
    revision,
    albumColor,
    Math.floor(Date.now() / (settings.seconds ? 1000 : 60000)),
    innerWidth,
    innerHeight,
    visual.revision,
  ].join(":");
  if ((sample?.playing && settings.motion) || signature !== lastRender) {
    visual.draw(now, {
      settings,
      line: lastLine,
      playing: !!sample?.playing,
      audio,
      track,
    });
    lastRender = signature;
  }
  // Untimed text stays in the explicit lyric library, never masquerading as a synced graph.
  $("#plain-text").textContent = "";
  if (sample) {
    $("#time").textContent = timeLabel(position);
    if (document.activeElement !== $("#seek")) $("#seek").value = position;
  }
  if (desktop && native && now - lastPublish > 100) {
    lastPublish = now;
    const outputSettings = { ...settings };
    if (lastWallpaper === settings.wallpaper) delete outputSettings.wallpaper;
    else lastWallpaper = settings.wallpaper;
    call("publish_display", {
      state: {
        settings: outputSettings,
        line: lastLine,
        playing: !!sample?.playing,
        audio,
      },
    }).catch(report);
  }
  if (!demo && now - lastPoll > (sample?.playing ? 1000 : 3000)) {
    lastPoll = now;
    refreshPlayers();
  }
}
await load();
if (native) {
  const startup = await call("ui_ready");
  if (startup) await dispatchAction(startup).catch(report);
}
wake();
