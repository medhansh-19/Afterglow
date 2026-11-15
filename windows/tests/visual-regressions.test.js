import test from "node:test";
import assert from "node:assert/strict";
import { ribbonMesh } from "../../linux/src/ribbon-mesh.js";
import { createWindowsBeat, windowsWaves } from "../../linux/src/windows-visuals.js";
import { appearanceSky } from "../../linux/src/appearance-sky.js";
import { createNotice } from "../../linux/src/notice.js";

test("waves reach both screen edges and stay within any aspect ratio", () => {
  for (const [width, height] of [[640, 480], [1920, 1080], [3440, 1440], [1080, 1920], [3840, 2160]]) {
    for (const reducedMotion of [false, true]) {
      for (const phase of [0, 2, 7]) {
        const mesh = ribbonMesh({ width, height, phase, reducedMotion, live: true, energy: .8, bands: Array(32).fill(.7) });
        for (const points of mesh) {
          assert.equal(points[0].x, 0);
          assert.equal(points.at(-1).x, width);
          assert.ok(points.every(({ x, y }) => x >= 0 && x <= width && y >= 0 && y <= height));
        }
      }
    }
  }
});
test("glass borrows lyric hue without brightening the sheet or tinting neutrals", () => {
  assert.deepEqual(appearanceSky("#ffffff"), ["#292929", "#474747", "#858585"]);
  assert.deepEqual(appearanceSky("#000000"), appearanceSky("#ffffff"));
  for (const hex of ["#ff0000", "#00ff00", "#0000ff", "#f7b566", "#22ccaa"]) {
    const sky = appearanceSky(hex);
    assert.equal(sky.length, 3);
    const values = sky.map((color) => [1, 3, 5].map((n) => parseInt(color.slice(n, n + 2), 16)));
    assert.deepEqual(values.map((c) => Math.max(...c)), [41, 71, 133]);
    assert.ok(values.every((c) => (Math.max(...c) - Math.min(...c)) / Math.max(...c) <= .41));
  }
  assert.notDeepEqual(appearanceSky("#ff0000"), appearanceSky("#0000ff"));
});
test("notices expire, replace safely, pause on interaction and dismiss", () => {
  let now = 0, id = 0, message = "", pending = new Map();
  const notifications = createNotice({ show: (text) => message = text, now: () => now,
    schedule: (fn, delay) => { pending.set(++id, { fn, at: now + delay }); return id; }, cancel: (id) => pending.delete(id) });
  const advance = (ms) => { now += ms; for (const [id, task] of [...pending]) if (task.at <= now) { pending.delete(id); task.fn(); } };
  notifications.show("First error", 8000);
  advance(7000);
  notifications.show("First error", 8000);
  advance(1000); assert.equal(message, "", "Repeated polling errors must not extend the notice forever");
  notifications.show("First error", 8000); assert.equal(message, "", "Repeated errors are suppressed briefly after dismissal");
  notifications.show("New error", 8000);
  advance(1000); assert.equal(message, "New error");
  notifications.pause(); advance(20000); assert.equal(message, "New error");
  notifications.resume(); advance(7000); assert.equal(message, "");
  notifications.show("Saved"); notifications.clear(); advance(10000); assert.equal(message, "");
  assert.equal(pending.size, 0);
});

test("quiet drum hits stay visible over steady audio between draws and then fade", () => {
  const detector = createWindowsBeat();
  const bassline = { level: .1, bands: Array(32).fill(.08) };
  const snare = { level: .12, bands: bassline.bands.map((value, i) => i >= 11 && i < 25 ? .12 : value) };
  for (let now = 0; now <= 640; now += 40) detector.receive(now, bassline);
  assert.equal(detector.frame(640), null);
  detector.receive(680, snare);
  detector.receive(720, bassline);
  const hit = detector.frame(755);
  assert.ok(hit.pulse >= .55);
  assert.equal(hit.bands, snare.bands);
  const mesh = windowsWaves(1920, 1080, hit.bands, hit.pulse, false, 755);
  const heights = mesh.flat().map(point => Math.abs(point.y - 540));
  assert.ok(Math.max(...heights) > 16);
  assert.ok(Math.max(...heights) < 110);
  for (let now = 760; now <= 1120; now += 40) detector.receive(now, bassline);
  assert.equal(detector.frame(1120), null);
  detector.receive(1160, snare);
  assert.ok(detector.frame(1160));
  assert.equal(detector.frame(1480), null);
});
