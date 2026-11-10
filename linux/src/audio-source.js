// Never infer a Windows PID from a media-session identity, or choose a whole browser.
export function matchingAudioStream(streams, player, preferredBinary = null) {
  const binary = (value) => String(value || "").split(/[\\/]/).at(-1).toLowerCase();
  let names;
  if (preferredBinary) names = [binary(preferredBinary)];
  else {
    const identity = `${player?.identity || ""} ${player?.bus || ""}`.toLowerCase();
    if (identity.includes("spotify")) names = ["spotify.exe", "spotify"];
    else if (identity.includes("applemusic") || identity.includes("apple.music") || identity.includes("apple music")) names = ["applemusic.exe", "music.ui.exe"];
    else return null;
  }
  const matches = streams.filter((stream) => names.includes(binary(stream.binary)));
  return matches.length === 1 ? matches[0] : null;
}
export function audioStatus({ enabled, pending, active, playing, sleeping, visible, now, lastFrame, lastSignal, started, error }) {
  if (!enabled) return "Beat sync off";
  if (sleeping || !visible || !playing) return "Beat sync paused";
  if (pending) return "Connecting to player audio…";
  if (!active) return error || "Choose your player’s audio stream";
  if (now - started < 2000 && !lastFrame) return "Waiting for player audio…";
  if (!lastFrame || now - lastFrame > 2000) return "No audio received · Refresh or choose another player stream";
  if (!lastSignal || now - lastSignal > 3000) return "Player is silent · Protected playback may not support capture";
  return "Beat sync · Listening to player audio";
}
