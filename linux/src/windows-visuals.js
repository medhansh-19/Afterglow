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
  let previous = null, bassFloor = 0, pulse = 0, peakAt = -Infinity;
  return (now, audio, dt) => {
    pulse *= Math.exp(-dt * 10);
    if (audio.bands?.length !== 32) {
      previous = null;
      bassFloor = 0;
      pulse = 0;
      peakAt = -Infinity;
      return 0;
    }
    if (audio !== previous) {
      const bass = audio.bands.slice(0, 8).reduce((sum, band) => sum + band, 0) / 8;
      const onset = bass - bassFloor;
      if (bass > .12 && onset > .065 && now - peakAt >= 135) {
        pulse = Math.min(1, onset * 3);
        peakAt = now;
      }
      bassFloor += onset * (onset > 0 ? .28 : .17);
      previous = audio;
    }
    return pulse > .045 ? pulse : 0;
  };
}

export function windowsWaves(width, height, bands, pulse, animate, now) {
  if (!pulse || bands.length !== 32) return [];
  const amplitude = Math.min(height * .085, width * .07, 76) * pulse;
  // Log-spaced WASAPI bands map to shorter wavelengths as frequency rises.
  // Each band's measured energy controls height independently of wavelength.
  const harmonics = Array.from({ length: 8 }, (_, i) => {
    const group = bands.slice(i * 4, i * 4 + 4);
    return { cycles: 1.5 * 1.35 ** i, strength: Math.max(...group) ** 2 / (i + 1) ** .6 };
  });
  const total = Math.max(1, harmonics.reduce((sum, band) => sum + band.strength, 0));
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
