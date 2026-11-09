export const PRESET_COLORS = {
  Rose: "#f066ab", Blue: "#6bb0f7", Amber: "#f7b566", Mint: "#4df5bf", Violet: "#b87aff",
  "Off-white": "#f2f0e0", Scarlet: "#fa525c", Coral: "#ff7d6e", Orange: "#ff9c45", Gold: "#ffd657",
  Lime: "#baeb5c", Teal: "#40d1ba", Cyan: "#4ad9f7", Indigo: "#7a8aff",
};
export const collectionTint = (collection, album, fallback) => collection?.color === "album" ? (album || PRESET_COLORS.Rose) : (collection?.color || fallback);
export function saveColor(library, value, label) {
  const color = value.toLowerCase();
  if (!/^#[0-9a-f]{6}$/.test(color)) throw Error("Choose a valid RGB color.");
  const name = label.trim() || color.toUpperCase();
  if ([...name].length > 40) throw Error("Color names can contain up to 40 characters.");
  const existing = library.colors.find((saved) => saved.color.toLowerCase() === color);
  if (existing) existing.name = name; else library.colors.push({ name, color });
}
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
  estimatedWords: true,
  chorusMemory: true,
  fontSize: 38,
  wallpaper: null,
  allowPlainFallback: true,
  allowTimedFallback: true,
};
// Provider/privacy settings apply globally and must not change with a song scene.
const appearanceKeys = Object.keys(defaults).filter(
  (key) => !["allowPlainFallback", "allowTimedFallback"].includes(key),
);
export function snapshotAppearance(settings) {
  return Object.fromEntries(appearanceKeys.filter((key) => settings[key] !== undefined).map((key) => [key, settings[key]]));
}
const normalizeSettings = (settings) => ({
  ...settings,
  ...(settings.clockSize === undefined ? {} : { clockSize: Math.min(140, Math.max(70, settings.clockSize)) }),
});
export function newLibrary() {
  return {
    version: 1,
    playerBus: null,
    settings: { ...defaults },
    scenes: {},
    timing: {},
    imports: {},
    matches: {},
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
    base.settings = { ...defaults, ...normalizeSettings(value.settings) };
  }
  for (const key of ["scenes", "timing", "imports", "matches", "colorSource"]) {
    if (value[key] === undefined) continue;
    if (!record(value[key]) || Object.keys(value[key]).length > 10000)
      invalid();
    for (const entry of Object.values(value[key])) {
      if (
        (key === "scenes" && !validSettings(entry)) ||
        (key === "timing" && !finite(entry, -5, 5)) ||
        (["imports", "matches"].includes(key) && !validDocument(entry)) ||
        (key === "colorSource" &&
          !(typeof entry === "string" && entry.length <= 128))
      )
        invalid();
    }
    base[key] = key === "scenes"
      ? Object.fromEntries(Object.entries(value[key]).map(([id, settings]) => [id, snapshotAppearance(normalizeSettings(settings))]))
      : value[key];
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
          (c.color == null || c.color === "album" || hex(c.color)) &&
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
const preparedLines = new WeakMap();
const preparedChoruses = new WeakMap();
const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });
const characterCount = (text) => [...graphemes.segment(text)].length;
const vocal = (line) => /[\p{L}\p{N}]/u.test(line.text) &&
  !["[instrumental]", "(instrumental)", "[music]", "(music)", "[interlude]", "(interlude)"].includes(line.text.trim().toLowerCase());
