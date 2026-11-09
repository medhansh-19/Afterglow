import test from "node:test";
import assert from "node:assert/strict";
import { createLyricRetries } from "../../linux/src/lyric-retry.js";

function clock() {
  let id = 0;
  const pending = new Map(), history = [];
  return {
    schedule(callback, delay) { pending.set(++id, callback); history.push(delay); return id; },
    unschedule(id) { pending.delete(id); },
    fire() { const [id, callback] = pending.entries().next().value; pending.delete(id); callback(); },
    pending, history,
  };
}
test("missing synced lyrics retry after 15 then 45 seconds and stop after two attempts", () => {
  const timer = clock(), retries = createLyricRetries(timer);
  let calls = 0;
  const result = () => retries.result({ document: { lines: [], plainText: "Unsynced text" } }, () => { calls++; result(); });
  result();
  assert.deepEqual(timer.history, [15000]);
  timer.fire();
  assert.equal(calls, 1);
  assert.deepEqual(timer.history, [15000, 45000]);
  timer.fire();
  assert.equal(calls, 2);
  assert.equal(timer.pending.size, 0);
});
test("timed, instrumental, imported, demo and disconnected results cancel retries", () => {
  for (const state of [
    { document: { lines: [{ time: 1, text: "timed" }] } },
    { document: { instrumental: true } }, { imported: true }, { demo: true }, { connected: false },
  ]) {
    const timer = clock(), retries = createLyricRetries(timer);
    retries.result({}, () => assert.fail("Canceled retry fired"));
    assert.equal(timer.pending.size, 1);
    retries.result(state, () => assert.fail("Ineligible retry fired"));
    assert.equal(timer.pending.size, 0);
  }
});
test("track changes/manual lookup reset retry budget and invalidate queued callbacks", () => {
  const timer = clock(), retries = createLyricRetries(timer);
  let calls = 0;
  retries.result({}, () => calls++);
  const callback = [...timer.pending.values()][0];
  retries.reset();
  callback();
  assert.equal(calls, 0);
  retries.result({}, () => calls++);
  assert.deepEqual(timer.history, [15000, 15000]);
});
