import test from "node:test";
import assert from "node:assert/strict";
import {
  newLibrary, readLibrary, recordingKey, colorCollection, appearance,
  snapshotAppearance, collectionName, positionAt, resolveLine,
} from "../../linux/src/domain.js";

const track = { title: "A song", artist: "An artist", album: "An album", duration: 240 };
const songKey = recordingKey(track);
const membership = () => ({ key: songKey, track });

test("explicit inheriting membership overrides automatic collection color", () => {
  const library = newLibrary();
  library.settings.tint = "#112233";
  library.settings.albumColor = false;
  library.collections[0].color = "#ff0000";
  library.collections[0].songs.push(membership());
  library.collections[1].songs.push(membership());
  assert.equal(appearance(library, songKey).color, "#ff0000");
  library.colorSource[songKey] = "favorites";
  assert.equal(colorCollection(library, songKey).id, "favorites");
  assert.equal(appearance(library, songKey).color, "#112233");
  library.collections[1].songs = [];
  assert.equal(appearance(library, songKey).color, "#ff0000");
});

test("scene snapshots never change provider privacy choices or include resolved color", () => {
  const library = newLibrary();
  library.settings.allowTimedFallback = false;
  library.settings.allowPlainFallback = false;
  library.scenes[songKey] = snapshotAppearance({
    ...library.settings, tint: "#abcdef", allowTimedFallback: true,
    allowPlainFallback: true, color: "#ffffff",
  });
  assert.ok(!("allowTimedFallback" in library.scenes[songKey]));
  assert.ok(!("allowPlainFallback" in library.scenes[songKey]));
  assert.ok(!("color" in library.scenes[songKey]));
  const settings = appearance(library, songKey);
  assert.equal(settings.allowTimedFallback, false);
  assert.equal(settings.allowPlainFallback, false);
  assert.equal(settings.tint, "#abcdef");
  // Old partial scenes retain settings inherited from the global appearance.
  library.settings.fontSize = 55;
  library.scenes[songKey] = { tint: "#111111" };
  assert.equal(appearance(library, songKey).fontSize, 55);
});

test("older scenes are sanitized and old clock sizes migrate without losing the library", () => {
  const saved = newLibrary();
  saved.settings.clockSize = 180;
  saved.scenes[songKey] = { clockSize: 60, allowPlainFallback: false, tint: "#123456" };
  const loaded = readLibrary(saved);
  assert.equal(loaded.settings.clockSize, 140);
  assert.equal(loaded.scenes[songKey].clockSize, 70);
  assert.ok(!("allowPlainFallback" in loaded.scenes[songKey]));
  assert.equal(loaded.scenes[songKey].tint, "#123456");
  assert.equal(saved.settings.clockSize, 180, "migration must not mutate input before persistence");
});

test("collection names use Mac uniqueness, trimming and 40-character bounds", () => {
  const library = newLibrary();
  assert.equal(collectionName(library, "  Night drives  "), "Night drives");
  for (const invalid of ["", " ", "LIKED", "favorités", "x".repeat(41)])
    assert.throws(() => collectionName(library, invalid));
  assert.equal(collectionName(library, "Liked", "liked"), "Liked");
  assert.equal(collectionName(library, "✨".repeat(40)), "✨".repeat(40));
});

test("supplied word ends preserve silence and backward seeks choose the original timestamp", () => {
  const lines = [
    { time: 2, text: "First light", words: [{ text: "First", time: 2, end: 2.5 }, { text: "light", time: 4, end: 5 }] },
    { time: 7, text: "", words: [] },
    { time: 10, text: "First light", words: [{ text: "First", time: 10, end: 10.5 }, { text: "light", time: 12, end: 13 }] },
  ];
  assert.equal(resolveLine(lines, 3).active, -1);
  assert.equal(resolveLine(lines, 4.1).active, 1);
  assert.equal(resolveLine(lines, 8).index, -1);
  assert.equal(resolveLine(lines, 12.1).active, 1);
  assert.equal(resolveLine(lines, 2.1).active, 0);
  assert.equal(positionAt({ position: 3, duration: 10, playing: false, received: 5 }, 9000), 3);
});

test("display token segmentation preserves decimal and ellipsis punctuation", () => {
  const split = (text) => resolveLine([{ time: 0, text, end: 10, words: [] }], 1, true, 10).words;
  assert.deepEqual(split("anymore.Like this;then that"), ["anymore.", "Like", "this;", "then", "that"]);
  assert.deepEqual(split("Wait...Now；go。Home don't 3.14"), ["Wait...", "Now；", "go。", "Home", "don't", "3.14"]);
  assert.deepEqual(split("[ (words) ] （bright） ✨ !!!"), ["words", "bright"]);
});

