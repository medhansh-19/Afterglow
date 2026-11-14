import test from "node:test";
import assert from "node:assert/strict";
import { resolveLine, newLibrary, readLibrary } from "../src/domain.js";

test("brief rap pauses hold lyrics without highlighting finished words", () => {
  for (const gap of [0.2, 1, 1.5, 1.51, 4]) {
    for (const markers of [false, true]) {
      const lines = [
        { time: 0, end: 2, text: "Fast verse", words: [{ time: 0, end: 2, text: "Fast verse" }] },
        ...(markers ? [{ time: 2, text: "", words: [] }, { time: 2.1, text: "[Music]", words: [] }] : []),
        { time: 2 + gap, text: "Next verse", words: [] },
      ];
      for (const estimated of [false, true]) {
        // Deliberately resolve out of order to exercise backward seeks.
        for (const time of [2 + gap - 0.01, 2.01]) {
          const scene = resolveLine(lines, time, estimated, 12);
          assert.equal(scene.index, gap <= 1.5 ? 0 : -1);
          assert.equal(scene.active, -1);
          if (gap <= 1.5) {
            assert.ok(scene.words.length > 0);
            assert.ok(!scene.instrumental);
          }
        }
        assert.equal(resolveLine(lines, 2 + gap, estimated, 12).index, lines.length - 1);
      }
      assert.equal(resolveLine(lines, 12, true, 12).index, -1);
      assert.equal(resolveLine(lines, -1, true, 12).index, -1);
    }
  }
});

test("long gaps with several blank markers stay instrumental throughout", () => {
  const lines = [{ time: 0, end: 2, text: "Before", words: [] },
    { time: 2, text: "", words: [] }, { time: 3, text: "", words: [] },
    { time: 5, text: "After", words: [] }];
  for (const time of [2.1, 3.1, 4.99]) assert.equal(resolveLine(lines, time, true, 10).index, -1);
});

test("supplied word timing is the default and estimates remain an explicit choice", () => {
  assert.equal(newLibrary().settings.estimatedWords, false);
  const legacy = newLibrary();
  delete legacy.suppliedWordTimingDefaultApplied;
  legacy.settings.estimatedWords = true;
  legacy.scenes.song = { estimatedWords: true };
  const migrated = readLibrary(legacy);
  assert.equal(migrated.settings.estimatedWords, false);
  assert.equal(migrated.scenes.song.estimatedWords, false);
  assert.equal(legacy.scenes.song.estimatedWords, true, "migration does not mutate its input");
  migrated.settings.estimatedWords = true;
  migrated.scenes.song.estimatedWords = true;
  const chosen = readLibrary(JSON.parse(JSON.stringify(migrated)));
  assert.equal(chosen.settings.estimatedWords, true);
  assert.equal(chosen.scenes.song.estimatedWords, true);
});
