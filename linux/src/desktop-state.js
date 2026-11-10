import { defaults, positionAt, resolveLine } from "./domain.js";

// Each wallpaper has its own clock. Hidden-window timers never drive its words or audio.
export function createDesktopState() {
  let state = { settings: { ...defaults, color: defaults.tint }, lyrics: [], line: { words: [], active: -1, index: -1 }, track: null, sample: null, playing: false, audioActive: false, sleeping: false, onBattery: false };
  let received = -Infinity, audioAt = -Infinity, audio = { level: 0, bands: [] };
  return {
    receive(update, now) {
      state = { ...state, ...update, settings: { ...state.settings, ...update.settings } };
      if (Object.hasOwn(update, "sample")) state.sample = update.sample ? { ...update.sample, received: now } : null;
      received = now;
      if (!state.audioActive || !state.playing || state.sleeping) { audioAt = -Infinity; audio = { level: 0, bands: [] }; }
    },
    audio(frame, now) {
      if (!state.audioActive || state.sleeping || !state.playing) return;
      if (!Array.isArray(frame.bands) || frame.bands.length !== 32) return;
      audio = { level: Math.max(0, Math.min(1, Number(frame.level) || 0)), bands: frame.bands.map(v => Math.max(0, Math.min(1, Number(v) || 0))) };
      audioAt = now;
    },
    power(update, now = 0) {
      if (update.sleeping && state.sample) state.sample = { ...state.sample, position: positionAt(state.sample, now), received: now, playing: false };
      state = { ...state, ...update };
      if (state.sleeping) audioAt = -Infinity;
    },
    frame(now) {
      const fresh = now - received < 15000;
      const playing = fresh && state.playing && !state.sleeping;
      const sample = state.sample ? { ...state.sample, playing: state.playing && !state.sleeping && state.sample.playing } : null;
      const position = positionAt(sample, Math.min(now, received + 15000));
      const line = state.sample ? resolveLine(state.lyrics, position - (state.timing || 0), state.settings.estimatedWords, state.track?.duration || 120) : state.line;
      return { ...state, position, line, playing, audio: playing && state.audioActive && now - audioAt < 300 ? audio : { level: 0, bands: [] } };
    },
  };
}
