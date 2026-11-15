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

export function windowsWaves(width, height, bands, pulse, animate, now) {
  if (!pulse || bands.length !== 32) return [];
  const amplitude = Math.min(height * .105, width * .085, 88) * pulse;
  // Log-spaced WASAPI bands map to shorter wavelengths as frequency rises.
  // Each band's measured energy controls height independently of wavelength.
  const harmonics = Array.from({ length: 8 }, (_, i) => {
    const group = bands.slice(i * 4, i * 4 + 4);
    return { cycles: 1.5 * 1.35 ** i, strength: Math.max(...group) ** 2 / (i + 1) ** .6 };
  });
  const total = Math.max(.001, harmonics.reduce((sum, band) => sum + band.strength, 0));
  const phase = animate ? now / 440 : 0;
  return Array.from({ length: 7 }, (_, ribbon) => Array.from({ length: 161 }, (_, i) => {
    const x = i / 160;
    const wave = harmonics.reduce((sum, { cycles, strength }, band) =>
      sum + strength * Math.sin(x * cycles * 2 * Math.PI - phase * (1 + band * .24) + ribbon * .13), 0);
    return {
      x: x * width,
      y: height / 2 + amplitude * Math.sin(Math.PI * x) * (wave / total + (ribbon - 3) * .09),
    };
  }));
}