test("joined provider intervals only estimate emphasis when opted in, never source timestamps", () => {
  const line = { time: 0, text: "first.Next last", end: 6, words: [
    { text: "first.Next", time: 0, end: 4 }, { text: "last", time: 4, end: 6 },
  ] };
  const before = JSON.stringify(line);
  assert.equal(resolveLine([line], 3, true, 6).active, 1);
  assert.equal(resolveLine([line], 3, false, 6).active, 0);
  assert.equal(resolveLine([line], 4.1, false, 6).active, 2);
  assert.equal(JSON.stringify(line), before);
});

test("graphs page all words in bounded groups and backward seeks restore a page", () => {
  const line = { time: 0, text: Array.from({ length: 60 }, (_, i) => `word${i}`).join(" "), end: 60, words: [] };
  const lines = [line];
  const first = resolveLine(lines, 0, true, 60);
  assert.equal(first.words.length, 24);
  assert.equal(first.pageStart, 0);
  const last = resolveLine(lines, 59.9, true, 60);
  assert.equal(last.words.length, 12);
  assert.equal(last.pageStart, 48);
  assert.equal(last.words.at(-1), "word59");
  assert.deepEqual(resolveLine(lines, 0, true, 60), first);
  assert.deepEqual(resolveLine([{ time: 0, text: "one.two;three.four", end: 8, words: [] }], 7.9, true, 8, 2).words, ["three.", "four"]);
});

test("chorus memory recognizes substantial passages but never short repeated filler", () => {
  const rows = ["Carry this light", "Until we come home", "oh", "A new verse starts", "CARRY, THIS LIGHT!", "until we come home", "oh"];
  const lines = rows.map((text, i) => ({ time: i * 5, text, words: [] }));
  assert.equal(resolveLine(lines, 0.5, true, 40).layoutSeed, resolveLine(lines, 20.5, true, 40).layoutSeed);
  assert.equal(resolveLine(lines, 5.5, true, 40).layoutSeed, resolveLine(lines, 25.5, true, 40).layoutSeed);
  const fillers = [{ time: 0, text: "oh", words: [] }, { time: 5, text: "oh", words: [] }];
  assert.notEqual(resolveLine(fillers, .5, true, 10).layoutSeed, resolveLine(fillers, 5.5, true, 10).layoutSeed);
});

test("instrumental markers and sparse long holds yield to waves without erasing dense verses", () => {
  assert.equal(resolveLine([{ time: 0, text: "[instrumental]", words: [] }], 1, true, 30).index, -1);
  assert.equal(resolveLine([{ time: 0, text: "Only a few words", words: [] }], 20, true, 120).index, -1);
  const line = { time: 0, text: Array.from({ length: 30 }, (_, i) => `word${i}`).join(" "), words: [] };
  assert.equal(resolveLine([line], 100, true, 120).index, 0);
});

test("album-color collections resolve live artwork and survive persistence", async () => {
  const { collectionTint } = await import("../../linux/src/domain.js");
  const library = newLibrary();
  library.collections[0].songs.push(membership());
  library.collections[0].color = "album";
  assert.equal(appearance(library, songKey, "#010203").color, "#010203");
  assert.equal(appearance(library, songKey, "#aabbcc").color, "#aabbcc");
  assert.equal(readLibrary(library).collections[0].color, "album");
  assert.equal(collectionTint(library.collections[0], null, "#123456"), "#f066ab");
});

test("named saved swatches deduplicate canonical RGB and retain edited labels", async () => {
  const { saveColor } = await import("../../linux/src/domain.js");
  const library = newLibrary();
  saveColor(library, "#AABBCC", "Ocean");
  saveColor(library, "#aabbcc", "Evening");
  assert.equal(library.colors.length, 1);
  assert.equal(library.colors[0].name, "Evening");
  assert.equal(readLibrary(library).colors[0].color, "#aabbcc");
  assert.throws(() => saveColor(library, "#xyzxyz", "Invalid"));
});

test("selected alternative documents persist independently of original imports", () => {
  const library = newLibrary();
  library.matches[songKey] = { source: "lrclib", manualMatch: true, lines: [{ time: 1, text: "Chosen timing", words: [] }] };
  const loaded = readLibrary(JSON.parse(JSON.stringify(library)));
  assert.equal(loaded.matches[songKey].lines[0].text, "Chosen timing");
  assert.equal(loaded.matches[songKey].manualMatch, true);
  assert.deepEqual(loaded.imports, {});
});
