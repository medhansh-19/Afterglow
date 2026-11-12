import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime = load("stage-runtime")
package = load("measure-package")
hooks = load("generate-installer-hooks")


def pe_fixture(path, machine=0x8664, forwarder=None):
    """Small PE32+ with one ordinary import and one delayed import."""
    data = bytearray(4096)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3c, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", data, 0x84, machine, 1, 0, 0, 0, 240, 0x22)
    optional = 0x98
    struct.pack_into("<H", data, optional, 0x20b)
    struct.pack_into("<Q", data, optional + 24, 0x140000000)
    struct.pack_into("<II", data, optional + 32, 0x1000, 0x200)
    struct.pack_into("<II", data, optional + 56, 0x2000, 0x200)
    struct.pack_into("<I", data, optional + 108, 16)
    struct.pack_into("<II", data, optional + 112 + 8, 0x1000, 40)
    struct.pack_into("<II", data, optional + 112 + 13 * 8, 0x1300, 64)
    section = optional + 240
    data[section:section + 8] = b".rdata\0\0"
    struct.pack_into("<IIII", data, section + 8, 0xe00, 0x1000, 0xe00, 0x200)
    struct.pack_into("<I", data, section + 36, 0x40000040)
    struct.pack_into("<IIIII", data, 0x200, 0x1200, 0, 0, 0x1100, 0x1200)
    data[0x300:0x30e] = b"swiftCore.dll\0"
    struct.pack_into("<Q", data, 0x400, 0x8000000000000001)
    struct.pack_into("<IIIIIIII", data, 0x500, 1, 0x1400, 0, 0x1500, 0x1500, 0, 0, 0)
    data[0x600:0x60d] = b"delayed.dll\0\0"
    struct.pack_into("<Q", data, 0x700, 0x8000000000000001)
    if forwarder:
        struct.pack_into("<II", data, optional + 112, 0x1600, 0x100)
        struct.pack_into("<IIHHIIIIIII", data, 0x800, 0, 0, 0, 0, 0, 1, 1, 0, 0x1640, 0, 0)
        struct.pack_into("<I", data, 0x840, 0x1680)
        encoded = forwarder.encode("ascii") + b"\0"
        data[0x880:0x880 + len(encoded)] = encoded
    path.write_bytes(data)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dlls = self.root / "dlls"
        self.dlls.mkdir()
        self.system = self.root / "system"
        self.system.mkdir()
        self.binary = self.root / "helper.exe"
        self.binary.write_bytes(b"helper")
        self.graph = {"helper.exe": ["swiftcore.dll"]}

    def reader(self, path):
        return runtime.X64, self.graph.get(path.name.lower(), [])

    def dll(self, name, imports=(), content=None, root=None):
        path = (root or self.dlls) / name
        path.write_bytes(content or name.encode())
        self.graph[name.lower()] = list(imports)
        return path

    def stage(self, mode="imports", extra=None, roots=None):
        return runtime.stage(self.binary, roots or [self.dlls], self.system,
                             self.root / "staged", self.root / "report.json",
                             extra or {}, mode, self.reader)

    def test_reads_real_pe_regular_and_delay_imports(self):
        fixture = self.root / "fixture.exe"
        pe_fixture(fixture)
        machine, imports = runtime.inspect_pe(fixture)
        self.assertEqual(machine, runtime.X64)
        self.assertEqual(imports, ["delayed.dll", "swiftcore.dll"])

    def test_export_forwarder_adds_dependency_without_an_import_entry(self):
        fixture = self.root / "forwarder.dll"
        pe_fixture(fixture, forwarder="forwarded.Function")
        _, imports = runtime.inspect_pe(fixture)
        self.assertIn("forwarded.dll", imports)

    def test_recursive_cycle_system_and_unused_dlls(self):
        self.dll("swiftCore.dll", ["nested.dll", "KERNEL32.dll", "api-ms-win-core-test.dll"])
        self.dll("nested.dll", ["swiftcore.dll"])
        self.dll("unused.dll")
        (self.system / "kernel32.DLL").write_bytes(b"OS")
        report = self.stage()
        self.assertEqual({p.name.lower() for p in (self.root / "staged").iterdir()}, {"swiftcore.dll", "nested.dll"})
        self.assertEqual(report["excluded"], ["unused.dll"])
        self.assertEqual(report["excludedBytes"], len(b"unused.dll"))
        self.assertIn("kernel32.dll", report["systemImports"])

    def test_missing_transitive_dependency_fails_before_staging(self):
        self.dll("swiftCore.dll", ["missing.dll"])
        with self.assertRaisesRegex(ValueError, "missing.dll"):
            self.stage()
        self.assertFalse((self.root / "staged").exists())

    def test_private_dependency_cannot_be_satisfied_by_system32(self):
        self.dll("swiftCore.dll", ["vcruntime140.dll"])
        (self.system / "vcruntime140.dll").write_bytes(b"developer-installed")
        with self.assertRaisesRegex(ValueError, "Unresolved private DLL"):
            self.stage()

    def test_arbitrary_vendor_dll_in_system32_is_not_an_os_dependency(self):
        self.dll("swiftCore.dll", ["vendor.dll"])
        (self.system / "vendor.dll").write_bytes(b"developer-installed")
        with self.assertRaisesRegex(ValueError, "Unresolved private DLL"):
            self.stage()

    def test_dynamic_extra_is_traversed_and_reason_recorded(self):
        self.dll("swiftCore.dll")
        self.dll("extra.dll", ["nested.dll"])
        self.dll("nested.dll")
        report = self.stage(extra={"extra.dll": "loaded by Foundation at runtime"})
        self.assertEqual(len(report["files"]), 3)
        extra = next(row for row in report["files"] if row["name"] == "extra.dll")
        self.assertIn("runtime-loaded: loaded by Foundation at runtime", extra["requiredBy"])

    def test_conflicting_runtime_versions_fail(self):
        self.dll("swiftCore.dll")
        other = self.root / "other"
        other.mkdir()
        self.dll("swiftCore.dll", content=b"incompatible", root=other)
        with self.assertRaisesRegex(ValueError, "Conflicting copies"):
            self.stage(roots=[self.dlls, other])

    def test_identical_runtime_copies_are_deduplicated(self):
        self.dll("swiftCore.dll")
        other = self.root / "other"
        other.mkdir()
        self.dll("swiftCore.dll", root=other)
        self.assertEqual(len(self.stage(roots=[self.dlls, other])["files"]), 1)

    def test_full_mode_preserves_compatibility_and_excludes_compiler(self):
        self.dll("swiftCore.dll")
        self.dll("unused.dll")
        self.dll("LLVM.dll")
        report = self.stage(mode="full")
        self.assertEqual(len(report["files"]), 2)
        self.assertEqual(report["excludedBytes"], 0)

    def test_runtime_mode_keeps_unimported_application_runtime_libraries(self):
        self.dll("swiftCore.dll")
        self.dll("runtimeLoaded.dll", ["nested.dll"])
        self.dll("nested.dll")
        report = self.stage(mode="runtime")
        self.assertEqual(len(report["files"]), 3)
        self.assertEqual(report["excludedBytes"], 0)

    def test_runtime_mode_validates_dependencies_of_unimported_libraries(self):
        self.dll("swiftCore.dll")
        self.dll("runtimeLoaded.dll", ["missing.dll"])
        with self.assertRaisesRegex(ValueError, "missing.dll"):
            self.stage(mode="runtime")

    def test_wrong_architecture_rejected(self):
        fixture = self.root / "fixture.exe"
        pe_fixture(fixture, machine=0x14c)
        with self.assertRaisesRegex(ValueError, "x64"):
            runtime.select_runtime(fixture, {}, self.system, {}, "imports")

    def test_invalid_extra_name_rejected(self):
        self.dll("swiftCore.dll")
        with self.assertRaisesRegex(ValueError, "Invalid DLL name"):
            self.stage(extra={"../other.dll": "invalid"})

    def test_package_inventory_does_not_double_count_frontend(self):
        installed = self.root / "installed"
        (installed / "runtime").mkdir(parents=True)
        (installed / "afterglow-windows.exe").write_bytes(b"1234")
        (installed / "afterglow-lyrics.exe").write_bytes(b"12")
        (installed / "runtime" / "swiftCore.dll").write_bytes(b"123")
        installer = self.root / "setup.exe"
        installer.write_bytes(b"12")
        frontend = self.root / "frontend"
        frontend.mkdir()
        (frontend / "index.html").write_bytes(b"12345")
        report = package.measure(installer, installed, frontend)
        self.assertEqual(report["installedBytes"], 9)
        self.assertEqual(report["components"]["swiftRuntime"], 3)
        self.assertEqual(report["frontendBeforeEmbeddingBytes"], 5)
        baseline = json.loads(json.dumps(report))
        baseline["installer"]["bytes"] += 10
        self.assertEqual(package.compare(report, baseline)["installerBytes"], -10)
        output = self.root / "package.json"
        result = subprocess.run([sys.executable, str(SCRIPTS / "measure-package.py"),
                                 "--installer", str(installer), "--installed", str(installed),
                                 "--output", str(output), "--max-installer-bytes", "1"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(json.loads(output.read_text())["budgetViolations"]), 1)

    def test_checked_in_size_budget_and_invalid_values(self):
        path = self.root / "budget.json"
        path.write_text(json.dumps({"schemaVersion": 1, "maxInstallerBytes": 25, "maxInstalledBytes": 100}))
        self.assertEqual(package.load_budget(path), [25, 100])
        path.write_text(json.dumps({"schemaVersion": 1, "maxInstallerBytes": True, "maxInstalledBytes": 100}))
        with self.assertRaisesRegex(ValueError, "positive integer"):
            package.load_budget(path)
        self.assertEqual(package.load_budget(SCRIPTS.parent / "size-budget.json"), [25000000, 100000000])

    def test_cleanup_only_removes_historical_files_not_in_incoming_runtime(self):
        self.dll("Keep.DLL")
        self.dll("unknown-user-file.dll")
        source = self.root / "obsolete.json"
        source.write_text(json.dumps({"schemaVersion": 1, "libraries": ["keep.dll", "LTO.dll"]}))
        output = self.root / "hooks.nsh"
        self.assertEqual(hooks.generate(self.dlls, source, output), ["LTO.dll"])
        text = output.read_text()
        self.assertIn('NSIS_HOOK_POSTINSTALL', text)
        self.assertIn('Delete "$INSTDIR\\runtime\\LTO.dll"', text)
        self.assertNotIn('unknown-user-file.dll', text)
        self.assertNotIn('Delete "$INSTDIR\\runtime\\keep.dll"', text)
        self.assertNotIn('/REBOOTOK', text)

    def test_cleanup_rejects_paths_and_installer_code_injection(self):
        source = self.root / "obsolete.json"
        for name in ["../user.dll", 'bad$INSTDIR.dll', 'bad".dll', 'bad\\file.dll']:
            source.write_text(json.dumps({"schemaVersion": 1, "libraries": [name]}))
            with self.assertRaisesRegex(ValueError, "Invalid historical DLL"):
                hooks.generate(self.dlls, source, self.root / "hooks.nsh")


if __name__ == "__main__":
    unittest.main()
