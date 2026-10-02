"""Fixture tests for tools/release/bootstrap_toolchain.py (stdlib only, no downloads)."""

import hashlib
import io
import json
import os
import platform
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "release"))
import bootstrap_toolchain as bt  # noqa: E402

REAL_LOCK = REPO / "tools" / "release" / "toolchain-lock.json"
HOST = {"system": platform.system(), "machine": [platform.machine().lower()]}


def make_zip(path, members):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in members.items():
            z.writestr(name, data)
    return path


def make_tar(path, members):
    """members: name -> bytes | ("sym", target) | ("hard", target)."""
    with tarfile.open(path, "w:gz") as t:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            if isinstance(data, tuple):
                info.type = tarfile.SYMTYPE if data[0] == "sym" else tarfile.LNKTYPE
                info.linkname = data[1]
                t.addfile(info)
            else:
                info.size = len(data)
                t.addfile(info, io.BytesIO(data))
    return path


def make_newc(entries):
    """cpio newc bytes (rpm2cpio's format). entries: name -> bytes | ("sym", target)."""
    out = bytearray()

    def add(name, mode, body):
        nb = name.encode() + b"\0"
        fields = [0, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(nb), 0]
        out.extend(b"070701" + b"".join(b"%08X" % v for v in fields) + nb)
        out.extend(b"\0" * (-len(out) % 4) + body)
        out.extend(b"\0" * (-len(out) % 4))

    for name, data in entries.items():
        if isinstance(data, tuple):
            add(name, 0o120777, data[1].encode())
        else:
            add(name, 0o100755, data)
    add("TRAILER!!!", 0, b"")
    return bytes(out)


def artifact(path, fmt, **extra):
    data = Path(path).read_bytes()
    return {"url": Path(path).as_uri(), "file": Path(path).name, "format": fmt,
            "algorithm": "sha256", "digest": hashlib.sha256(data).hexdigest(),
            "size": len(data), "version": "1", "license": "MIT",
            "provenance": "test fixture", **extra}


def fixture_lock(artifacts, tools, cmake=None, host=HOST, platform_key="linux-x86_64"):
    return {"schema_version": 1,
            "pins": {"engine": "4.7.2.stable", "velopack": "1.2.161"},
            "artifacts": artifacts,
            "platforms": {platform_key: {
                "host": host, "tools": tools,
                "cmake": cmake or {},
                "compiler": {"requirement": None, "status": "unproved"}}}}


class ToolchainTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.src = self.tmp / "src"
        self.src.mkdir()
        self.root = self.tmp / "work" / "root"
        self.cache = self.tmp / "work" / "cache"

    def tearDown(self):
        self._tmp.cleanup()

    def good_lock(self, version_txt=b"4.7.2.stable"):
        tpl = make_zip(self.src / "tpl.tpz", {"templates/version.txt": version_txt,
                                               "templates/linux_release.x86_64": b"x"})
        pkg = make_tar(self.src / "pkg.tar.gz", {"pkg/bin/tool": b"#!x\n", "pkg/lib": ("sym", "bin/tool")})
        return fixture_lock(
            {"tpl": artifact(tpl, "zip", pin="engine", version="4.7.2.stable"),
             "pkg": artifact(pkg, "tar")},
            {"templates": ["tpl", "templates"], "pkg": ["pkg", "pkg"]},
            cmake={"TORTUGA_PKG_ROOT": "pkg"})

    def fetch(self, lock, key="linux-x86_64"):
        return bt.fetch_toolchain(key, lock, self.root, cache=self.cache, allow_file=True)

    def outside_files(self):
        """Fixture-created names anywhere under tmp except inside a completed ROOT/bad extraction."""
        inside = self.root / "bad"
        return sorted(str(p) for p in self.tmp.rglob("*")
                      if p.name in ("evil", "escape", "abs", "PWNED_LINK") and inside not in p.parents)

    def assert_links_contained(self):
        root = os.path.realpath(self.root)
        for p in self.root.rglob("*"):
            if p.is_symlink():
                self.assertEqual(os.path.commonpath([root, os.path.realpath(p)]), root, str(p))

    def test_pin_and_templates_agree(self):
        lock = bt.load_lock(REAL_LOCK)
        self.assertEqual(lock["pins"], {"engine": "4.7.2.stable", "velopack": "1.2.161"})
        arts = lock["artifacts"]
        for key in ("linux-x86_64", "macos-universal", "windows-x86_64"):
            tools = lock["platforms"][key]["tools"]
            for tool in ("engine", "templates", "vpk", "velopack_sdk", "godot_cpp", "dotnet"):
                self.assertIn(tool, tools, f"{key} lacks {tool}")
            self.assertEqual(arts[tools["engine"][0]]["version"], "4.7.2.stable")
            self.assertEqual(arts[tools["templates"][0]]["version"], "4.7.2.stable")
            self.assertEqual(arts[tools["vpk"][0]]["version"], "1.2.161")
            self.assertEqual(arts[tools["velopack_sdk"][0]]["version"], "1.2.161")
        for name, art in arts.items():
            self.assertTrue(art["url"].startswith("https://"), name)
            self.assertEqual(len(art["digest"]), {"sha256": 64, "sha512": 128}[art["algorithm"]], name)
            self.assertGreater(art["size"], 0, name)
        cpp = arts[lock["platforms"]["linux-x86_64"]["tools"]["godot_cpp"][0]]
        self.assertRegex(cpp["commit"], r"^[0-9a-f]{40}$")
        self.assertIn(cpp["commit"], cpp["url"])
        self.assertEqual(bt.main(["verify", "--lock", str(REAL_LOCK)]), 0)
        with self.assertRaisesRegex(bt.ToolchainError, "https"):
            bt.validate_lock(self.good_lock())  # file:// is fixture-only, never accepted by default
        # Fetched templates whose version.txt disagrees with the engine pin are rejected.
        with self.assertRaisesRegex(bt.ToolchainError, "version.txt"):
            self.fetch(self.good_lock(version_txt=b"4.7.1.stable"))
        self.assertFalse((self.root / "toolchain.json").exists())

    def test_missing_hash_or_changed_bytes_rejected(self):
        lock = self.good_lock()
        for bad in ("", "abc", "g" * 64, None):
            broken = json.loads(json.dumps(lock))
            if bad is None:
                del broken["artifacts"]["pkg"]["digest"]
            else:
                broken["artifacts"]["pkg"]["digest"] = bad
            path = self.tmp / "lock.json"
            path.write_text(json.dumps(broken))
            with self.assertRaisesRegex(bt.ToolchainError, "digest"):
                bt.load_lock(path, allow_file=True)
            self.assertEqual(bt.main(["verify", "--lock", str(path)]), 1)
        del lock["artifacts"]["pkg"]["url"]
        (self.tmp / "lock.json").write_text(json.dumps(lock))
        with self.assertRaisesRegex(bt.ToolchainError, "missing url"):
            bt.load_lock(self.tmp / "lock.json", allow_file=True)
        for malformed in ({**self.good_lock(), "platforms": {"linux-x86_64": []}},
                          {**self.good_lock(), "artifacts": {"pkg": "nope"}}, []):
            (self.tmp / "lock.json").write_text(json.dumps(malformed))
            with self.assertRaises(bt.ToolchainError):
                bt.load_lock(self.tmp / "lock.json", allow_file=True)
            self.assertEqual(bt.main(["verify", "--lock", str(self.tmp / "lock.json")]), 1)

        blob = self.src / "blob"
        blob.write_bytes(b"hello")
        with self.assertRaises(bt.ToolchainError):
            bt.verify_artifact(blob, hashlib.sha256(b"hellO").hexdigest(), "sha256")
        with self.assertRaises(bt.ToolchainError):
            bt.verify_artifact(blob, "", "sha256")
        bt.verify_artifact(blob, hashlib.sha512(b"hello").hexdigest(), "sha512")

        # Source bytes differ from the locked digest: nothing cached, nothing extracted.
        lock = self.good_lock()
        data = bytearray((self.src / "pkg.tar.gz").read_bytes())
        data[-1] ^= 0x01  # same size, different bytes
        (self.src / "pkg.tar.gz").write_bytes(bytes(data))
        with self.assertRaisesRegex(bt.ToolchainError, "digest mismatch"):
            self.fetch(lock)
        self.assertFalse((self.cache / "pkg.tar.gz").exists())
        self.assertFalse((self.root / "pkg").exists())
        self.assertEqual(list(self.cache.glob("*.partial")), [])

        # A locked size that disagrees with the bytes is rejected too.
        lock = self.good_lock()
        lock["artifacts"]["pkg"]["size"] += 1
        with self.assertRaisesRegex(bt.ToolchainError, "size mismatch"):
            self.fetch(lock)
        self.assertFalse((self.cache / "pkg.tar.gz").exists())

    def test_extraction_traversal_and_symlink_escape_rejected(self):
        cases = {
            "zip-dotdot": ("zip", lambda p: make_zip(p, {"ok": b"1", "../evil": b"x"})),
            "zip-abs": ("zip", lambda p: make_zip(p, {"/tmp/abs": b"x"})),
            "tar-dotdot": ("tar", lambda p: make_tar(p, {"a/../../evil": b"x"})),
            "tar-abs": ("tar", lambda p: make_tar(p, {"/abs": b"x"})),
            "tar-symlink-out": ("tar", lambda p: make_tar(p, {"d/link": ("sym", "../../escape"),
                                                             "d/link/evil": b"x"})),
            "tar-symlink-abs": ("tar", lambda p: make_tar(p, {"link": ("sym", "/etc")})),
            "tar-hardlink-out": ("tar", lambda p: make_tar(p, {"hl": ("hard", "../escape")})),
            "zip-symlink": ("zip", self.zip_with_symlink),
            # Hardlink through a chained link that resolves above ROOT, onto an existing outside file.
            "tar-hardlink-via-symlink": ("tar", lambda p: make_tar(p, {
                "x": ("sym", "."), "q": ("sym", "x/x/x/../../.."), "h": ("hard", "q/secret")})),
        }
        secret = self.tmp / "secret"  # three levels above ROOT/.tmp-bad-*: where q would point
        secret.write_bytes(b"s")
        for name, (fmt, build) in cases.items():
            with self.subTest(name):
                arc = build(self.src / f"{name}.{fmt}")
                lock = fixture_lock({"bad": artifact(arc, fmt)}, {"bad": ["bad", "."]})
                with self.assertRaisesRegex(bt.ToolchainError, "unsafe archive member"):
                    self.fetch(lock)
                self.assertEqual(self.outside_files(), [])
                self.assertFalse((self.root / "bad").exists())
                self.assertEqual([p.name for p in self.root.iterdir() if p.name.startswith(".")], [])
                self.assertFalse((self.root / "toolchain.json").exists())
                self.assertEqual(secret.stat().st_nlink, 1)

        # Chained symlinks (x -> ., q -> x/x/x/../../.., q/PWNED_LINK) must never place anything
        # outside ROOT: rejected, or confined by the stdlib 'data' filter.
        arc = make_tar(self.src / "chain.tar", {"x": ("sym", "."), "q": ("sym", "x/x/x/../../.."),
                                                "q/PWNED_LINK": ("sym", "whatever")})
        try:
            self.fetch(fixture_lock({"bad": artifact(arc, "tar")}, {"bad": ["bad", "."]}))
        except bt.ToolchainError as exc:
            self.assertIn("unsafe archive member", str(exc))
        self.assertEqual(self.outside_files(), [])
        self.assert_links_contained()

        # cpio newc (rpm payload) parsing: '../' and absolute names rejected, a normal tree extracts.
        for name, entries in {"cpio-dotdot": {"./usr/../../evil": b"x"}, "cpio-abs": {"/abs": b"x"},
                              "cpio-symlink-out": {"./link": ("sym", "../../escape")}}.items():
            with self.subTest(name):
                dest = self.root / name
                dest.mkdir(parents=True)
                with self.assertRaisesRegex(bt.ToolchainError, "unsafe archive member"):
                    with bt._cpio_newc(make_newc(entries)) as tf:
                        bt._extract_tar(tf, dest)
                self.assertEqual(self.outside_files(), [])
        dest = self.root / "cpio-ok"
        dest.mkdir()
        with bt._cpio_newc(make_newc({"./usr/bin/tool": b"#!x\n", "./usr/bin/alias": ("sym", "tool")})) as tf:
            bt._extract_tar(tf, dest)
        self.assertEqual((dest / "usr/bin/alias").read_bytes(), b"#!x\n")
        self.assertTrue((dest / "usr/bin/alias").is_symlink())

    def zip_with_symlink(self, path):
        with zipfile.ZipFile(path, "w") as z:
            info = zipfile.ZipInfo("link")
            info.external_attr = 0o120777 << 16
            z.writestr(info, "target")
        return path

    def test_platform_mismatch_rejected(self):
        lock = self.good_lock()
        lock["platforms"]["linux-x86_64"]["host"] = {"system": "NoSuchOS", "machine": ["x86_64"]}
        with self.assertRaisesRegex(bt.ToolchainError, "host"):
            self.fetch(lock)
        self.assertFalse(self.cache.exists() and any(self.cache.iterdir()))
        with self.assertRaisesRegex(bt.ToolchainError, "platform"):
            self.fetch(self.good_lock(), key="windows-x86_64")
        real = bt.load_lock(REAL_LOCK)
        if bt.host_matches(real["platforms"]["windows-x86_64"]["host"]):
            self.skipTest("running on Windows")
        with self.assertRaisesRegex(bt.ToolchainError, "host"):
            bt.fetch_toolchain("windows-x86_64", real, self.root, cache=self.cache)
        out = self.tmp / "cli-out"
        self.assertEqual(bt.main(["fetch", "--platform", "windows-x86_64", "--lock", str(REAL_LOCK),
                                  "--output", str(out)]), 1)
        self.assertFalse(out.exists())

    def test_cache_reverified(self):
        lock = self.good_lock()
        receipt = self.fetch(lock)
        self.assertEqual(receipt["schema_version"], 1)
        self.assertEqual(receipt["platform"], "linux-x86_64")
        self.assertEqual(receipt["verified"]["templates_version"], "4.7.2.stable")
        for path in receipt["tools"].values():
            self.assertTrue(Path(path).is_absolute() and Path(path).exists(), path)
        self.assertTrue(all(isinstance(a, str) for a in receipt["cmake_args"]))
        self.assertIn(f"-DTORTUGA_PKG_ROOT={(self.root / 'pkg' / 'pkg').as_posix()}", receipt["cmake_args"])
        self.assertTrue((self.root / "pkg" / "pkg" / "lib").is_symlink())
        self.assertEqual(json.loads((self.root / "toolchain.json").read_text()), receipt)

        # Second run reuses the verified cache without touching the source URL.
        (self.src / "pkg.tar.gz").unlink()
        self.assertEqual(self.fetch(lock)["artifacts"]["pkg"]["digest"], lock["artifacts"]["pkg"]["digest"])

        cached = self.cache / "pkg.tar.gz"
        data = bytearray(cached.read_bytes())
        data[len(data) // 2] ^= 0x01
        cached.write_bytes(bytes(data))
        with self.assertRaisesRegex(bt.ToolchainError, "digest mismatch"):
            self.fetch(lock)
        self.assertFalse((self.root / "toolchain.json").exists())
        self.assertEqual(cached.read_bytes(), bytes(data))  # failed closed, not silently re-downloaded


if __name__ == "__main__":
    unittest.main()
