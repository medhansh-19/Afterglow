import { ribbonMesh } from "./ribbon-mesh";
import { graphSvgMarkup } from "./lyric-graph";
import { clockMarkup } from "./clock-preview";
export function renderer(canvas, graph, clock) {
  const ctx = canvas.getContext("2d");
  let invalidation = 0;
  let w = 0,
    h = 0,
    phase = 0,
    last = 0,
    key = "",
    lastClock = "",
    energy = 0,
    wallpaper = null,
    wallpaperURL = null;
  function resize() {
    const scale = Math.min(devicePixelRatio || 1, 1.5);
    w = canvas.clientWidth;
    h = canvas.clientHeight;
    canvas.width = w * scale;
    canvas.height = h * scale;
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    key = "";
    invalidation++;
  }
  const observer = new ResizeObserver(resize);
  observer.observe(canvas);
  resize();
  function draw(now, { settings, line, playing, audio, track }) {
    const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
    last = now;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    energy += ((playing ? audio.level || 0 : 0) - energy) * Math.min(1, dt * 8); // release smoothly after pause
    if (!playing) energy *= Math.exp(-dt * 8);
    if (playing && settings.motion && !reduced)
      phase += dt * (1 + energy * 2.4);
    ctx.fillStyle = "#09090b";
    ctx.fillRect(0, 0, w, h);
    if (wallpaperURL !== settings.wallpaper) {
      wallpaperURL = settings.wallpaper;
      wallpaper = null;
      if (wallpaperURL) {
        const image = new Image();
        image.onload = () => {
          if (wallpaperURL === settings.wallpaper) {
            wallpaper = image;
            invalidation++;
          }
        };
        image.src = wallpaperURL;
      }
    }
    if (wallpaper) {
      const scale = Math.max(w / wallpaper.width, h / wallpaper.height);
      ctx.globalAlpha = settings.opacity;
      ctx.drawImage(
        wallpaper,
        (w - wallpaper.width * scale) / 2,
        (h - wallpaper.height * scale) / 2,
        wallpaper.width * scale,
        wallpaper.height * scale,
      );
      ctx.globalAlpha = 1;
    }
    const glow = ctx.createRadialGradient(
      w * 0.5,
      h * 0.5,
      0,
      w * 0.5,
      h * 0.5,
      w * 0.75,
    );
    glow.addColorStop(0, `${settings.color}18`);
    glow.addColorStop(1, "#09090b00");
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, w, h);
    const mesh = ribbonMesh({
      phase,
      energy,
      bands: audio.bands || [],
      live: playing && audio.bands?.length === 32,
      pulse: energy * 0.2,
      reducedMotion: reduced,
    });
    ctx.strokeStyle = settings.color;
    mesh.forEach((points, i) => {
      ctx.beginPath();
      points.forEach((p, j) => {
        const x = (p.x / 1400) * w,
          y = h * 0.55 + ((p.y - 300) / 600) * h * 0.65;
        j ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      });
      ctx.globalAlpha = (line.words.length ? 0.18 : 0.6) * (i === 8 ? 1 : 0.45);
      ctx.lineWidth = i === 8 ? 1.4 : 0.7;
      ctx.stroke();
    });
    ctx.globalAlpha = 1;
    const nextKey = JSON.stringify([
      line.words,
      line.active,
      settings.fontSize,
      settings.marker,
      settings.emoji,
      Math.round(graph.clientWidth),
      settings.chorusMemory,
      line.layoutSeed,
      line.pageStart,
    ]);
    if (nextKey !== key) {
      key = nextKey;
      graph.innerHTML = line.words.length
        ? graphSvgMarkup(line.words, {
            arrangementSeed: settings.chorusMemory ? (line.layoutSeed ?? line.index * 31) : (line.index * 31 + (line.pageStart || 0)),
            fontSize: settings.fontSize,
            active: line.active,
            lineFocus: line.active < 0,
            height: Math.max(
              300,
              (1000 * graph.clientHeight) / Math.max(1, graph.clientWidth),
            ),
            renderWidth: graph.clientWidth,
          })
        : "";
      graph.setAttribute("aria-label", line.words.join(" "));
    }
    graph.style.color = settings.color;
    graph.dataset.marker = settings.marker;
    graph.querySelectorAll(".ag-marker-sparkle").forEach((node) => {
      node.textContent = settings.emoji || "✨";
    });
    const date = new Date(),
      nextClock = [
        Math.floor(date.getTime() / (settings.seconds ? 1000 : 60000)),
        settings.clockStyle,
        settings.format,
        settings.seconds,
        settings.date,
        settings.clockSize,
      ].join(":");
    clock.hidden = !settings.clock;
    clock.style.color = settings.clockFollowsLyrics
      ? settings.color
      : settings.clockColor;
    if (nextClock !== lastClock) {
      lastClock = nextClock;
      clock.innerHTML =
        clockMarkup(date, {
          ...settings,
          format:
            settings.format === "System"
              ? new Intl.DateTimeFormat(undefined, {
                  hour: "numeric",
                }).resolvedOptions().hour12
                ? "12"
                : "24"
              : settings.format,
        }) +
        (settings.date
          ? `<div class="clock-date">${date.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" })}</div>`
          : "");
      clock.dataset.style = settings.clockStyle;
      clock.style.fontSize = `${(settings.clockSize / 100) * 2.2}rem`;
    }
  }
  return {
    draw,
    dispose() { observer.disconnect(); },
    get revision() {
      return invalidation;
    },
    async drawMap(track, line, color) {
      const frozen = graph.querySelector("svg")?.cloneNode(true);
      if (frozen) {
        frozen.setAttribute("xmlns", "http://www.w3.org/2000/svg");
        frozen.setAttribute("width", "1600");
        frozen.setAttribute("height", "700");
        frozen.style.color = color;
        frozen.querySelectorAll('[class^="ag-marker-"]').forEach((node) => {
          const wanted = node.classList.contains(
            "ag-marker-" + graph.dataset.marker,
          );
          node.style.display = wanted ? "block" : "none";
        });
        if (graph.dataset.marker !== "diamond")
          frozen
            .querySelectorAll(".ag-graph-node>path")
            .forEach((node) => (node.style.display = "none"));
      }
      const out = document.createElement("canvas");
      out.width = 1600;
      out.height = 1000;
      const c = out.getContext("2d");
      c.fillStyle = "#09090b";
      c.fillRect(0, 0, 1600, 1000);
      if (frozen) {
        const font = await fetch("/fonts/manrope.woff2").then((r) =>
          r.arrayBuffer(),
        );
        let bytes = "";
        for (const value of new Uint8Array(font))
          bytes += String.fromCharCode(value);
        const style = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "style",
        );
        style.textContent = `@font-face{font-family:Manrope;src:url(data:font/woff2;base64,${btoa(bytes)}) format('woff2')}`;
        frozen.prepend(style);
        const image = new Image();
        const url = URL.createObjectURL(
          new Blob([new XMLSerializer().serializeToString(frozen)], {
            type: "image/svg+xml",
          }),
        );
        try {
          await new Promise((resolve, reject) => {
            image.onload = resolve;
            image.onerror = () =>
              reject(Error("Lyric map could not be rendered."));
            image.src = url;
          });
          c.drawImage(image, 0, 70, 1600, 700);
        } finally {
          URL.revokeObjectURL(url);
        }
      } else {
        c.drawImage(canvas, 0, 0, 1600, 780);
      }
      c.fillStyle = "#eee";
      c.textAlign = "center";
      c.font = "30px Manrope, sans-serif";
      c.fillText(track?.title || "Afterglow", 800, 830, 1400);
      c.fillStyle = "#999";
      c.font = "22px Manrope, sans-serif";
      c.fillText(track?.artist || "", 800, 875, 1400);
      c.font = "18px Manrope, sans-serif";
      c.fillText("AFTERGLOW", 800, 955);
      return out;
    },
  };
}
