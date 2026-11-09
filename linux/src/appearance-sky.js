// Match Theme.appearanceSkyColors: bounded saturation and dark-to-slate depth.
export function appearanceSky(hex) {
  const rgb = /^#[0-9a-f]{6}$/i.test(hex) ? hex : "#b9a5ef";
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(rgb.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
  let hue = 0;
  if (delta) {
    hue = max === r ? (g - b) / delta : max === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
    hue = ((hue / 6) % 1 + 1) % 1;
  }
  const saturation = Math.min(.4, (max ? delta / max : 0) * .65);
  return [[.16, .55], [.28, .8], [.52, 1]].map(([value, strength]) => {
    const sat = saturation * strength;
    return "#" + [5, 3, 1].map((n) => {
      const k = (n + hue * 6) % 6;
      const channel = value * (1 - sat * Math.max(0, Math.min(k, 4 - k, 1)));
      return Math.round(channel * 255).toString(16).padStart(2, "0");
    }).join("");
  });
}
