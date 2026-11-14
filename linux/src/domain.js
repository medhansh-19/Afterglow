export const defaults = {
  tint: "#b9a5ef",
  albumColor: true,
  opacity: 0.45,
  marker: "diamond",
  emoji: "✨",
  clock: true,
  clockColor: "#eeeeee",
  clockFollowsLyrics: false,
  clockStyle: "Minimal",
  format: "System",
  seconds: false,
  date: false,
  clockSize: 100,
  motion: true,
  estimatedWords: false,
  chorusMemory: true,
  fontSize: 38,
  wallpaper: null,
  allowPlainFallback: true,
  allowTimedFallback: true,
};
export function newLibrary() {
  return {
    version: 1,
    suppliedWordTimingDefaultApplied: true,
    playerBus: null,
    settings: { ...defaults },
    scenes: {},
    timing: {},
    imports: {},
    collections: [
      { id: "liked", name: "Liked", color: null, songs: [] },
      { id: "favorites", name: "Favorites", color: null, songs: [] },
    ],
    colorSource: {},
    colors: [],
    excerpts: [],
  };
}
const record = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const finite = (v, min, max) =>
  typeof v === "number" && Number.isFinite(v) && v >= min && v <= max;
const hex = (v) => typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v);
const validTrack = (t) =>
  record(t) &&
  ["title", "artist", "album"].every(
    (k) => typeof t[k] === "string" && t[k].length <= 10000,
  ) &&
  finite(t.duration, 0, 86400);