function lyricPieces(source) {
  const chars = [...source], pieces = [];
  let current = "";
  for (let i = 0; i < chars.length; i++) {
    const char = chars[i];
    if (/\s/u.test(char)) { if (current) pieces.push(current); current = ""; continue; }
    current += char;
    if (!".;；。".includes(char)) continue;
    if (char === "." && /\p{N}/u.test(chars[i - 1] || "") && /\p{N}/u.test(chars[i + 1] || "")) continue;
    if (chars[i + 1] && ".;；。".includes(chars[i + 1])) continue;
    pieces.push(current); current = "";
  }
  if (current) pieces.push(current);
  return pieces;
}
function prepareLine(line) {
  if (preparedLines.has(line)) return preparedLines.get(line);
  const raw = line.words?.length ? line.words.map((word) => word.text) : line.text.trim().split(/\s+/u);
  const tokens = [], original = [], groups = new Map(), weights = [0];
  raw.forEach((token, index) => {
    for (const piece of lyricPieces(token)) {
      const text = piece.replace(/^[()\[\]{}（）【】「」『』《》]+|[()\[\]{}（）【】「」『』《》]+$/gu, "");
      if (!/[\p{L}\p{N}]/u.test(text)) continue;
      if (!groups.has(index)) groups.set(index, [tokens.length, tokens.length]);
      groups.get(index)[1] = tokens.length + 1;
      tokens.push(text); original.push(index);
      weights.push(weights.at(-1) + Math.max(2, characterCount(text)));
    }
  });
  const result = { tokens, original, groups, weights };
  preparedLines.set(line, result);
  return result;
}
function chorusLines(lines) {
  if (preparedChoruses.has(lines)) return preparedChoruses.get(lines);
  const keys = lines.map((line) => vocal(line) ? line.text.toLowerCase().replace(/[^\p{L}\p{N}\p{M}]/gu, " ").trim().replace(/\s+/gu, " ") : "");
  const canonical = lines.map((_, i) => i), occurrences = new Map();
  for (let i = 0; i < keys.length; i++) {
    if (!keys[i]) continue;
    for (const first of occurrences.get(keys[i]) || []) {
      if (first > 0 && i > 0 && keys[i - 1] && keys[first - 1] === keys[i - 1]) continue;
      let length = 0, words = 0;
      while (first + length < i && i + length < keys.length && keys[i + length] && keys[first + length] === keys[i + length]) {
        words += keys[i + length].split(" ").length; length++;
      }
      if (!(length >= 2 && words >= 6 || length === 1 && words >= 6)) continue;
      for (let offset = 0; offset < length; offset++) canonical[i + offset] = Math.min(canonical[i + offset], canonical[first + offset]);
    }
    if (!occurrences.has(keys[i])) occurrences.set(keys[i], []);
    occurrences.get(keys[i]).push(i);
  }
  preparedChoruses.set(lines, canonical);
  return canonical;
}
export function resolveLine(lines, time, estimated = true, duration = 0, pageSize = 24) {
  const empty = { index: -1, words: [], active: -1 };
  if (!Number.isFinite(time) || time < 0 || (duration > 0 && time >= duration)) return empty;
  let low = 0, high = lines.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (lines[mid].time <= time) low = mid + 1; else high = mid;
  }
  const index = low - 1, line = lines[index];
  if (!line || !vocal(line)) return empty;
  const nextTime = lines[index + 1]?.time ?? (duration > 0 ? duration : line.time + 5);
  let end = Math.min(nextTime, line.end ?? nextTime);
  if (!line.words?.length && end - line.time > 30 && line.text.trim().split(/\s+/u).length <= 24)
    end = Math.min(end, line.time + Math.min(16, Math.max(8, line.text.trim().split(/\s+/u).length * .8)));
  if (time >= end) return empty;
  const prepared = prepareLine(line), { tokens, original, groups, weights } = prepared;
  if (!tokens.length) return empty;
  const weighted = (progress, start = 0, stop = tokens.length) => {
    const target = Math.min(Math.max(progress, 0), .999999) * (weights[stop] - weights[start]);
    let left = start, right = stop;
    while (left < right) { const mid = (left + right) >> 1; if (weights[mid + 1] - weights[start] <= target) left = mid + 1; else right = mid; }
    return Math.min(stop - 1, left);
  };
  let active = -1, supplied = -1;
  if (line.words?.length) {
    for (let i = 0; i < line.words.length; i++) if (line.words[i].time <= time) supplied = i;
    if (supplied >= 0 && !(line.words[supplied].end != null && time >= line.words[supplied].end)) {
      const group = groups.get(supplied);
      if (group) {
        active = group[0];
        if (group[1] - group[0] > 1 && estimated) {
          const word = line.words[supplied], stop = Math.min(end, word.end ?? line.words[supplied + 1]?.time ?? end);
          active = weighted((time - word.time) / Math.max(.1, stop - word.time), group[0], group[1]);
        }
      }
    }
  } else if (estimated) active = weighted((time - line.time) / Math.max(.1, end - line.time));
  let anchor = active;
  if (anchor < 0 && line.words?.length) { anchor = 0; for (let i = 0; i < original.length; i++) if (original[i] <= Math.max(0, supplied)) anchor = i; }
  if (anchor < 0) anchor = weighted((time - line.time) / Math.max(.1, end - line.time));
  const capacity = Math.max(1, Math.floor(pageSize)), pageStart = Math.floor(Math.min(tokens.length - 1, Math.max(0, anchor)) / capacity) * capacity;
  return { index, words: tokens.slice(pageStart, pageStart + capacity), active: active < 0 ? -1 : active - pageStart, exact: !!line.words?.length,
    pageStart, layoutSeed: chorusLines(lines)[index] * 31 + pageStart };
}
export function colorCollection(library, key) {
  const memberships = library.collections.filter((c) => c.songs.some((s) => s.key === key));
  // An explicit inheriting collection deliberately opts out of another collection's color.
  return memberships.find((c) => c.id === library.colorSource[key]) ||
    memberships.find((c) => c.color != null);
}
export function collectionName(library, value, excluding = null) {
  const name = value.trim();
  const normalized = (text) => text.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase();
  if (!name || [...name].length > 40 || library.collections.some((c) =>
    c.id !== excluding && normalized(c.name) === normalized(name)))
    throw Error("Use a unique collection name of 1–40 characters.");
  return name;
}
export function appearance(library, key, albumColor) {
  const settings = { ...library.settings, ...snapshotAppearance(library.scenes[key] || library.settings) };
  const collection = colorCollection(library, key);
  return {
    ...settings,
    color: collectionTint(collection, albumColor, settings.albumColor && albumColor ? albumColor : settings.tint),
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
