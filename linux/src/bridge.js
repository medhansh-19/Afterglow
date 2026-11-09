import { invoke } from "@tauri-apps/api/core";
import demo from "./demo.json";
export const native = !!window.__TAURI_INTERNALS__;
export const isWindows = /Windows/i.test(navigator.userAgent) || new URLSearchParams(location.search).get("platform") === "windows";
export const platformName = isWindows ? "Windows" : "Linux";
export async function call(command, args = {}) {
  if (native) return invoke(command, args);
  switch (command) {
    case "load_library":
      return JSON.parse(
        localStorage.getItem("afterglow-linux-preview") || "{}",
      );
    case "save_library":
      localStorage.setItem(
        "afterglow-linux-preview",
        JSON.stringify(args.library),
      );
      return;
    case "lyrics":
      if (args.request.command === "demo") return demo;
      break;
    case "audio_stop":
      return;
    case "players":
      return [];
  }
  throw Error(
    `This action needs the installed ${platformName} app. The browser preview supports the silent demo and appearance controls.`,
  );
}
export async function saveImage(canvas, name, copy = false) {
  const data = canvas.toDataURL("image/png");
  if (copy) {
    if (!native) throw Error("Image clipboard requires the installed app.");
    const { Image } = await import("@tauri-apps/api/image");
    const { writeImage } = await import("@tauri-apps/plugin-clipboard-manager");
    const bytes = Uint8Array.from(atob(data.split(",")[1]), (c) =>
      c.charCodeAt(0),
    );
    const image = await Image.fromBytes(bytes);
    try {
      await writeImage(image);
    } finally {
      await image.close();
    }
    return;
  }
  if (native) {
    const { save } = await import("@tauri-apps/plugin-dialog");
    const path = await save({
      defaultPath: name,
      filters: [{ name: "PNG image", extensions: ["png"] }],
    });
    if (path) await call("export_png", { path, data: data.split(",")[1] });
  } else {
    const link = document.createElement("a");
    link.download = name;
    link.href = data;
    link.click();
  }
}