function validSettings(settings) {
  if (!record(settings)) return false;
  return Object.entries(settings).every(([k, v]) => {
    if (
      [
        "albumColor",
        "clock",
        "clockFollowsLyrics",
        "seconds",
        "date",
        "motion",
        "estimatedWords",
        "chorusMemory",
        "allowPlainFallback",
        "allowTimedFallback",
      ].includes(k)
    )
      return typeof v === "boolean";
    if (k === "tint" || k === "clockColor") return hex(v);
    if (k === "opacity") return finite(v, 0, 1);
    if (k === "fontSize") return finite(v, 22, 60);
    if (k === "clockSize") return finite(v, 60, 180);
    if (k === "clockStyle")
      return [
        "Minimal",
        "Flip",
        "Rounded",
        "Glass",
        "Ring",
        "Analog",
        "Classic",
      ].includes(v);
    if (k === "format") return ["System", "12", "24"].includes(v);
    if (k === "marker")
      return [
        "diamond",
        "circle",
        "triangle",
        "star",
        "octagon",
        "rectangle",
        "sparkle",
      ].includes(v);
    if (k === "emoji") return typeof v === "string" && v.length <= 24;
    if (k === "wallpaper")
      return (
        v === null ||
        (typeof v === "string" &&
          v.length <= 8000000 &&
          /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(v))
      );
    return false;
  });
}
function validDocument(doc) {
  return (
    record(doc) &&
    Array.isArray(doc.lines) &&
    doc.lines.length <= 5000 &&
    doc.lines.every(
      (l) =>
        record(l) &&
        finite(l.time, 0, 86400) &&
        typeof l.text === "string" &&
        l.text.length <= 10000 &&
        (l.end == null || finite(l.end, l.time, 86400)) &&
        Array.isArray(l.words) &&
        l.words.length <= 500 &&
        l.words.every(
          (w) =>
            record(w) &&
            typeof w.text === "string" &&
            finite(w.time, l.time, 86400) &&
            (w.end == null || finite(w.end, w.time, 86400)),
        ),
    ) &&
    (doc.plainText == null ||
      (typeof doc.plainText === "string" && doc.plainText.length <= 500000))
  );
}
export function readLibrary(value) {
  const invalid = () => {
    throw Error(
      "Invalid saved library. Restore a valid backup before changing it.",
    );
  };
  if (!record(value)) invalid();
  if (value.version !== undefined && value.version !== 1)
    throw Error("This library was made by a newer version of Afterglow.");
  const base = newLibrary();
  if (value.playerBus !== undefined) {
    if (
      value.playerBus !== null &&
      !(typeof value.playerBus === "string" && value.playerBus.length <= 255)
    )
      invalid();
    base.playerBus = value.playerBus;
  }
  if (value.settings !== undefined) {
    if (!validSettings(value.settings)) invalid();
    base.settings = { ...defaults, ...value.settings };
  }
  for (const key of ["scenes", "timing", "imports", "colorSource"]) {
    if (value[key] === undefined) continue;
    if (!record(value[key]) || Object.keys(value[key]).length > 10000)
      invalid();
    for (const entry of Object.values(value[key])) {
      if (
        (key === "scenes" && !validSettings(entry)) ||
        (key === "timing" && !finite(entry, -5, 5)) ||
        (key === "imports" && !validDocument(entry)) ||
        (key === "colorSource" &&
          !(typeof entry === "string" && entry.length <= 128))
      )
        invalid();
    }
    base[key] = value[key];
  }
  if (value.collections !== undefined) {
    if (
      !Array.isArray(value.collections) ||
      value.collections.length > 1000 ||
      !value.collections.every(
        (c) =>
          record(c) &&
          typeof c.id === "string" &&
          c.id.length <= 128 &&
          typeof c.name === "string" &&
          c.name.length <= 80 &&
          (c.color == null || hex(c.color)) &&
          Array.isArray(c.songs) &&
          c.songs.length <= 10000 &&
          c.songs.every(
            (s) =>
              record(s) && typeof s.key === "string" && validTrack(s.track),
          ),
      )
    )
      invalid();
    base.collections = value.collections;
  }
  if (value.colors !== undefined) {
    if (
      !Array.isArray(value.colors) ||
      !value.colors.every(
        (c) => record(c) && typeof c.name === "string" && hex(c.color),
      )
    )
      invalid();
    base.colors = value.colors;
  }
  if (value.excerpts !== undefined) {
    if (
      !Array.isArray(value.excerpts) ||
      !value.excerpts.every(
        (x) =>
          record(x) &&
          validTrack(x.track) &&
          typeof x.text === "string" &&
          [...x.text].length <= 280 &&
          hex(x.color),
      )
    )
      invalid();
    base.excerpts = value.excerpts;
  }
  // Older versions enabled estimated highlights automatically, including saved scenes.
  // Apply the precise default once; subsequent explicit choices survive roundtrips.
  if (value.suppliedWordTimingDefaultApplied !== true) {
    base.settings.estimatedWords = false;
    base.scenes = Object.fromEntries(Object.entries(base.scenes).map(([id, scene]) => [id, { ...scene, estimatedWords: false }]));
  }
  return base;
}
export function recordingKey(track) {
  return [
    track.title || "",
    track.artist || "",
    track.album || "",
    String(
      Math.floor(
        Number.isFinite(track.duration) ? Math.max(0, track.duration) : 0,
      ),
    ),
  ]
    .map((v) => `${new TextEncoder().encode(v).length}:${v}`)
    .join("");
}
export function positionAt(sample, now) {
  if (!sample) return 0;
  return Math.max(
    0,
    Math.min(
      sample.duration || 86400,
      sample.position +
        (sample.playing
          ? (Math.max(0, now - sample.received) / 1000) * (sample.rate || 1)
          : 0),
    ),
  );
}
// Resolve from the media clock so seeking into a brief pause preserves the same lyric.
export function resolveLine(lines, time, estimated = true, duration = 0) {
  const empty = { index: -1, words: [], active: -1 };
  if (!Number.isFinite(time) || time < 0 || (duration > 0 && time >= duration)) return empty;
  const isVocal = (line) => /[\p{L}\p{N}]/u.test(line.text.trim()) &&
    !/^(?:\[|\()?(?:instrumental|music|interlude)(?:\]|\))?$/i.test(line.text.trim());
  const displayEnd = (index) => {
    const line = lines[index], next = lines[index + 1]?.time ?? (duration > 0 ? duration : line.time + 5);
    let end = Math.min(next, line.end ?? next);
    const count = line.text.trim().split(/\s+/u).length;
    if (!line.words?.length && end - line.time > 30 && count <= 24)
      end = Math.min(end, line.time + Math.min(16, Math.max(8, count * .8)));
    return end;
  };
  let low = 0, high = lines.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (lines[mid].time <= time) low = mid + 1; else high = mid;
  }
  const current = low - 1;
  if (current < 0) return empty;
  if (isVocal(lines[current]) && time < displayEnd(current)) return resolveTimedLine(lines, time, estimated, duration);
  let previous = current;
  while (previous >= 0 && !isVocal(lines[previous])) previous--;
  let next = current + 1;
  while (next < lines.length && !isVocal(lines[next])) next++;
  const stop = lines[next]?.time ?? duration;
  const start = previous >= 0 ? displayEnd(previous) : lines[0].time;
  // Hold only short complete gaps; never highlight an already finished word.
  if (previous >= 0 && stop - start <= 1.5 && stop > time) {
    const held = resolveTimedLine(lines, Math.max(lines[previous].time, start - 0.000001), estimated, duration);
    return { ...held, active: -1 };
  }
  return empty;
}
function resolveTimedLine(lines, time, estimated = true, duration = 0) {
  let low = 0,
    high = lines.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (lines[mid].time <= time) low = mid + 1;
    else high = mid;
  }
  const index = low - 1,
    line = lines[index];
  if (!line || !line.text || (line.end != null && time >= line.end))
    return { index: -1, words: [], active: -1 };
  const words = line.words?.length
    ? line.words.map((w) => w.text)
    : line.text.trim().split(/\s+/u);
  let active = -1;
  if (line.words?.length) {
    for (let i = 0; i < line.words.length; i++) {
      if (line.words[i].time <= time) active = i;
    }
    if (
      active >= 0 &&
      line.words[active].end != null &&
      time >= line.words[active].end
    )
      active = -1;
  } else if (estimated) {
    const end = Math.min(
      lines[index + 1]?.time ?? duration ?? line.time + 5,
      line.end ?? Infinity,
    );
    const weights = words.map((w) => Math.max(2, [...w].length)),
      total = weights.reduce((a, b) => a + b, 0);
    let target =
      Math.max(
        0,
        Math.min(0.999999, (time - line.time) / Math.max(0.1, end - line.time)),
      ) * total;
    active = words.length - 1;
    for (let i = 0; i < words.length; i++) {
      target -= weights[i];
      if (target < 0) {
        active = i;
        break;
      }
    }
  }
  return { index, words, active, exact: !!line.words?.length };
}
export function appearance(library, key, albumColor) {
  const settings = { ...library.settings, ...library.scenes[key] };
  const candidates = library.collections.filter(
    (c) => c.color && c.songs?.some((s) => s.key === key),
  );
  const collection =
    candidates.find((c) => c.id === library.colorSource[key]) || candidates[0];
  return {
    ...settings,
    color:
      collection?.color ||
      (settings.albumColor && albumColor ? albumColor : settings.tint),
  };
}
export function excerptText(lines, selected) {
  const chosen = lines.filter((_, i) => selected.has(i)).map((l) => l.text);
  const text = chosen.join("\n").trim();
  if (!text || chosen.length > 6 || [...text].length > 280)
    throw Error("Choose up to six lines and 280 characters.");
  return text;
}
export const escape = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
export const timeLabel = (value) =>
  `${Math.floor(Math.max(0, value) / 60)}:${String(Math.floor(Math.max(0, value) % 60)).padStart(2, "0")}`;
