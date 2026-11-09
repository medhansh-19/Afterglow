// Bounded missing-synced retries, shared with fake-timer regression checks.
export function createLyricRetries({ schedule = setTimeout, unschedule = clearTimeout } = {}) {
  let timer = null, generation = 0, attempt = 0;
  const cancel = () => { generation++; if (timer !== null) unschedule(timer); timer = null; };
  return {
    reset() { cancel(); attempt = 0; },
    cancel,
    result({ document, imported = false, demo = false, connected = true }, retry) {
      cancel();
      if (!connected || imported || demo || document?.instrumental || document?.lines?.length || attempt >= 2) return;
      const current = generation, delay = [15000, 45000][attempt++];
      timer = schedule(() => { timer = null; if (current === generation) retry(); }, delay);
    },
  };
}
