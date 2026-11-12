"""Report actual installer/installed bytes, without counting CI logs or caches.

Frontend bytes are informational: Tauri embeds them in the native executable,
so they are deliberately not added to the installed total a second time.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path


def file_row(path, root):
    with path.open("rb") as stream:
        sha = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"path": path.relative_to(root).as_posix(), "bytes": path.stat().st_size, "sha256": sha}


def component(path):
    path = path.lower()
    if path.startswith("runtime/"):
        return "swiftRuntime"
    if path.startswith("notices/"):
        return "notices"
    if path == "afterglow-windows.exe":
        return "nativeWithEmbeddedFrontend"
    if path == "afterglow-lyrics.exe":
        return "lyricHelper"
    return "other"


def measure(installer, installed, frontend=None):
    if not installed.is_dir():
        raise ValueError(f"Installed app directory not found: {installed}")
    for required in ("afterglow-windows.exe", "afterglow-lyrics.exe"):
        if not (installed / required).is_file():
            raise ValueError(f"Installed app missing {required}")
    rows = [file_row(p, installed) for p in sorted(installed.rglob("*")) if p.is_file()]
    totals = defaultdict(int)
    for row in rows:
        row["component"] = component(row["path"])
        totals[row["component"]] += row["bytes"]
    result = {
        "schemaVersion": 1, "installer": file_row(installer, installer.parent),
        "installedBytes": sum(row["bytes"] for row in rows),
        "components": dict(sorted(totals.items())), "files": rows,
        "excludes": ["shared WebView2 prerequisite", "user data and cache", "CI evidence"],
    }
    if frontend is not None:
        if not frontend.is_dir():
            raise ValueError(f"Frontend build directory not found: {frontend}")
        result["frontendBeforeEmbeddingBytes"] = sum(p.stat().st_size for p in frontend.rglob("*") if p.is_file())
    return result


def compare(current, baseline):
    return {
        "installerBytes": current["installer"]["bytes"] - baseline["installer"]["bytes"],
        "installedBytes": current["installedBytes"] - baseline["installedBytes"],
        "components": {key: current["components"].get(key, 0) - baseline["components"].get(key, 0)
                       for key in sorted(set(current["components"]) | set(baseline["components"]))},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--installed", type=Path, required=True)
    parser.add_argument("--frontend", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--max-installer-bytes", type=int)
    parser.add_argument("--max-installed-bytes", type=int)
    args = parser.parse_args()
    result = measure(args.installer, args.installed, args.frontend)
    if args.baseline:
        result["deltaFromBaseline"] = compare(result, json.loads(args.baseline.read_text(encoding="utf-8")))
    violations = []
    for actual, budget, label in (
        (result["installer"]["bytes"], args.max_installer_bytes, "installer"),
        (result["installedBytes"], args.max_installed_bytes, "installed"),
    ):
        if budget is not None and actual > budget:
            violations.append(f"{label}: {actual:,} bytes exceeds budget {budget:,}")
    result["budgetViolations"] = violations
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Installer: {result['installer']['bytes']:,} bytes; installed: {result['installedBytes']:,} bytes")
    for name, size in result["components"].items():
        print(f"  {name}: {size:,} bytes")
    if violations:
        raise SystemExit("\n".join(violations))


if __name__ == "__main__":
    main()
