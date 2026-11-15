// Match the Mac AlbumPalette population, saturation and luminance rules.
export function windowsAlbumAccent(rgba) {
  const bins = new Map();
  let opaque = 0, visible = 0, colorful = 0;
  for (let i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] <= 180) continue;
    opaque++;
    const rgb = [rgba[i], rgba[i + 1], rgba[i + 2]].map(value => value / 255);
    const high = Math.max(...rgb), low = Math.min(...rgb);
    if (high < .12) continue;
    visible++;
    if (high - low > .16) colorful++;
    const key = rgb.map(value => Math.floor(value * 7)).join("");
    const bin = bins.get(key) || { count: 0, sum: [0, 0, 0] };
    bin.count++;
    rgb.forEach((value, channel) => { bin.sum[channel] += value; });
    bins.set(key, bin);
  }
  if (!visible) return opaque ? "#e0e6f0" : null;
  const neutral = colorful / visible < .15;
  let best = null, bestScore = -1;
  for (const { count, sum } of bins.values()) {
    const rgb = sum.map(value => value / count);
    const saturation = 1 - Math.min(...rgb) / Math.max(...rgb);
    const score = count * (neutral ? (saturation < .18 ? 1.4 : .25) : .65 + saturation);
    if (score > bestScore) {
      best = rgb;
      bestScore = score;
    }
  }
  const boost = Math.max(1, .94 / Math.max(...best));
  let rgb = best.map(value => value * boost);
  const linear = value => value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  const luminance = ([r, g, b]) => .2126 * linear(r) + .7152 * linear(g) + .0722 * linear(b);
  for (let i = 0; i < 16 && luminance(rgb) < .18; i++)
    rgb = rgb.map(value => value + (1 - value) * .08);
  return "#" + rgb.map(value => Math.round(value * 255).toString(16).padStart(2, "0")).join("");
}

export function createWindowsBeat() {
  let lastFrame = -Infinity, lastHit = -Infinity, strength = 0, hitBands = [];
  let floor = [0, 0, 0];
  let previous = [0, 0, 0];
  return {
    reset() {
      lastFrame = lastHit = -Infinity;
      strength = 0;
      hitBands = [];
      floor = [0, 0, 0];
      previous = [0, 0, 0];
    },
    receive(now, { level, bands }) {
      if (bands?.length !== 32) return;
      if (now - lastFrame > 320) this.reset();
      lastFrame = now;
      const mean = (from, to) => bands.slice(from, to).reduce((sum, value) => sum + value, 0) / (to - from);
      // Follow kick, snare and overall level independently so a steady bassline
      // cannot mask a drum transient in a different band.
      const energy = [mean(0, 7), mean(11, 25), level || 0];
      let attack = 0;
      for (let i = 0; i < energy.length; i++) {
        const rise = energy[i] - previous[i];
        const aboveFloor = energy[i] - floor[i];
        if (energy[i] >= .035 && rise > .012 && aboveFloor > .018)
          attack = Math.max(attack, Math.min(rise * 5, aboveFloor * 3));
        floor[i] += aboveFloor * (aboveFloor > 0 ? .25 : .12);
      }
      previous = energy;
      if (attack && now - lastHit >= 125) {
        lastHit = now;
        strength = Math.max(.55, Math.min(1, attack));
        hitBands = bands;
      }
    },
    frame(now) {
      const age = now - lastHit;
      if (age >= 420 || now - lastFrame >= 320) return null;
      return { pulse: strength * Math.exp(-Math.max(0, age - 115) / 125), bands: hitBands };
    },
  };
}

export function windowsWaveMode(playing, words, beatEnabled, beat) {
  if (!playing || words.length) return null;
  if (!beatEnabled) return "standard";
  return beat ? "beat" : null;
}

export function windowsWaves(width, height, bands, pulse, animate, now) {
  if (pulse <= 0) return [];
  const amplitude = Math.min(height * .15, width * .12, 158) * pulse;
  const bass = bands.slice(0, 8).reduce((sum, value) => sum + value, 0);
  const treble = bands.slice(16).reduce((sum, value) => sum + value, 0);
  // Shorten the overtone wavelength as the spectral balance rises, while
  // keeping the broad curves of the main ribbon readable.
  const overtone = bands.length ? 2.8 + 3.2 * treble / Math.max(.1, treble + bass * 2) : 3.5;
  const phase = animate ? now / 570 : 0;
  return Array.from({ length: 17 }, (_, ribbon) => Array.from({ length: 121 }, (_, i) => {
    const x = i / 120;
    const layer = ribbon - 8;
    const fan = Math.sin(x * Math.PI) * (.65 + .35 * Math.sin(x * 7 - phase * .55));
    const primary = Math.sin(x * 3.2 * Math.PI - phase + layer * .09);
    const secondary = Math.sin(x * overtone * 2 * Math.PI + phase * .72 + layer * .13);
    return {
      x: x * width,
      y: height / 2 + amplitude * (.61 * primary + .22 * secondary + layer * .045 * fan),
    };
  }));
}
