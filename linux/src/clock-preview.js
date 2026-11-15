// Web rendering of ClockFace in Sources/Afterglow/CustomClock.swift.
export const CLOCK_STYLES = [
  "Minimal",
  "Flip",
  "Rounded",
  "Glass",
  "Ring",
  "Analog",
  "Classic",
];
export const WINDOWS_CLOCK_STYLES = [...CLOCK_STYLES, "Split", "Editorial", "Orbit"];

export function clockMarkup(
  date,
  { clockStyle = "Minimal", format = "24", seconds = false } = {},
) {
  const hour = date.getHours(),
    minute = date.getMinutes(),
    second = date.getSeconds();
  const h =
      format === "12" ? String(hour % 12 || 12) : String(hour).padStart(2, "0"),
    m = String(minute).padStart(2, "0"),
    s = String(second).padStart(2, "0");
  const period =
    format === "12" ? `<small>${hour < 12 ? "AM" : "PM"}</small>` : "";
  if (clockStyle === "Flip")
    return `<span class="ag-clock-tiles">${[h, m, ...(seconds ? [s] : [])].map((value) => `<span>${value}</span>`).join("")}</span>${period}`;
  if (clockStyle === "Split")
    return `<span class="clock-split">${h}<span>${m}</span></span>${seconds ? `<small>${s}s</small>` : ""}${period}`;
  if (!["Ring", "Analog", "Classic", "Orbit"].includes(clockStyle))
    return `${h}:${m}${seconds ? ":" + s : ""}${period}`;
  const point = (angle, r) => [
    50 + Math.sin(angle) * r,
    50 - Math.cos(angle) * r,
  ];
  const hand = (angle, length, width, opacity) => {
    const [x, y] = point(angle, length);
    return `<line x1="50" y1="50" x2="${x}" y2="${y}" stroke-width="${width}" opacity="${opacity}" stroke-linecap="round"/>`;
  };
  const orbit = (angle, radius, size, opacity) => {
    const [x, y] = point(angle, radius);
    return `<circle cx="${x}" cy="${y}" r="${size}" fill="currentColor" opacity="${opacity}" stroke="none"/>`;
  };
  if (clockStyle === "Orbit")
    return `<svg class="ag-analog-clock" viewBox="0 0 100 100" role="img" aria-label="${h}:${m}"><g stroke="currentColor" fill="none"><circle cx="50" cy="50" r="29" opacity=".25"/><circle cx="50" cy="50" r="43" opacity=".4"/>${orbit(((hour % 12 + minute / 60) * Math.PI) / 6, 29, 5, .8)}${orbit((minute * Math.PI) / 30, 43, 4, 1)}${seconds ? orbit((second * Math.PI) / 30, 43, 2, .6) : ""}<text x="50" y="54" text-anchor="middle" fill="currentColor" stroke="none" font-size="12">${h}:${m}</text></g></svg>`;
  const face =
    clockStyle === "Analog"
      ? '<rect x="7" y="7" width="86" height="86" rx="18" fill="currentColor" opacity=".22"/><circle cx="50" cy="50" r="38" fill="black" opacity=".25"/>'
      : `<circle cx="50" cy="50" r="43" fill="none" stroke-width="${clockStyle === "Ring" ? 10 : 1.2}" opacity="${clockStyle === "Ring" ? 0.22 : 0.85}"/>`;
  const marks =
    clockStyle === "Classic"
      ? Array.from({ length: 12 }, (_, i) => {
          const n = i + 1,
            [x, y] = point((n * Math.PI) / 6, 33);
          return `<text x="${x}" y="${y + 3}" text-anchor="middle" fill="currentColor" stroke="none" font-family="Georgia,serif" font-size="10">${n}</text>`;
        }).join("")
      : clockStyle === "Ring"
        ? Array.from({ length: 60 }, (_, i) => {
            const angle = (i * Math.PI) / 30,
              [x1, y1] = point(angle, i % 5 ? 40 : 37),
              [x2, y2] = point(angle, 43);
            return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke-width="${i % 5 ? 0.7 : 1.7}" opacity="${i % 5 ? 0.45 : 1}"/>`;
          }).join("")
        : "";
  return `<svg class="ag-analog-clock" viewBox="0 0 100 100" role="img" aria-label="${h}:${m}"><g stroke="currentColor">${face}${marks}${hand((((hour % 12) + minute / 60) * Math.PI) / 6, 21, 3, 0.95)}${hand(((minute + (seconds ? second / 60 : 0)) * Math.PI) / 30, 32, 2, 0.85)}${seconds ? hand((second * Math.PI) / 30, 35, 0.8, 0.65) : ""}<circle cx="50" cy="50" r="2.5" fill="currentColor" stroke="none"/></g></svg>`;
}
