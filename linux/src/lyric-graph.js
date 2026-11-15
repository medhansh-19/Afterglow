// Ported from Sources/Afterglow/Constellation.swift: reading-order columns,
// alternating heights, connected diamond markers and one active word.
export const GRAPH_LINES = [
  ["Rainbow,", "waiting", "by", "my", "window"],
  ["Rainbow,", "singing", "at", "my", "door"],
  ["And", "it's", "all", "I", "know"],
  ["You're", "the", "afterglow"],
  ["That", "never", "fades"],
];
const escapeXml = (value) =>
  String(value).replace(
    /[<>&"']/g,
    (c) =>
      ({
        "<": "&lt;",
        ">": "&gt;",
        "&": "&amp;",
        '"': "&quot;",
        "'": "&apos;",
      })[c],
  );
export function graphSvgMarkup(
  words,
  {
    color = "currentColor",
    fontSize = 38,
    active = 0,
    height = 580,
    lineFocus = false,
    renderWidth = 1000,
    arrangementSeed = 0,
    diamondScale = 1,
  } = {},
) {
  const columns = Math.min(words.length, words.length > 12 ? 6 : 4),
    rows = Math.ceil(words.length / columns),
    width = 1000;
  const points = words.map((word, i) => {
    const row = Math.floor(i / columns),
      col = i % columns,
      occupied = Math.min(columns, words.length - row * columns),
      rh = height / Math.max(2, rows);
    return {
      word,
      x:
        (width * (col + 0.5 + (columns - occupied) / 2)) / columns +
        Math.sin((i + 1) * (arrangementSeed + 1) * 12.9898) *
          Math.min(12, (width / columns) * 0.04),
      y:
        height / 2 +
        (row - (rows - 1) / 2) * rh * 0.8 +
        (col % 2 === 0 ? -1 : 1) * Math.min(rh * 0.22, 42),
    };
  });
  const unit = 1000 / Math.max(1, renderWidth),
    base =
      Math.max(14, Math.min(renderWidth / (words.length > 12 ? 37 : 29), 38)) *
      unit,
    size = fontSize / 38;
  const edges = [];
  points.forEach((point, i) => {
    if (!i) return;
    edges.push([i - 1, i, lineFocus || i <= active ? 0.72 : 0.34, 1.1]);
    if (i > 2) edges.push([i - 3, i, 0.36, 0.85]);
    if (i > 4 && i % 2 === 0) edges.push([1, i, 0.27, 0.8]);
  });
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 ${height}" aria-hidden="true"><g fill="none" stroke="${color}">${edges.map(([a, b, opacity, w]) => `<path d="M${points[a].x} ${points[a].y}L${points[b].x} ${points[b].y}" opacity="${opacity}" stroke-width="${w}" vector-effect="non-scaling-stroke"/>`).join("")}</g>${points
    .map((p, i) => {
      const current = i === active,
        opacity = current || lineFocus ? 1 : i < active ? 0.78 : 0.48;
      const polygon = (n, star = false) =>
        Array.from({ length: n }, (_, j) => {
          const a = (j * 2 * Math.PI) / n - Math.PI / 2,
            r = 5 * (star && j % 2 ? 0.44 : 1);
          return `${p.x + Math.cos(a) * r},${p.y + Math.sin(a) * r}`;
        }).join(" ");
      const fs = (current ? Math.max(22 * unit, base * 1.5) : base) * size;
      return `<g class="ag-graph-node${current ? " is-active" : ""}" data-graph-word="${i}" style="color:${color};opacity:${opacity}"><text x="${p.x}" y="${p.y - 25 * unit}" text-anchor="middle" fill="currentColor" font-family="Manrope,system-ui,sans-serif" font-weight="500" font-size="${fs}" ${p.word.length * fs * 0.54 > width / columns - 18 ? `textLength="${width / columns - 18}" lengthAdjust="spacingAndGlyphs"` : ""} style="${current ? "filter:drop-shadow(0 0 22px currentColor)" : ""}">${escapeXml(p.word)}</text><path d="M${p.x} ${p.y - 7}l7 7-7 7-7-7Z" fill="currentColor" transform="translate(${p.x} ${p.y}) scale(${diamondScale * (current || lineFocus ? 1 : 4 / 7)}) translate(${-p.x} ${-p.y})"/><polygon class="ag-marker-triangle" points="${polygon(3)}" fill="currentColor"/><polygon class="ag-marker-star" points="${polygon(10, true)}" fill="currentColor"/><polygon class="ag-marker-octagon" points="${polygon(8)}" fill="currentColor"/><rect class="ag-marker-rectangle" x="${p.x - 5}" y="${p.y - 3.5}" width="10" height="7" fill="currentColor"/><circle class="ag-marker-circle" cx="${p.x}" cy="${p.y}" r="${current ? 5 : 3}" fill="currentColor"/><text class="ag-marker-sparkle" x="${p.x}" y="${p.y + 5}" text-anchor="middle" font-size="14">✨</text></g>`;
    })
    .join("")}</svg>`;
}
export function createLyricGraph(
  container,
  {
    lines = GRAPH_LINES,
    fontSize = 38,
    progress = 0,
    height = 580,
    referenceWidth = 0,
  } = {},
) {
  let index = -1,
    active = -2,
    paused = false,
    focused = false,
    lastWidth = 0;
  container.classList.add("ag-node-graph");
  container.setAttribute("role", "img");
  function setLine(next, within = 0, options = {}) {
    next = Math.max(0, Math.min(lines.length - 1, next));
    const count =
      options.active ??
      Math.min(lines[next].length - 1, Math.floor(within * lines[next].length));
    if (next !== index || count !== active || !!options.lineFocus !== focused) {
      index = next;
      active = count;
      focused = !!options.lineFocus;
      container.innerHTML = graphSvgMarkup(lines[index], {
        fontSize,
        renderWidth: referenceWidth || container.clientWidth || 1000,
        height,
        active,
        lineFocus: options.lineFocus,
      });
      container.dataset.graphIndex = String(index);
      container.dataset.activeWord = String(active);
      container.setAttribute("aria-label", lines[index].join(" "));
    }
  }
  function setProgress(value) {
    if (paused) return;
    const p = Math.max(0, Math.min(0.999999, value)) * lines.length;
    setLine(Math.floor(p), p % 1);
    container.dataset.graphProgress = String(value);
  }
  const resize = new ResizeObserver(() => {
    if (container.clientWidth > 0 && container.clientHeight > 0) {
      const nextHeight = Math.max(
        260,
        (1000 * container.clientHeight) / container.clientWidth,
      );
      if (
        Math.abs(nextHeight - height) > 1 ||
        lastWidth !== container.clientWidth
      ) {
        lastWidth = container.clientWidth;
        height = nextHeight;
        const previous = active;
        active = -2;
        setLine(index < 0 ? 0 : index, 0, {
          active: previous,
          lineFocus: focused,
        });
      }
    }
  });
  resize.observe(container);
  setProgress(progress);
  return {
    setLine,
    setProgress,
    setPaused(value) {
      paused = !!value;
    },
    get index() {
      return index;
    },
    dispose() {
      resize.disconnect();
      container.replaceChildren();
    },
  };
}
