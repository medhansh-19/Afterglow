"""Stage Windows x64 Swift DLLs with a reproducible dependency/size manifest.

Full mode preserves the previous broad runtime set. Imports mode is a candidate
for acceptance testing, not proof that dynamically loaded libraries are unused.
Only explicit runtime roots supply redistributables; System32 is never copied.
"""
import argparse
from collections import defaultdict, deque
import hashlib
import json
from pathlib import Path
import re
import shutil

import pefile

X64 = 0x8664
COMPILER_DLL = re.compile(r"^(libclang|libLTO|LLVM|sourcekit|IndexStore|swiftScan|swiftSyntax)", re.I)
# Explicit Windows 11 platform DLLs, not "anything found in System32". A
# developer-installed vendor library in System32 must not mask a missing private
# dependency. API-set contracts are handled separately by the Windows loader.
SYSTEM_DLLS = frozenset(name + ".dll" for name in """
advapi32 authz bcrypt bcryptprimitives cabinet cfgmgr32 comctl32 comdlg32
crypt32 cryptbase cryptsp cryptui dbghelp dhcpcsvc dhcpcsvc6 dnsapi dwmapi
gdi32 gdi32full imagehlp imm32 iphlpapi kernel32 kernelbase msasn1 msvcrt
mswsock ncrypt netapi32 netutils normaliz ntdll ntmarta ole32 oleaut32
powrprof profapi propsys psapi rasapi32 rasman rpcrt4 rtutils secur32 sensapi
setupapi shell32 shlwapi srvcli sspicli ucrtbase user32 userenv usp10 uxtheme
version winhttp wininet winmm winspool wintrust wldap32 ws2_32 wtsapi32
""".split())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inspect_pe(path):
    with pefile.PE(str(path), fast_load=True) as pe:
        pe.parse_data_directories(directories=[
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT"],
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"],
        ])
        imports = set()
        for table in ("DIRECTORY_ENTRY_IMPORT", "DIRECTORY_ENTRY_DELAY_IMPORT"):
            for entry in getattr(pe, table, []):
                name = entry.dll.decode("ascii").lower()
                validate_name(name)
                imports.add(name)
        # A private DLL can forward exports to another DLL without listing that
        # DLL in its import table. Conservatively include every such target.
        exports = getattr(pe, "DIRECTORY_ENTRY_EXPORT", None)
        for symbol in exports.symbols if exports else []:
            if symbol.forwarder:
                module, separator, _ = symbol.forwarder.decode("ascii").rpartition(".")
                if not separator:
                    raise ValueError(f"Malformed export forwarder in {path}")
                name = module.lower()
                if not name.endswith(".dll"):
                    name += ".dll"
                validate_name(name)
                imports.add(name)
        return pe.FILE_HEADER.Machine, sorted(imports)


def validate_name(name):
    if not re.fullmatch(r"[A-Za-z0-9_.+-]+\.dll", name, re.I) or ".." in name:
        raise ValueError(f"Invalid DLL name: {name!r}")


def inventory(roots, reader=inspect_pe):
    candidates = defaultdict(list)
    for root in roots:
        for path in sorted(root.iterdir(), key=lambda p: p.name.lower()):
            if not path.is_file() or path.suffix.lower() != ".dll" or COMPILER_DLL.match(path.name):
                continue
            machine, imports = reader(path)
            if machine == X64:
                candidates[path.name.lower()].append({
                    "path": path, "imports": imports, "sha256": digest(path),
                    "bytes": path.stat().st_size,
                })
    return candidates


def select_runtime(binary, candidates, system, extra, mode, reader=inspect_pe):
    machine, imports = reader(binary)
    if machine != X64:
        raise ValueError("The lyric helper must be Windows x64.")
    reasons = defaultdict(set)
    system_imports = set()
    queue = deque((name, binary.name) for name in imports)
    for name, reason in extra.items():
        validate_name(name)
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"Runtime-loaded DLL {name} needs a reason.")
        queue.append((name.lower(), f"runtime-loaded: {reason}"))
    selected = {}
    # Full mode intentionally reproduces the existing root precedence. Imports
    # mode refuses ambiguous versions instead of silently choosing a toolchain.
    if mode == "full":
        for name, choices in sorted(candidates.items()):
            selected[name] = choices[0]
            reasons[name].add("full runtime compatibility bundle")
        return selected, reasons, system_imports
    system_names = {p.name.lower() for p in system.iterdir() if p.is_file()}
    while queue:
        name, parent = queue.popleft()
        name = name.lower()
        if name.startswith(("api-ms-win-", "ext-ms-win-")):
            system_imports.add(name)
            continue
        choices = candidates.get(name, [])
        if not choices:
            if name in system_names and name in SYSTEM_DLLS:
                system_imports.add(name)
                continue
            raise ValueError(f"Unresolved private DLL {name}, required by {parent}")
        if len({choice["sha256"] for choice in choices}) != 1:
            paths = ", ".join(str(choice["path"]) for choice in choices)
            raise ValueError(f"Conflicting copies of {name}; pin runtime roots: {paths}")
        reasons[name].add(parent)
        if name in selected:
            continue
        selected[name] = choices[0]
        queue.extend((dependency, name) for dependency in choices[0]["imports"])
    return selected, reasons, system_imports


def stage(binary, roots, system, destination, report, extra, mode, reader=inspect_pe):
    candidates = inventory(roots, reader)
    selected, reasons, system_imports = select_runtime(binary, candidates, system, extra, mode, reader)
    if "swiftcore.dll" not in selected:
        raise ValueError("Swift core runtime is missing; refusing an incomplete package.")
    # Destination is a fresh temporary directory owned by the caller. Never
    # mutate the active runtime if dependency resolution fails.
    destination.mkdir(parents=True, exist_ok=True)
    if any(destination.iterdir()):
        raise ValueError("Staging destination must be empty.")
    files = []
    for name, item in sorted(selected.items()):
        shutil.copy2(item["path"], destination / item["path"].name)
        files.append({
            "name": item["path"].name, "source": str(item["path"].resolve()),
            "bytes": item["bytes"], "sha256": item["sha256"],
            "imports": item["imports"], "requiredBy": sorted(reasons[name]),
        })
    all_bytes = sum(choices[0]["bytes"] for choices in candidates.values())
    total = sum(item["bytes"] for item in files)
    result = {
        "schemaVersion": 1, "mode": mode,
        "acceptance": "unvalidated candidate" if mode == "imports" else "compatibility baseline",
        "helper": {"sha256": digest(binary), "bytes": binary.stat().st_size},
        "runtimeBytes": total, "fullRuntimeBytes": all_bytes,
        "excludedBytes": all_bytes - total,
        "systemImports": sorted(system_imports), "files": files,
        "excluded": sorted(set(candidates) - set(selected)),
        "conflicts": {name: [str(c["path"]) for c in choices]
                      for name, choices in sorted(candidates.items())
                      if len({c["sha256"] for c in choices}) > 1},
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Staged {len(files)} DLLs: {total:,} bytes ({all_bytes - total:,} fewer than full runtime).")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--roots", type=Path, required=True, help="JSON array of approved runtime roots")
    parser.add_argument("--system", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--extras", type=Path, required=True)
    parser.add_argument("--mode", choices=["full", "imports"], default="full")
    args = parser.parse_args()
    roots = [Path(p) for p in json.loads(args.roots.read_text(encoding="utf-8-sig"))]
    extra = json.loads(args.extras.read_text(encoding="utf-8-sig"))["libraries"]
    stage(args.binary, roots, args.system, args.destination, args.report, extra, args.mode)


if __name__ == "__main__":
    main()
